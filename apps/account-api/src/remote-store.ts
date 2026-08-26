import { createHash, randomBytes, randomInt } from "node:crypto";
import { db, newId, nowIso } from "./db.js";

const PAIRING_TTL_MS = 5 * 60 * 1000;

type DeviceRow = {
	id: string;
	userId: string;
	kind: "mac" | "ios";
	name: string;
	createdAt: string;
	updatedAt: string;
	lastSeenAt: string | null;
	revokedAt: string | null;
};

type PairingRow = {
	id: string;
	userId: string;
	macDeviceId: string;
	claimedDeviceId: string | null;
	codeHash: string;
	status: "pending" | "claimed" | "expired" | "canceled";
	expiresAt: string;
	createdAt: string;
	claimedAt: string | null;
};

export type RemoteThread = {
	id: string;
	title: string;
	status: string;
	clientRequestId: string;
	createdAt: string;
	updatedAt: string;
};

export type RemoteTurn = {
	id: string;
	threadId: string;
	clientRequestId: string;
	role: string;
	content: string;
	status: string;
	createdAt: string;
	updatedAt: string;
};

function sha256(value: string): string {
	return createHash("sha256").update(value).digest("hex");
}

function fail(code: string): never {
	throw new Error(code);
}

function inTransaction<T>(run: () => T): T {
	db.exec("BEGIN IMMEDIATE");
	try {
		const result = run();
		db.exec("COMMIT");
		return result;
	} catch (error) {
		db.exec("ROLLBACK");
		throw error;
	}
}

function requireThread(userId: string, threadId: string): void {
	const row = db
		.prepare("SELECT id FROM remote_thread WHERE id = ? AND userId = ?")
		.get(threadId, userId);
	if (!row) fail("not_found");
}

function requireTurn(userId: string, turnId: string, threadId?: string): void {
	const row = threadId
		? db
				.prepare("SELECT id FROM remote_turn WHERE id = ? AND threadId = ? AND userId = ?")
				.get(turnId, threadId, userId)
		: db.prepare("SELECT id FROM remote_turn WHERE id = ? AND userId = ?").get(turnId, userId);
	if (!row) fail("not_found");
}

function publicDevice(row: DeviceRow) {
	return {
		id: row.id,
		kind: row.kind,
		name: row.name,
		createdAt: row.createdAt,
		updatedAt: row.updatedAt,
		lastSeenAt: row.lastSeenAt,
		revokedAt: row.revokedAt,
	};
}

export function startPairing(input: {
	userId: string;
	deviceName: string;
	publicUrl: string;
}) {
	return inTransaction(() => {
		const now = nowIso();
		let mac = db
			.prepare(
				"SELECT * FROM device WHERE userId = ? AND kind = 'mac' AND revokedAt IS NULL LIMIT 1",
			)
			.get(input.userId) as DeviceRow | undefined;
		if (!mac) {
			mac = {
				id: newId(),
				userId: input.userId,
				kind: "mac",
				name: input.deviceName.trim() || "Mac",
				createdAt: now,
				updatedAt: now,
				lastSeenAt: null,
				revokedAt: null,
			};
			db.prepare(
				`INSERT INTO device
				 (id, userId, kind, name, createdAt, updatedAt, lastSeenAt, revokedAt)
				 VALUES (?, ?, 'mac', ?, ?, ?, NULL, NULL)`,
			).run(mac.id, mac.userId, mac.name, now, now);
		} else {
			db.prepare("UPDATE device SET name = ?, updatedAt = ? WHERE id = ?").run(
				input.deviceName.trim() || mac.name,
				now,
				mac.id,
			);
		}

		db.prepare(
			"UPDATE pairing_session SET status = 'canceled' WHERE userId = ? AND status = 'pending'",
		).run(input.userId);
		const rawDeviceToken = `zd_${randomBytes(24).toString("base64url")}`;
		db.prepare(
			`INSERT INTO device_token
			 (id, userId, deviceId, tokenHash, prefix, createdAt, lastUsedAt, revokedAt)
			 VALUES (?, ?, ?, ?, 'zd_', ?, NULL, NULL)`,
		).run(newId(), input.userId, mac.id, sha256(rawDeviceToken), now);

		const pairingId = newId();
		const code = String(randomInt(0, 1_000_000)).padStart(6, "0");
		const expiresAt = new Date(Date.now() + PAIRING_TTL_MS).toISOString();
		db.prepare(
			`INSERT INTO pairing_session
			 (id, userId, macDeviceId, claimedDeviceId, codeHash, status, expiresAt, createdAt, claimedAt)
			 VALUES (?, ?, ?, NULL, ?, 'pending', ?, ?, NULL)`,
		).run(pairingId, input.userId, mac.id, sha256(code), expiresAt, now);

		const publicUrl = input.publicUrl.replace(/\/$/, "");
		const qrPayload =
			`zhigeng://pair?pid=${encodeURIComponent(pairingId)}` +
			`&c=${encodeURIComponent(code)}&api=${encodeURIComponent(publicUrl)}`;
		return {
			pairingId,
			deviceId: mac.id,
			deviceToken: rawDeviceToken,
			code,
			qrPayload,
			expiresAt,
		};
	});
}

