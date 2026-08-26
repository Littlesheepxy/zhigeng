import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const dir = mkdtempSync(join(tmpdir(), "fold-account-"));
process.env.ACCOUNT_DB_PATH = join(dir, "test.sqlite");
process.env.ACCOUNT_AUTH_MODE = "mock";

const { requestLoginCode, verifyLoginCode, resolveUserFromBearer } = await import("./auth.js");
const { getEntitlements, consumeUsage } = await import("./usage-ledger.js");
const { activateSubscription } = await import("./payments.js");
const { CN_PRODUCT_IDS, cnProductMeta } = await import("./products.js");
const { quoteCost } = await import("./cost-catalog.js");
const { db } = await import("./db.js");
const {
	appendRemoteEvent,
	claimPairing,
	createRemoteApproval,
	createRemoteThread,
	createRemoteTurn,
	getPairingStatus,
	getRemoteThread,
	getRemoteTurn,
	listDevices,
	respondToRemoteApproval,
	revokeDevice,
	startPairing,
} = await import("./remote-store.js");

assert.equal(cnProductMeta(CN_PRODUCT_IDS.monthly).amountYuan, 29.9);
assert.equal(cnProductMeta(CN_PRODUCT_IDS.monthly).anchorYuan, 45.9);
assert.equal(cnProductMeta(CN_PRODUCT_IDS.yearly).amountYuan, 228);
assert.equal(cnProductMeta(CN_PRODUCT_IDS.yearly).anchorYuan, 358.8);

const byok = quoteCost({
	provider: "dashscope",
	model: "qwen-flash",
	feature: "planner",
	funding: "byok",
	usage: { inputTextTokens: 100, outputTextTokens: 50 },
});
assert.equal(byok.companyCostMicros, 0);

await requestLoginCode("demo@zhigeng.app");
const { user, apiKey } = verifyLoginCode({ email: "demo@zhigeng.app", code: "888888" });
assert.ok(apiKey.startsWith("zk_"));
assert.equal(user.email, "demo@zhigeng.app");

const authed = resolveUserFromBearer(`Bearer ${apiKey}`);
assert.equal(authed?.id, user.id);

let ents = getEntitlements(user.id);
assert.equal(ents.planTier, "free");
assert.equal(ents.voiceSecondsLimit, 1800);
assert.ok(ents.periodEnd);

activateSubscription({
	subscriptionId: "sub_test",
	customerId: "cus_test",
	productId: CN_PRODUCT_IDS.monthly,
	userId: user.id,
	provider: "mock",
});
ents = getEntitlements(user.id);
assert.equal(ents.planTier, "pro");
assert.equal(ents.voiceSecondsLimit, 36000);

const consumed = consumeUsage({ userId: user.id, voiceSeconds: 60 });
assert.equal(consumed.ok, true);
ents = getEntitlements(user.id);
assert.equal(ents.voiceSecondsUsed, 60);

const pairing = startPairing({
	userId: user.id,
	deviceName: "Test Mac",
	publicUrl: "https://account.example",
});
assert.ok(pairing.deviceToken.startsWith("zd_"));
assert.equal(pairing.code.length, 6);
assert.equal(
	pairing.qrPayload,
	`zhigeng://pair?pid=${encodeURIComponent(pairing.pairingId)}&c=${encodeURIComponent(pairing.code)}&api=${encodeURIComponent("https://account.example")}`,
);
assert.ok(new Date(pairing.expiresAt).getTime() - Date.now() <= 5 * 60 * 1000);
const storedPairing = db
	.prepare("SELECT codeHash FROM pairing_session WHERE id = ?")
	.get(pairing.pairingId) as { codeHash: string };
const storedDeviceToken = db
	.prepare("SELECT tokenHash FROM device_token WHERE deviceId = ?")
	.get(pairing.deviceId) as { tokenHash: string };
assert.notEqual(storedPairing.codeHash, pairing.code);
assert.notEqual(storedDeviceToken.tokenHash, pairing.deviceToken);

await requestLoginCode("other@zhigeng.app");
const { user: otherUser } = verifyLoginCode({ email: "other@zhigeng.app", code: "888888" });
assert.throws(
	() =>
		claimPairing({
			userId: otherUser.id,
			pairingId: pairing.pairingId,
			code: pairing.code,
			deviceName: "Other iPhone",
		}),
	/forbidden/,
);

const claimed = claimPairing({
	userId: user.id,
	pairingId: pairing.pairingId,
	code: pairing.code,
	deviceName: "Test iPhone",
});
assert.equal(claimed.status, "claimed");
assert.equal(getPairingStatus(user.id, pairing.pairingId)?.status, "claimed");
assert.equal(listDevices(user.id).length, 2);

const thread = createRemoteThread({
	userId: user.id,
	title: "Persistent thread",
	clientRequestId: "thread-request-1",
});
const sameThread = createRemoteThread({
	userId: user.id,
	title: "Ignored duplicate",
	clientRequestId: "thread-request-1",
});
assert.equal(sameThread.id, thread.id);

const turn = createRemoteTurn({
	userId: user.id,
	threadId: thread.id,
	clientRequestId: "turn-request-1",
	content: "Run the checks",
});
const sameTurn = createRemoteTurn({
	userId: user.id,
	threadId: thread.id,
	clientRequestId: "turn-request-1",
	content: "Ignored duplicate",
});
assert.equal(sameTurn.id, turn.id);
assert.equal(getRemoteTurn(user.id, turn.id)?.content, "Run the checks");
assert.equal(getRemoteTurn(otherUser.id, turn.id), undefined);
assert.equal(getRemoteThread(user.id, thread.id)?.turns[0]?.id, turn.id);

const event = appendRemoteEvent({
	userId: user.id,
	threadId: thread.id,
	turnId: turn.id,
	type: "status",
	payload: { state: "running" },
});
assert.equal(event.type, "status");

const approval = createRemoteApproval({
	userId: user.id,
	threadId: thread.id,
	turnId: turn.id,
	clientRequestId: "approval-request-1",
	kind: "command",
	prompt: "Allow command?",
});
const responded = respondToRemoteApproval({
	userId: user.id,
	approvalId: approval.id,
	decision: "approved",
});
assert.equal(responded.status, "approved");
assert.throws(
	() =>
		respondToRemoteApproval({
			userId: user.id,
			approvalId: approval.id,
			decision: "denied",
		}),
	/conflict/,
);

revokeDevice(user.id, pairing.deviceId);
assert.ok(listDevices(user.id).find((device) => device.id === pairing.deviceId)?.revokedAt);
const revokedToken = db
	.prepare("SELECT revokedAt FROM device_token WHERE deviceId = ?")
	.get(pairing.deviceId) as { revokedAt: string | null };
assert.ok(revokedToken.revokedAt);

const { readVolcAsrConfig } = await import("./volc-asr.js");
assert.equal(readVolcAsrConfig(), null);
process.env.VOLC_ASR_APP_ID = "test-app";
process.env.VOLC_ASR_TOKEN = "test-token";
process.env.VOLC_ASR_RESOURCE_ID = "volc.bigasr.sauc.duration";
const volc = readVolcAsrConfig();
assert.ok(volc);
assert.equal(volc?.appId, "test-app");
assert.equal(volc?.token, "test-token");
assert.equal(volc?.resourceId, "volc.bigasr.sauc.duration");
assert.ok(volc?.expireAt);

rmSync(dir, { recursive: true, force: true });
console.log("account-api self-check ok");
