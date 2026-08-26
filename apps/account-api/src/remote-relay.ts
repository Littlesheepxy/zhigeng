import type { Server } from "node:http";
import { WebSocket, WebSocketServer } from "ws";
import { resolveUserFromBearer } from "./auth.js";
import {
	appendRemoteEvent,
	createRemoteApproval,
	getRemoteTurn,
	isDevicePaired,
	markDeviceSeen,
	resolveDeviceToken,
	updateRemoteTurn,
	type RemoteTurn,
} from "./remote-store.js";

type MacConnection = {
	deviceId: string;
	userId: string;
	socket: WebSocket;
	busyTurnId: string | null;
};

const macs = new Map<string, MacConnection>();
const phones = new Map<string, Set<WebSocket>>();

function tokenFromRequest(request: {
	headers: { authorization?: string };
	url?: string;
}): string {
	const bearer = request.headers.authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
	if (bearer) return bearer;
	const url = new URL(request.url ?? "/", "http://localhost");
	return url.searchParams.get("token") ?? "";
}

function send(socket: WebSocket, payload: unknown): void {
	if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(payload));
}

function broadcast(userId: string, payload: unknown): void {
	for (const socket of phones.get(userId) ?? []) send(socket, payload);
}

function activeMac(userId: string): MacConnection | undefined {
	return [...macs.values()].find(
		(connection) =>
			connection.userId === userId && connection.socket.readyState === WebSocket.OPEN,
	);
}

function handleMacMessage(connection: MacConnection, raw: WebSocket.RawData): void {
	let frame: Record<string, unknown>;
	try {
		frame = JSON.parse(raw.toString()) as Record<string, unknown>;
	} catch {
		send(connection.socket, { type: "error", error: "invalid_json" });
		return;
	}

	if (frame.type === "heartbeat") {
		markDeviceSeen(connection.deviceId);
		if (typeof frame.activeTurnId === "string") {
			const active = getRemoteTurn(connection.userId, frame.activeTurnId);
			if (active && !["completed", "failed", "canceled"].includes(active.status)) {
				connection.busyTurnId = active.id;
			}
		}
		send(connection.socket, { type: "pong", timestamp: Date.now() });
		return;
	}
	if (frame.type === "hello") {
		if (typeof frame.activeTurnId === "string") {
			const active = getRemoteTurn(connection.userId, frame.activeTurnId);
			if (active && !["completed", "failed", "canceled"].includes(active.status)) {
				connection.busyTurnId = active.id;
			}
		}
		send(connection.socket, { type: "registered", deviceId: connection.deviceId });
		return;
	}
	if (typeof frame.turnId !== "string") {
		send(connection.socket, { type: "error", error: "turn_id_required" });
		return;
	}
	const turn = getRemoteTurn(connection.userId, frame.turnId);
	if (!turn) {
		send(connection.socket, { type: "error", error: "turn_not_found" });
		return;
	}

	if (frame.type === "turn.state") {
		const status = typeof frame.status === "string" ? frame.status : "running";
		updateRemoteTurn({ userId: connection.userId, turnId: turn.id, status });
		const event = appendRemoteEvent({
			userId: connection.userId,
			threadId: turn.threadId,
			turnId: turn.id,
			type: "state",
			payload: frame.state ?? { status },
		});
		if (["completed", "failed", "canceled"].includes(status)) connection.busyTurnId = null;
		broadcast(connection.userId, {
			type: "turn.updated",
			turnId: turn.id,
			threadId: turn.threadId,
			status,
			event,
		});
		return;
	}

	if (frame.type === "approval.request") {
		const request =
			frame.request && typeof frame.request === "object"
				? (frame.request as Record<string, unknown>)
				: {};
		const requestId =
			typeof request.id === "string"
				? request.id
				: typeof frame.requestId === "string"
					? frame.requestId
					: `${turn.id}:approval`;
		const prompt =
			typeof request.message === "string"
				? request.message
				: typeof request.title === "string"
					? request.title
					: "需要确认";
		const approval = createRemoteApproval({
			userId: connection.userId,
			threadId: turn.threadId,
			turnId: turn.id,
			clientRequestId: `${turn.id}:${requestId}`,
			kind: typeof request.kind === "string" ? request.kind : "confirm",
			prompt,
			request,
			expiresAt: typeof request.expiresAt === "string" ? request.expiresAt : undefined,
		});
		updateRemoteTurn({
			userId: connection.userId,
			turnId: turn.id,
			status: "awaiting_approval",
		});
		broadcast(connection.userId, {
			type: "approval.requested",
			turnId: turn.id,
			threadId: turn.threadId,
			approval,
			request,
		});
		return;
	}

	if (frame.type === "turn.result") {
		const status = frame.error ? "failed" : "completed";
		updateRemoteTurn({ userId: connection.userId, turnId: turn.id, status });
		const event = appendRemoteEvent({
			userId: connection.userId,
			threadId: turn.threadId,
			turnId: turn.id,
			type: "result",
			payload: { result: frame.result ?? null, error: frame.error ?? null },
		});
		connection.busyTurnId = null;
		broadcast(connection.userId, {
			type: "turn.updated",
			turnId: turn.id,
			threadId: turn.threadId,
			status,
			event,
		});
		return;
	}

	send(connection.socket, { type: "error", error: "unsupported_frame" });
}

