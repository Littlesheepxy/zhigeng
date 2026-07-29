import { loadConfig, saveConfig, type FoldConfig } from "./config.js";
import { clearAccountSecret, loadAccountSecret, saveAccountSecret } from "./secure-store.js";

const DEFAULT_ACCOUNT_API = "http://127.0.0.1:3010";

export type AccountState = {
	signedIn: boolean;
	email?: string;
	name?: string;
	userId?: string;
	planTier: FoldConfig["planTier"];
	voiceSecondsRemaining?: number;
	smartActionsRemaining?: number;
	voiceSecondsLimit?: number;
	smartActionsLimit?: number;
	periodEnd?: string;
	syncedAt?: number;
};

export function accountApiBase(): string {
	return (
		process.env.FOLD_ACCOUNT_API_URL?.trim() ||
		process.env.ACCOUNT_API_URL?.trim() ||
		DEFAULT_ACCOUNT_API
	).replace(/\/$/, "");
}

async function apiJson<T>(
	path: string,
	init: RequestInit & { apiKey?: string } = {},
): Promise<T> {
	const headers = new Headers(init.headers);
	headers.set("Content-Type", "application/json");
	if (init.apiKey) headers.set("Authorization", `Bearer ${init.apiKey}`);
	const res = await fetch(`${accountApiBase()}${path}`, { ...init, headers });
	if (!res.ok) {
		const text = await res.text().catch(() => "");
		let detail = text.slice(0, 200);
		try {
			const parsed = JSON.parse(text) as { error?: string; reason?: string };
			detail = parsed.error || parsed.reason || detail;
		} catch {
			/* keep raw */
		}
		throw new Error(detail || `account-api ${path} failed (${res.status})`);
	}
	return (await res.json()) as T;
}

export function getAccountState(): AccountState {
	const config = loadConfig();
	const apiKey = loadAccountSecret() ?? "";
	const signedIn = Boolean(apiKey && config.accountUserId);
	return {
		signedIn,
		email: config.accountEmail,
		name: config.accountName,
		userId: config.accountUserId,
		planTier: config.planTier ?? "free",
		voiceSecondsRemaining: config.voiceSecondsRemaining,
		smartActionsRemaining: config.smartActionsRemaining,
		voiceSecondsLimit: config.voiceSecondsLimit,
		smartActionsLimit: config.smartActionsLimit,
		periodEnd: config.periodEnd,
		syncedAt: config.accountSyncedAt,
	};
}

export async function requestAccountCode(
	email: string,
): Promise<{ ok: true; mode: string } | { ok: false; error: string }> {
	try {
		const result = await apiJson<{ ok: true; mode: string }>("/auth/request-code", {
			method: "POST",
			body: JSON.stringify({ email }),
		});
		return { ok: true, mode: result.mode };
	} catch (error) {
		return { ok: false, error: error instanceof Error ? error.message : String(error) };
	}
}

export async function verifyAccountCode(input: {
	email: string;
	code: string;
}): Promise<{ ok: true; state: AccountState } | { ok: false; error: string }> {
	try {
		const result = await apiJson<{
			apiKey: string;
			user: { id: string; email: string; name: string | null };
		}>("/auth/verify", {
			method: "POST",
			body: JSON.stringify(input),
		});
		saveAccountSecret(result.apiKey);
		const config = loadConfig();
		saveConfig({
			...config,
			hubApiKey: undefined,
			accountUserId: result.user.id,
			accountEmail: result.user.email,
			accountName: result.user.name ?? result.user.email,
			accountSyncedAt: Date.now(),
		});
		process.env.FOLD_ACCOUNT_API_KEY = result.apiKey;
		process.env.FOLD_HUB_API_KEY = result.apiKey;
		const state = await syncAccountEntitlements();
		return { ok: true, state };
	} catch (error) {
		return { ok: false, error: error instanceof Error ? error.message : String(error) };
	}
}

/** @deprecated Browser PKCE login removed; use email code flow. */
export async function startDesktopLogin(): Promise<{ ok: true } | { ok: false; error: string }> {
	return {
		ok: false,
		error: "请在账户弹窗内用邮箱验证码登录",
	};
}