export function claimPairing(input: {
	userId: string;
	pairingId: string;
	code: string;
	deviceName: string;
}) {
	return inTransaction(() => {
		const row = db
			.prepare("SELECT * FROM pairing_session WHERE id = ?")
			.get(input.pairingId) as PairingRow | undefined;
		if (!row) fail("not_found");
		if (row.userId !== input.userId) fail("forbidden");
		if (row.status !== "pending") fail("conflict");
		const now = nowIso();
		if (Date.now() >= new Date(row.expiresAt).getTime()) {
			db.prepare("UPDATE pairing_session SET status = 'expired' WHERE id = ?").run(row.id);
			fail("expired");
		}
		if (sha256(input.code) !== row.codeHash) fail("forbidden");

		const phoneId = newId();
		const phoneName = input.deviceName.trim() || "iPhone";
		db.prepare(
			`INSERT INTO device
			 (id, userId, kind, name, createdAt, updatedAt, lastSeenAt, revokedAt)
			 VALUES (?, ?, 'ios', ?, ?, ?, ?, NULL)`,
		).run(phoneId, input.userId, phoneName, now, now, now);
		db.prepare(
			`UPDATE pairing_session
			 SET status = 'claimed', claimedDeviceId = ?, claimedAt = ?
			 WHERE id = ?`,
		).run(phoneId, now, row.id);
		return {
			status: "claimed" as const,
			macDevice: publicDevice(
				db.prepare("SELECT * FROM device WHERE id = ?").get(row.macDeviceId) as DeviceRow,
			),
			iosDevice: publicDevice(
				db.prepare("SELECT * FROM device WHERE id = ?").get(phoneId) as DeviceRow,
			),
		};
	});
}

export function getPairingStatus(userId: string, pairingId: string) {
	const row = db
		.prepare("SELECT * FROM pairing_session WHERE id = ? AND userId = ?")
		.get(pairingId, userId) as PairingRow | undefined;
	if (!row) return undefined;
	if (row.status === "pending" && Date.now() >= new Date(row.expiresAt).getTime()) {
		db.prepare("UPDATE pairing_session SET status = 'expired' WHERE id = ?").run(row.id);
		row.status = "expired";
	}
	return {
		id: row.id,
		status: row.status,
		macDeviceId: row.macDeviceId,
		claimedDeviceId: row.claimedDeviceId,
		expiresAt: row.expiresAt,
		claimedAt: row.claimedAt,
	};
}

export function listDevices(userId: string) {
	return (
		db
			.prepare("SELECT * FROM device WHERE userId = ? ORDER BY createdAt ASC")
			.all(userId) as DeviceRow[]
	).map(publicDevice);
}

export function revokeDevice(userId: string, deviceId: string): void {
	const now = nowIso();
	const changed = db
		.prepare("UPDATE device SET revokedAt = ?, updatedAt = ? WHERE id = ? AND userId = ?")
		.run(now, now, deviceId, userId);
	if (changed.changes === 0) fail("not_found");
	db.prepare(
		"UPDATE device_token SET revokedAt = ? WHERE deviceId = ? AND userId = ? AND revokedAt IS NULL",
	).run(now, deviceId, userId);
}

export function resolveDeviceToken(rawToken: string) {
	if (!rawToken.startsWith("zd_")) return undefined;
	const row = db
		.prepare(
			`SELECT dt.deviceId, dt.userId, d.kind, d.name
			 FROM device_token dt
			 JOIN device d ON d.id = dt.deviceId
			 WHERE dt.tokenHash = ? AND dt.revokedAt IS NULL AND d.revokedAt IS NULL`,
		)
		.get(sha256(rawToken)) as
		| { deviceId: string; userId: string; kind: string; name: string }
		| undefined;
	if (row) {
		db.prepare("UPDATE device_token SET lastUsedAt = ? WHERE tokenHash = ?").run(
			nowIso(),
			sha256(rawToken),
		);
	}
	return row;
}