export function attachRemoteRelay(server: Server): void {
	const macServer = new WebSocketServer({ noServer: true, maxPayload: 256 * 1024 });
	const phoneServer = new WebSocketServer({ noServer: true, maxPayload: 256 * 1024 });

	server.on("upgrade", (request, socket, head) => {
		const url = new URL(request.url ?? "/", "http://localhost");
		const token = tokenFromRequest(request);

		if (url.pathname === "/remote/ws/mac") {
			const device = resolveDeviceToken(token);
			if (!device || device.kind !== "mac" || !isDevicePaired(device.userId, device.deviceId)) {
				socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
				socket.destroy();
				return;
			}
			macServer.handleUpgrade(request, socket, head, (ws) => {
				macServer.emit("connection", ws, request, device);
			});
			return;
		}

		if (url.pathname === "/remote/ws/phone") {
			const user = resolveUserFromBearer(`Bearer ${token}`);
			if (!user) {
				socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
				socket.destroy();
				return;
			}
			phoneServer.handleUpgrade(request, socket, head, (ws) => {
				phoneServer.emit("connection", ws, request, user.id);
			});
			return;
		}

		socket.write("HTTP/1.1 404 Not Found\r\n\r\n");
		socket.destroy();
	});

	macServer.on(
		"connection",
		(socket: WebSocket, _request: unknown, device: { deviceId: string; userId: string }) => {
			const previous = macs.get(device.deviceId);
			previous?.socket.close(4001, "replaced");
			const connection: MacConnection = {
				deviceId: device.deviceId,
				userId: device.userId,
				socket,
				busyTurnId: null,
			};
			macs.set(device.deviceId, connection);
			markDeviceSeen(device.deviceId);
			send(socket, { type: "registered", deviceId: device.deviceId });
			broadcast(device.userId, { type: "presence", deviceId: device.deviceId, online: true });
			socket.on("message", (data) => handleMacMessage(connection, data));
			socket.on("close", () => {
				if (macs.get(device.deviceId)?.socket === socket) macs.delete(device.deviceId);
				broadcast(device.userId, {
					type: "presence",
					deviceId: device.deviceId,
					online: false,
				});
			});
		},
	);

	phoneServer.on("connection", (socket: WebSocket, _request: unknown, userId: string) => {
		const subscribers = phones.get(userId) ?? new Set<WebSocket>();
		subscribers.add(socket);
		phones.set(userId, subscribers);
		const mac = activeMac(userId);
		send(socket, {
			type: "presence",
			deviceId: mac?.deviceId ?? null,
			online: Boolean(mac),
		});
		socket.on("close", () => {
			subscribers.delete(socket);
			if (subscribers.size === 0) phones.delete(userId);
		});
	});
}

export function dispatchRemoteTurn(input: {
	userId: string;
	turn: RemoteTurn;
}): boolean {
	const mac = activeMac(input.userId);
	if (!mac || mac.busyTurnId) return false;
	mac.busyTurnId = input.turn.id;
	updateRemoteTurn({ userId: input.userId, turnId: input.turn.id, status: "dispatched" });
	send(mac.socket, {
		type: "task.dispatch",
		turnId: input.turn.id,
		threadId: input.turn.threadId,
		intent: input.turn.content,
		clientRequestId: input.turn.clientRequestId,
	});
	return true;
}

export function sendApprovalToMac(input: {
	userId: string;
	turnId: string;
	approvalId: string;
	response: unknown;
}): boolean {
	const mac = activeMac(input.userId);
	if (!mac || mac.busyTurnId !== input.turnId) return false;
	send(mac.socket, {
		type: "approval.resolve",
		turnId: input.turnId,
		approvalId: input.approvalId,
		response: input.response,
	});
	updateRemoteTurn({ userId: input.userId, turnId: input.turnId, status: "running" });
	return true;
}

export function canSendApprovalToMac(userId: string, turnId: string): boolean {
	return activeMac(userId)?.busyTurnId === turnId;
}

export function disconnectRemoteDevice(deviceId: string): void {
	macs.get(deviceId)?.socket.close(4003, "revoked");
}

export function isRemoteMacOnline(userId: string): boolean {
	return Boolean(activeMac(userId));
}
