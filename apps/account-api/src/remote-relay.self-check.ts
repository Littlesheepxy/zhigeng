import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import WebSocket from "ws";

const dir = mkdtempSync(join(tmpdir(), "fold-relay-"));
process.env.ACCOUNT_DB_PATH = join(dir, "test.sqlite");
process.env.ACCOUNT_AUTH_MODE = "mock";

const { requestLoginCode, verifyLoginCode } = await import("./auth.js");
const { claimPairing, createRemoteThread, createRemoteTurn, startPairing } = await import(
	"./remote-store.js"
);
const { attachRemoteRelay, dispatchRemoteTurn, sendApprovalToMac } = await import(
	"./remote-relay.js"
);

await requestLoginCode("relay@zhigeng.app");
const { user, apiKey } = verifyLoginCode({
	email: "relay@zhigeng.app",
	code: "888888",
});
const pairing = startPairing({
	userId: user.id,
	deviceName: "Relay Mac",
	publicUrl: "http://127.0.0.1",
});
claimPairing({
	userId: user.id,
	pairingId: pairing.pairingId,
	code: pairing.code,
	deviceName: "Relay iPhone",
});

const server = createServer();
attachRemoteRelay(server);
await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
const address = server.address();
assert.ok(address && typeof address === "object");
const base = `ws://127.0.0.1:${address.port}`;

const mac = new WebSocket(`${base}/remote/ws/mac?token=${encodeURIComponent(pairing.deviceToken)}`);
await new Promise<void>((resolve, reject) => {
	mac.once("open", resolve);
	mac.once("error", reject);
});
mac.send(JSON.stringify({ type: "hello", deviceId: pairing.deviceId }));
await new Promise<void>((resolve) => mac.once("message", () => resolve()));

const phone = new WebSocket(`${base}/remote/ws/phone?token=${encodeURIComponent(apiKey)}`);
await new Promise<void>((resolve, reject) => {
	phone.once("open", resolve);
	phone.once("error", reject);
});

const thread = createRemoteThread({
	userId: user.id,
	title: "Relay check",
	clientRequestId: "relay-thread",
});
const turn = createRemoteTurn({
	userId: user.id,
	threadId: thread.id,
	clientRequestId: "relay-turn",
	content: "Run relay check",
});
const dispatched = dispatchRemoteTurn({ userId: user.id, turn });
assert.equal(dispatched, true);

const taskFrame = await new Promise<Record<string, unknown>>((resolve) => {
	mac.once("message", (data) => resolve(JSON.parse(data.toString())));
});
assert.equal(taskFrame.type, "task.dispatch");
assert.equal(taskFrame.turnId, turn.id);

const phoneEvent = new Promise<Record<string, unknown>>((resolve) => {
	phone.once("message", (data) => resolve(JSON.parse(data.toString())));
});
mac.send(
	JSON.stringify({
		type: "turn.state",
		turnId: turn.id,
		threadId: thread.id,
		status: "running",
		state: { status: "working", transcript: "Run relay check" },
	}),
);
assert.equal((await phoneEvent).type, "turn.updated");

const approvalEvent = new Promise<Record<string, unknown>>((resolve) => {
	phone.once("message", (data) => resolve(JSON.parse(data.toString())));
});
mac.send(
	JSON.stringify({
		type: "approval.request",
		turnId: turn.id,
		request: {
			id: "local-approval-1",
			kind: "confirm",
			title: "确认发送",
			message: "允许发送测试消息吗？",
			options: [{ id: "confirm", label: "允许" }],
		},
	}),
);
const requested = await approvalEvent;
assert.equal(requested.type, "approval.requested");
const approval = requested.approval as { id: string };
const approvalFrame = new Promise<Record<string, unknown>>((resolve) => {
	mac.once("message", (data) => resolve(JSON.parse(data.toString())));
});
assert.equal(
	sendApprovalToMac({
		userId: user.id,
		turnId: turn.id,
		approvalId: approval.id,
		response: { requestId: "local-approval-1", optionId: "confirm", modality: "click" },
	}),
	true,
);
assert.equal((await approvalFrame).type, "approval.resolve");

mac.close();
phone.close();
await new Promise<void>((resolve) => server.close(() => resolve()));
rmSync(dir, { recursive: true, force: true });
console.log("account-api remote relay self-check ok");
