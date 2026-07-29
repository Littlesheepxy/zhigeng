/**
 * synced-from: Fold/packages/database/prisma/schema.prisma (Purchase/AiUsage/AiCost*)
 * Field names/semantics stay isomorphic for a future Fold Hub merge.
 */
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { nanoid } from "nanoid";

const dbPath =
	process.env.ACCOUNT_DB_PATH?.trim() ||
	join(process.cwd(), "data", "account.sqlite");

mkdirSync(dirname(dbPath), { recursive: true });

export const db = new DatabaseSync(dbPath);
db.exec("PRAGMA journal_mode = WAL");
db.exec("PRAGMA foreign_keys = ON");

db.exec(`
CREATE TABLE IF NOT EXISTS user (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  name TEXT,
  emailVerified INTEGER NOT NULL DEFAULT 0,
  externalId TEXT UNIQUE,
  image TEXT,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS auth_code (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  codeHash TEXT NOT NULL,
  expiresAt TEXT NOT NULL,
  consumedAt TEXT,
  createdAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS auth_code_email_idx ON auth_code(email);

CREATE TABLE IF NOT EXISTS api_token (
  id TEXT PRIMARY KEY,
  userId TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  tokenHash TEXT NOT NULL UNIQUE,
  prefix TEXT NOT NULL,
  name TEXT,
  createdAt TEXT NOT NULL,
  lastUsedAt TEXT,
  revokedAt TEXT
);
CREATE INDEX IF NOT EXISTS api_token_user_idx ON api_token(userId);

CREATE TABLE IF NOT EXISTS purchase (
  id TEXT PRIMARY KEY,
  userId TEXT REFERENCES user(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  customerId TEXT NOT NULL,
  subscriptionId TEXT UNIQUE,
  productId TEXT NOT NULL,
  status TEXT,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS purchase_sub_idx ON purchase(subscriptionId);

CREATE TABLE IF NOT EXISTS ai_usage (
  id TEXT PRIMARY KEY,
  userId TEXT NOT NULL UNIQUE REFERENCES user(id) ON DELETE CASCADE,
  amaReplies INTEGER NOT NULL DEFAULT 0,
  traceAnalyses INTEGER NOT NULL DEFAULT 0,
  profileOptimizations INTEGER NOT NULL DEFAULT 0,
  voiceSeconds INTEGER NOT NULL DEFAULT 0,
  smartActions INTEGER NOT NULL DEFAULT 0,
  companyCostMicros TEXT NOT NULL DEFAULT '0',
  periodStart TEXT NOT NULL,
  periodEnd TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS ai_cost_event (
  id TEXT PRIMARY KEY,
  requestId TEXT NOT NULL UNIQUE,
  operationId TEXT,
  userId TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  feature TEXT NOT NULL,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  funding TEXT NOT NULL DEFAULT 'company',
  rateVersion TEXT NOT NULL,
  estimated INTEGER NOT NULL DEFAULT 0,
  inputTextTokens INTEGER NOT NULL DEFAULT 0,
  outputTextTokens INTEGER NOT NULL DEFAULT 0,
  cachedInputTokens INTEGER NOT NULL DEFAULT 0,
  reasoningTokens INTEGER NOT NULL DEFAULT 0,
  audioInputTokens INTEGER NOT NULL DEFAULT 0,
  audioOutputTokens INTEGER NOT NULL DEFAULT 0,
  audioSeconds INTEGER NOT NULL DEFAULT 0,
  searchCalls INTEGER NOT NULL DEFAULT 0,
  ocrPages INTEGER NOT NULL DEFAULT 0,
  ttsCharacters INTEGER NOT NULL DEFAULT 0,
  browserSeconds INTEGER NOT NULL DEFAULT 0,
  companyCostMicros TEXT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'CNY',
  breakdown TEXT,
  createdAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ai_cost_event_user_idx ON ai_cost_event(userId, createdAt);

CREATE TABLE IF NOT EXISTS ai_cost_daily (
  id TEXT PRIMARY KEY,
  userId TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  day TEXT NOT NULL,
  feature TEXT NOT NULL,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  funding TEXT NOT NULL DEFAULT 'company',
  requestCount INTEGER NOT NULL DEFAULT 0,
  audioSeconds INTEGER NOT NULL DEFAULT 0,
  companyCostMicros TEXT NOT NULL DEFAULT '0',
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL,
  UNIQUE(userId, day, feature, provider, model, funding)
);

CREATE TABLE IF NOT EXISTS device (
  id TEXT PRIMARY KEY,
  userId TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  name TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL,
  lastSeenAt TEXT,
  revokedAt TEXT
);
CREATE INDEX IF NOT EXISTS device_user_idx ON device(userId, createdAt);
CREATE UNIQUE INDEX IF NOT EXISTS device_one_active_mac_idx
  ON device(userId) WHERE kind = 'mac' AND revokedAt IS NULL;

CREATE TABLE IF NOT EXISTS device_token (
  id TEXT PRIMARY KEY,
  userId TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  deviceId TEXT NOT NULL REFERENCES device(id) ON DELETE CASCADE,
  tokenHash TEXT NOT NULL UNIQUE,
  prefix TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  lastUsedAt TEXT,
  revokedAt TEXT
);
CREATE INDEX IF NOT EXISTS device_token_user_idx ON device_token(userId, deviceId);

CREATE TABLE IF NOT EXISTS pairing_session (
  id TEXT PRIMARY KEY,
  userId TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  macDeviceId TEXT NOT NULL REFERENCES device(id) ON DELETE CASCADE,
  claimedDeviceId TEXT REFERENCES device(id) ON DELETE SET NULL,
  codeHash TEXT NOT NULL,
  status TEXT NOT NULL,
  expiresAt TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  claimedAt TEXT
);
CREATE INDEX IF NOT EXISTS pairing_session_user_idx ON pairing_session(userId, createdAt);

CREATE TABLE IF NOT EXISTS remote_thread (
  id TEXT PRIMARY KEY,
  userId TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  status TEXT NOT NULL,
  clientRequestId TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL,
  UNIQUE(userId, clientRequestId)
);
CREATE INDEX IF NOT EXISTS remote_thread_user_idx ON remote_thread(userId, updatedAt);

CREATE TABLE IF NOT EXISTS remote_turn (
  id TEXT PRIMARY KEY,
  userId TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  threadId TEXT NOT NULL REFERENCES remote_thread(id) ON DELETE CASCADE,
  clientRequestId TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  status TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL,
  UNIQUE(userId, clientRequestId)
);
CREATE INDEX IF NOT EXISTS remote_turn_thread_idx ON remote_turn(userId, threadId, createdAt);

CREATE TABLE IF NOT EXISTS remote_event (
  id TEXT PRIMARY KEY,
  userId TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  threadId TEXT NOT NULL REFERENCES remote_thread(id) ON DELETE CASCADE,
  turnId TEXT REFERENCES remote_turn(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  payload TEXT NOT NULL,
  createdAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS remote_event_turn_idx ON remote_event(userId, turnId, createdAt);

CREATE TABLE IF NOT EXISTS remote_approval (
  id TEXT PRIMARY KEY,
  userId TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  threadId TEXT NOT NULL REFERENCES remote_thread(id) ON DELETE CASCADE,
  turnId TEXT NOT NULL REFERENCES remote_turn(id) ON DELETE CASCADE,
  clientRequestId TEXT NOT NULL,
  kind TEXT NOT NULL,
  prompt TEXT NOT NULL,
  requestJson TEXT NOT NULL,
  status TEXT NOT NULL,
  response TEXT,
  expiresAt TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL,
  respondedAt TEXT,
  UNIQUE(userId, clientRequestId)
);
CREATE INDEX IF NOT EXISTS remote_approval_turn_idx ON remote_approval(userId, turnId, createdAt);
`);