export async function syncAccountEntitlements(): Promise<AccountState> {
	const apiKey = loadAccountSecret();
	if (!apiKey) return getAccountState();

	const entitlements = await apiJson<{
		planTier: "free" | "pro";
		periodEnd: string;
		voiceSecondsRemaining: number;
		smartActionsRemaining: number;
		voiceSecondsLimit: number;
		smartActionsLimit: number;
	}>("/billing/entitlements", { method: "GET", apiKey });

	const me = await apiJson<{
		id: string;
		email: string;
		name: string | null;
	}>("/me", { method: "GET", apiKey }).catch(() => null);

	const config = loadConfig();
	saveConfig({
		...config,
		planTier: entitlements.planTier === "pro" ? "pro" : "free",
		voiceSecondsRemaining: entitlements.voiceSecondsRemaining,
		smartActionsRemaining: entitlements.smartActionsRemaining,
		voiceSecondsLimit: entitlements.voiceSecondsLimit,
		smartActionsLimit: entitlements.smartActionsLimit,
		periodEnd: entitlements.periodEnd,
		accountSyncedAt: Date.now(),
		...(me
			? {
					accountUserId: me.id,
					accountEmail: me.email,
					accountName: me.name ?? me.email,
				}
			: {}),
	});
	return getAccountState();
}

export async function updateAccountName(
	name: string,
): Promise<{ ok: true; state: AccountState } | { ok: false; error: string }> {
	const apiKey = loadAccountSecret();
	if (!apiKey) return { ok: false, error: "未登录" };
	try {
		const updated = await apiJson<{ name: string }>("/me", {
			method: "PATCH",
			apiKey,
			body: JSON.stringify({ name }),
		});
		const config = loadConfig();
		saveConfig({ ...config, accountName: updated.name });
		return { ok: true, state: getAccountState() };
	} catch (error) {
		return { ok: false, error: error instanceof Error ? error.message : String(error) };
	}
}

export async function checkoutPlan(input: {
	productId: string;
}): Promise<
	| { ok: true; mode: string; activated?: boolean; checkoutUrl?: string; state: AccountState }
	| { ok: false; error: string }
> {
	const apiKey = loadAccountSecret();
	if (!apiKey) return { ok: false, error: "请先登录" };
	try {
		const result = await apiJson<{
			mode: string;
			activated?: boolean;
			checkoutUrl?: string;
			entitlements?: {
				planTier: "free" | "pro";
				periodEnd?: string;
				voiceSecondsRemaining: number;
				smartActionsRemaining: number;
				voiceSecondsLimit?: number;
				smartActionsLimit?: number;
			};
		}>("/billing/checkout", {
			method: "POST",
			apiKey,
			body: JSON.stringify(input),
		});
		if (result.entitlements) {
			const config = loadConfig();
			saveConfig({
				...config,
				planTier: result.entitlements.planTier,
				voiceSecondsRemaining: result.entitlements.voiceSecondsRemaining,
				smartActionsRemaining: result.entitlements.smartActionsRemaining,
				voiceSecondsLimit: result.entitlements.voiceSecondsLimit,
				smartActionsLimit: result.entitlements.smartActionsLimit,
				periodEnd: result.entitlements.periodEnd,
				accountSyncedAt: Date.now(),
			});
		} else {
			await syncAccountEntitlements();
		}
		return {
			ok: true,
			mode: result.mode,
			activated: result.activated,
			checkoutUrl: result.checkoutUrl,
			state: getAccountState(),
		};
	} catch (error) {
		return { ok: false, error: error instanceof Error ? error.message : String(error) };
	}
}

export async function cancelPlan(): Promise<
	{ ok: true; state: AccountState } | { ok: false; error: string }
> {
	const apiKey = loadAccountSecret();
	if (!apiKey) return { ok: false, error: "未登录" };
	try {
		await apiJson("/billing/cancel", { method: "POST", apiKey, body: "{}" });
		const state = await syncAccountEntitlements();
		return { ok: true, state };
	} catch (error) {
		return { ok: false, error: error instanceof Error ? error.message : String(error) };
	}
}

export async function deleteAccount(): Promise<
	{ ok: true; state: AccountState } | { ok: false; error: string }
> {
	const apiKey = loadAccountSecret();
	if (!apiKey) return { ok: false, error: "未登录" };
	try {
		await apiJson("/me", { method: "DELETE", apiKey });
		return { ok: true, state: logoutAccount() };
	} catch (error) {
		return { ok: false, error: error instanceof Error ? error.message : String(error) };
	}
}

export function logoutAccount(): AccountState {
	const apiKey = loadAccountSecret();
	if (apiKey) {
		void apiJson("/auth/logout", {
			method: "POST",
			apiKey,
			body: "{}",
		}).catch(() => undefined);
	}
	clearAccountSecret();
	delete process.env.FOLD_ACCOUNT_API_KEY;
	delete process.env.FOLD_HUB_API_KEY;
	const config = loadConfig();
	saveConfig({
		...config,
		accountUserId: undefined,
		accountEmail: undefined,
		accountName: undefined,
		accountSyncedAt: undefined,
		planTier: "free",
		voiceSecondsRemaining: undefined,
		smartActionsRemaining: undefined,
		voiceSecondsLimit: undefined,
		smartActionsLimit: undefined,
		periodEnd: undefined,
		hubApiKey: undefined,
	});
	return getAccountState();
}
