import { hostname, networkInterfaces } from "node:os";
import type { FoldStateEvent, UserActionResponse } from "@fold/runtime";
import { WebSocket } from "undici";
import { accountApiBase } from "./account-sync.js";
import {
	clearAccountSecret,
	clearRemoteDeviceSecret,
	loadAccountSecret,
	loadRemoteDeviceSecret,
	saveRemoteDeviceSecret,
} from "./secure-store.js";

type RemoteDeviceSecret = {
	apiBase: string;
	deviceId: string;
	token: string;
};

type PairingResult = {
	pairingId: string;
	deviceId: string;
	deviceToken: string;
	code: string;
	qrPayload: string;
	expiresAt: string;
};

type RemoteHandlers = {
	executeTask: (intent: string) => Promise<void>;
	handleInteractionResponse: (response: UserActionResponse) => Promise<void>;
};

let handlers: RemoteHandlers | null = null;
let socket: WebSocket | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let heartbeatTimer: ReturnType<typeof setInterval> | null = null;
let reconnectAttempt = 0;
let stopped = true;
let connectionState: "disabled" | "connecting" | "connected" | "error" = "disabled";
let lastError: string | null = null;
let activeTurn: { turnId: string; threadId: string } | null = null;
const forwardedInteractions = new Set<string>();

function loadDeviceSecret(): RemoteDeviceSecret | null {
	const raw = loadRemoteDeviceSecret();
	if (!raw) return null;
	try {
		const parsed = JSON.parse(raw) as Partial<RemoteDeviceSecret>;
		return parsed.apiBase && parsed.deviceId && parsed.token
			? {
					apiBase: parsed.apiBase,
					deviceId: parsed.deviceId,
					token: parsed.token,
				}
			: null;
	} catch {
		return null;
	}
}

function privateLanAddress(): string | null {
	const interfaces = networkInterfaces();
	const names = [
		...["en0", "en1"].filter((name) => interfaces[name]),
		...Object.keys(interfaces).filter((name) => name !== "en0" && name !== "en1"),
	];
	let fallback: string | null = null;
	for (const name of names) {
		for (const address of interfaces[name] ?? []) {
			if (address.family !== "IPv4" || address.internal) continue;
			fallback ??= address.address;
			if (
				address.address.startsWith("10.")
				|| address.address.startsWith("192.168.")
				|| /^172\.(1[6-9]|2\d|3[01])\./.test(address.address)
			) {
				return address.address;
			}
		}
	}
	return fallback;
}

function publicAccountUrl(base: string): string {
	const url = new URL(base);
	if (url.hostname === "127.0.0.1" || url.hostname === "localhost") {
		const lan = privateLanAddress();
		if (lan) url.hostname = lan;
	}
	return url.toString().replace(/\/$/, "");
}

async function accountRequest<T>(
	path: string,
	init: RequestInit & { apiKey?: string } = {},
	base = accountApiBase(),
): Promise<T> {
	const headers = new Headers(init.headers);
	headers.set("Content-Type", "application/json");
	if (init.apiKey) headers.set("Authorization", `Bearer ${init.apiKey}`);
	const response = await fetch(`${base.replace(/\/$/, "")}${path}`, { ...init, headers });
	if (!response.ok) {
		const body = (await response.json().catch(() => null)) as { error?: string } | null;
		if (response.status === 401 && init.apiKey) {
			clearAccountSecret();
			throw new Error("登录已失效，请到「账户」重新登录");
		}
		throw new Error(body?.error ?? `account-api ${response.status}`);
	}
	return (await response.json()) as T;
}

function wsUrl(secret: RemoteDeviceSecret): string {
	const url = new URL(secret.apiBase);
	url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
	url.pathname = "/remote/ws/mac";
	url.search = `?token=${encodeURIComponent(secret.token)}`;
	return url.toString();
}

function send(payload: unknown): void {
	if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(payload));
}

function clearTimers(): void {
	if (reconnectTimer) clearTimeout(reconnectTimer);
	if (heartbeatTimer) clearInterval(heartbeatTimer);
	reconnectTimer = null;
	heartbeatTimer = null;
}

function scheduleReconnect(): void {
	if (stopped || reconnectTimer || !loadDeviceSecret()) return;
	const delay = Math.min(30_000, 1_000 * 2 ** reconnectAttempt);
	reconnectAttempt += 1;
	reconnectTimer = setTimeout(() => {
		reconnectTimer = null;
		connectRemoteRelay();
	}, delay);
}

function handleRelayMessage(raw: unknown): void {
	let frame: Record<string, unknown>;
	try {
		const text =
			typeof raw === "string"
				? raw
				: raw instanceof ArrayBuffer
					? new TextDecoder().decode(raw)
					: String(raw);
		frame = JSON.parse(text) as Record<string, unknown>;
	} catch {
		return;
	}
	if (frame.type === "registered") {
		connectionState = "connected";
		lastError = null;
		reconnectAttempt = 0;
		return;
	}
	if (
		frame.type === "task.dispatch" &&
		typeof frame.turnId === "string" &&
		typeof frame.threadId === "string" &&
		typeof frame.intent === "string"
	) {
		if (!handlers || activeTurn) return;
		activeTurn = { turnId: frame.turnId, threadId: frame.threadId };
		forwardedInteractions.clear();
		void handlers.executeTask(frame.intent).catch((error) => {
			forwardRemoteState({
				status: "error",
				error: error instanceof Error ? error.message : String(error),
			});
		});
		return;
	}
	if (frame.type === "approval.resolve" && frame.response && handlers) {
		void handlers.handleInteractionResponse(frame.response as UserActionResponse);
	}
}