export function markDeviceSeen(deviceId: string): void {
	const now = nowIso();
	db.prepare(
		"UPDATE device SET lastSeenAt = ?, updatedAt = ? WHERE id = ? AND revokedAt IS NULL",
	).run(now, now, deviceId);
}

export function isDevicePaired(userId: string, deviceId: string): boolean {
	return Boolean(
		db
			.prepare(
				`SELECT id FROM pairing_session
				 WHERE userId = ? AND macDeviceId = ? AND status = 'claimed'
				 LIMIT 1`,
			)
			.get(userId, deviceId),
	);
}

export function createRemoteThread(input: {
	userId: string;
	title: string;
	clientRequestId: string;
}): RemoteThread {
	const existing = db
		.prepare("SELECT * FROM remote_thread WHERE userId = ? AND clientRequestId = ?")
		.get(input.userId, input.clientRequestId) as (RemoteThread & { userId: string }) | undefined;
	if (existing) return existing;
	const now = nowIso();
	const thread: RemoteThread = {
		id: newId(),
		title: input.title.trim() || "新任务",
		status: "active",
		clientRequestId: input.clientRequestId,
		createdAt: now,
		updatedAt: now,
	};
	db.prepare(
		`INSERT INTO remote_thread
		 (id, userId, title, status, clientRequestId, createdAt, updatedAt)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
	).run(
		thread.id,
		input.userId,
		thread.title,
		thread.status,
		thread.clientRequestId,
		now,
		now,
	);
	return thread;
}

export function listRemoteThreads(userId: string): RemoteThread[] {
	return db
		.prepare(
			`SELECT id, title, status, clientRequestId, createdAt, updatedAt
			 FROM remote_thread WHERE userId = ? ORDER BY updatedAt DESC`,
		)
		.all(userId) as RemoteThread[];
}

export function getRemoteThread(userId: string, threadId: string) {
	const thread = db
		.prepare(
			`SELECT id, title, status, clientRequestId, createdAt, updatedAt
			 FROM remote_thread WHERE id = ? AND userId = ?`,
		)
		.get(threadId, userId) as RemoteThread | undefined;
	if (!thread) return undefined;
	const turns = db
		.prepare(
			`SELECT id, threadId, clientRequestId, role, content, status, createdAt, updatedAt
			 FROM remote_turn WHERE threadId = ? AND userId = ? ORDER BY createdAt ASC`,
		)
		.all(threadId, userId) as RemoteTurn[];
	return { ...thread, turns };
}

export function createRemoteTurn(input: {
	userId: string;
	threadId: string;
	clientRequestId: string;
	content: string;
}): RemoteTurn {
	const existing = db
		.prepare("SELECT * FROM remote_turn WHERE userId = ? AND clientRequestId = ?")
		.get(input.userId, input.clientRequestId) as (RemoteTurn & { userId: string }) | undefined;
	if (existing) return existing;
	requireThread(input.userId, input.threadId);
	if (!input.content.trim()) fail("content_required");
	if (input.content.trim().length > 10_000) fail("content_too_long");
	const now = nowIso();
	const turn: RemoteTurn = {
		id: newId(),
		threadId: input.threadId,
		clientRequestId: input.clientRequestId,
		role: "user",
		content: input.content.trim(),
		status: "queued",
		createdAt: now,
		updatedAt: now,
	};
	db.prepare(
		`INSERT INTO remote_turn
		 (id, userId, threadId, clientRequestId, role, content, status, createdAt, updatedAt)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
	).run(
		turn.id,
		input.userId,
		turn.threadId,
		turn.clientRequestId,
		turn.role,
		turn.content,
		turn.status,
		now,
		now,
	);
	db.prepare("UPDATE remote_thread SET updatedAt = ? WHERE id = ? AND userId = ?").run(
		now,
		input.threadId,
		input.userId,
	);
	return turn;
}

export function getRemoteTurn(userId: string, turnId: string) {
	const turn = db
		.prepare(
			`SELECT id, threadId, clientRequestId, role, content, status, createdAt, updatedAt
			 FROM remote_turn WHERE id = ? AND userId = ?`,
		)
		.get(turnId, userId) as RemoteTurn | undefined;
	if (!turn) return undefined;
	const events = db
		.prepare(
			`SELECT id, type, payload, createdAt FROM remote_event
			 WHERE userId = ? AND turnId = ? ORDER BY createdAt ASC`,
		)
		.all(userId, turnId) as Array<{
		id: string;
		type: string;
		payload: string;
		createdAt: string;
	}>;
	return {
		...turn,
		events: events.map((event) => ({ ...event, payload: JSON.parse(event.payload) })),
	};
}

