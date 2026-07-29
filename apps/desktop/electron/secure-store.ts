import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { safeStorage } from "electron";
import { resolveDataDir } from "./data-dir.js";

function secretPath(): string {
	return join(resolveDataDir(), "account.secret");
}

function remoteDeviceSecretPath(): string {
	return join(resolveDataDir(), "remote-device.secret");
}

function saveSecret(path: string, value: string): void {
	const dir = resolveDataDir();
	if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
	if (!safeStorage.isEncryptionAvailable()) {
		// ponytail: fallback plaintext only when OS keychain unavailable; migrate when available
		writeFileSync(path, value, "utf8");
		return;
	}
	writeFileSync(path, safeStorage.encryptString(value));
}

function loadSecret(path: string): string | null {
	if (!existsSync(path)) return null;
	try {
		const raw = readFileSync(path);
		if (!safeStorage.isEncryptionAvailable()) {
			return raw.toString("utf8").trim() || null;
		}
		// Legacy plaintext tokens/JSON can exist from machines without Keychain access.
		const asText = raw.toString("utf8");
		if (/^(tm_|zk_|zd_|\{)/.test(asText)) return asText.trim();
		return safeStorage.decryptString(raw);
	} catch {
		return null;
	}
}

function clearSecret(path: string): void {
	if (!existsSync(path)) return;
	writeFileSync(path, "");
}

export function saveAccountSecret(apiKey: string): void {
	saveSecret(secretPath(), apiKey);
}

export function loadAccountSecret(): string | null {
	return loadSecret(secretPath());
}

export function clearAccountSecret(): void {
	clearSecret(secretPath());
}

export function saveRemoteDeviceSecret(value: string): void {
	saveSecret(remoteDeviceSecretPath(), value);
}

export function loadRemoteDeviceSecret(): string | null {
	return loadSecret(remoteDeviceSecretPath());
}

export function clearRemoteDeviceSecret(): void {
	clearSecret(remoteDeviceSecretPath());
}