function connectRemoteRelay(): void {
	if (stopped || socket?.readyState === WebSocket.OPEN) return;
	const secret = loadDeviceSecret();
	if (!secret) {
		connectionState = "disabled";
		return;
	}
	connectionState = "connecting";
	const next = new WebSocket(wsUrl(secret));
	socket = next;
	next.addEventListener("open", () => {
		send({
			type: "hello",
			deviceId: secret.deviceId,
			hostname: hostname(),
			activeTurnId: activeTurn?.turnId ?? null,
		});
		heartbeatTimer = setInterval(() => {
			send({ type: "heartbeat", activeTurnId: activeTurn?.turnId ?? null });
		}, 15_000);
	});
	next.addEventListener("message", (event) => handleRelayMessage(event.data));
	next.addEventListener("error", () => {
		lastError = "WebSocket 连接失败";
		connectionState = "error";
	});
	next.addEventListener("close", () => {
		if (socket === next) socket = null;
		if (heartbeatTimer) clearInterval(heartbeatTimer);
		heartbeatTimer = null;
		if (!stopped) scheduleReconnect();
	});
}

export function configureRemoteRelay(nextHandlers: RemoteHandlers): void {
	handlers = nextHandlers;
}

export function startRemoteRelay(): void {
	stopped = false;
	connectRemoteRelay();
}

export function stopRemoteRelay(): void {
	stopped = true;
	clearTimers();
	socket?.close(1000, "app_quit");
	socket = null;
	connectionState = loadDeviceSecret() ? "error" : "disabled";
	activeTurn = null;
}

export function forwardRemoteState(state: FoldStateEvent): void {
	if (!activeTurn) return;
	if (state.status === "ask" && state.interaction) {
		const requestId = state.interaction.id;
		if (!forwardedInteractions.has(requestId)) {
			forwardedInteractions.add(requestId);
			send({
				type: "approval.request",
				turnId: activeTurn.turnId,
				request: state.interaction,
			});
		}
	}
	const terminal = state.status === "done" || state.status === "error";
	const status =
		state.status === "done"
			? "completed"
			: state.status === "error"
				? "failed"
				: state.status === "ask"
					? "awaiting_approval"
					: "running";
	send({
		type: "turn.state",
		turnId: activeTurn.turnId,
		threadId: activeTurn.threadId,
		status,
		state,
	});
	if (terminal) {
		activeTurn = null;
		forwardedInteractions.clear();
	}
}

export async function startRemotePairing(): Promise<PairingResult> {
	const apiKey = loadAccountSecret();
	if (!apiKey) throw new Error("请先登录知更账户");
	const base = accountApiBase();
	const pairing = await accountRequest<PairingResult>(
		"/devices/pairing/start",
		{
			method: "POST",
			apiKey,
			body: JSON.stringify({
				deviceName: hostname(),
				publicUrl: publicAccountUrl(base),
			}),
		},
		base,
	);
	saveRemoteDeviceSecret(
		JSON.stringify({
			apiBase: base,
			deviceId: pairing.deviceId,
			token: pairing.deviceToken,
		} satisfies RemoteDeviceSecret),
	);
	return pairing;
}

export async function pollRemotePairing(pairingId: string) {
	const apiKey = loadAccountSecret();
	if (!apiKey) throw new Error("请先登录知更账户");
	const result = await accountRequest<{
		status: "pending" | "claimed" | "expired" | "canceled";
		claimedDeviceId?: string | null;
	}>(`/devices/pairing/${encodeURIComponent(pairingId)}/status`, { apiKey });
	if (result.status === "claimed") startRemoteRelay();
	return result;
}

export async function listRemoteDevices() {
	const apiKey = loadAccountSecret();
	if (!apiKey) return { devices: [] };
	return accountRequest<{
		devices: Array<{
			id: string;
			kind: "mac" | "ios";
			name: string;
			lastSeenAt: string | null;
			revokedAt: string | null;
		}>;
	}>("/devices", { apiKey });
}

export async function revokeRemoteDevice(deviceId: string): Promise<{ ok: true }> {
	const apiKey = loadAccountSecret();
	if (!apiKey) throw new Error("请先登录知更账户");
	const result = await accountRequest<{ ok: true }>(
		`/devices/${encodeURIComponent(deviceId)}`,
		{ method: "DELETE", apiKey },
	);
	const secret = loadDeviceSecret();
	if (secret?.deviceId === deviceId) {
		stopRemoteRelay();
		clearRemoteDeviceSecret();
		connectionState = "disabled";
	}
	return result;
}

export function getRemoteRelayStatus() {
	const secret = loadDeviceSecret();
	return {
		configured: Boolean(secret),
		deviceId: secret?.deviceId ?? null,
		state: connectionState,
		error: lastError,
	};
}