export function updateRemoteTurn(input: {
	userId: string;
	turnId: string;
	status: string;
}): void {
	const now = nowIso();
	const changed = db
		.prepare("UPDATE remote_turn SET status = ?, updatedAt = ? WHERE id = ? AND userId = ?")
		.run(input.status, now, input.turnId, input.userId);
	if (changed.changes === 0) fail("not_found");
}

export function appendRemoteEvent(input: {
	userId: string;
	threadId: string;
	turnId?: string;
	type: string;
	payload: unknown;
}) {
	requireThread(input.userId, input.threadId);
	if (input.turnId) requireTurn(input.userId, input.turnId, input.threadId);
	const event = {
		id: newId(),
		type: input.type,
		payload: input.payload,
		createdAt: nowIso(),
	};
	db.prepare(
		`INSERT INTO remote_event
		 (id, userId, threadId, turnId, type, payload, createdAt)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
	).run(
		event.id,
		input.userId,
		input.threadId,
		input.turnId ?? null,
		event.type,
		JSON.stringify(event.payload),
		event.createdAt,
	);
	return event;
}

export function createRemoteApproval(input: {
	userId: string;
	threadId: string;
	turnId: string;
	clientRequestId: string;
	kind: string;
	prompt: string;
	request?: unknown;
	expiresAt?: string;
}) {
	const existing = db
		.prepare("SELECT * FROM remote_approval WHERE userId = ? AND clientRequestId = ?")
		.get(input.userId, input.clientRequestId) as
		| { id: string; status: string; prompt: string }
		| undefined;
	if (existing) return existing;
	requireThread(input.userId, input.threadId);
	requireTurn(input.userId, input.turnId, input.threadId);
	const now = nowIso();
	const approval = {
		id: newId(),
		status: "pending",
		prompt: input.prompt,
		expiresAt: input.expiresAt ?? new Date(Date.now() + 10 * 60 * 1000).toISOString(),
	};
	db.prepare(
		`INSERT INTO remote_approval
		 (id, userId, threadId, turnId, clientRequestId, kind, prompt, requestJson, status,
		  response, expiresAt, createdAt, updatedAt, respondedAt)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', NULL, ?, ?, ?, NULL)`,
	).run(
		approval.id,
		input.userId,
		input.threadId,
		input.turnId,
		input.clientRequestId,
		input.kind,
		input.prompt,
		JSON.stringify(input.request ?? { kind: input.kind, message: input.prompt }),
		approval.expiresAt,
		now,
		now,
	);
	return approval;
}

export function getRemoteApproval(userId: string, approvalId: string) {
	const row = db
		.prepare(
			`SELECT id, turnId, status, requestJson, response, expiresAt, createdAt, respondedAt
			 FROM remote_approval WHERE id = ? AND userId = ?`,
		)
		.get(approvalId, userId) as
		| {
				id: string;
				turnId: string;
				status: string;
				requestJson: string;
				response: string | null;
				expiresAt: string;
				createdAt: string;
				respondedAt: string | null;
		  }
		| undefined;
	return row
		? {
				...row,
				request: JSON.parse(row.requestJson),
				response: row.response ? JSON.parse(row.response) : null,
			}
		: undefined;
}

export function respondToRemoteApproval(input: {
	userId: string;
	approvalId: string;
	decision: string;
	response?: unknown;
}) {
	return inTransaction(() => {
		const row = db
			.prepare("SELECT * FROM remote_approval WHERE id = ? AND userId = ?")
			.get(input.approvalId, input.userId) as
			| { id: string; turnId: string; status: string; response: string | null }
			| undefined;
		if (!row) fail("not_found");
		if (row.status !== "pending") fail("conflict");
		const now = nowIso();
		db.prepare(
			`UPDATE remote_approval
			 SET status = ?, response = ?, updatedAt = ?, respondedAt = ?
			 WHERE id = ?`,
		).run(
			input.decision,
			JSON.stringify(input.response ?? { decision: input.decision }),
			now,
			now,
			row.id,
		);
		return { id: row.id, turnId: row.turnId, status: input.decision, respondedAt: now };
	});
}