export function nowIso(): string {
	return new Date().toISOString();
}

export function newId(): string {
	return nanoid();
}

export type UserRow = {
	id: string;
	email: string;
	name: string | null;
	emailVerified: number;
	externalId: string | null;
	image: string | null;
	createdAt: string;
	updatedAt: string;
};

export function findUserByEmail(email: string): UserRow | undefined {
	return db.prepare("SELECT * FROM user WHERE email = ?").get(email.toLowerCase()) as
		| UserRow
		| undefined;
}

export function findUserById(id: string): UserRow | undefined {
	return db.prepare("SELECT * FROM user WHERE id = ?").get(id) as UserRow | undefined;
}

export function upsertUserByEmail(email: string, name?: string): UserRow {
	const normalized = email.trim().toLowerCase();
	const existing = findUserByEmail(normalized);
	const ts = nowIso();
	if (existing) {
		if (name && name !== existing.name) {
			db.prepare("UPDATE user SET name = ?, updatedAt = ? WHERE id = ?").run(
				name,
				ts,
				existing.id,
			);
			return findUserById(existing.id)!;
		}
		return existing;
	}
	const id = newId();
	db.prepare(
		`INSERT INTO user (id, email, name, emailVerified, externalId, image, createdAt, updatedAt)
     VALUES (?, ?, ?, 1, NULL, NULL, ?, ?)`,
	).run(id, normalized, name ?? normalized.split("@")[0] ?? "用户", ts, ts);
	return findUserById(id)!;
}
