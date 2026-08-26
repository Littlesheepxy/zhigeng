import assert from "node:assert/strict";
import { resolveLocalEngine } from "./local-asr.js";
import { stripSenseVoiceTags } from "./local-sensevoice.js";
import { shouldUseSmartVoice } from "./voice-setup.js";

assert.equal(shouldUseSmartVoice("auto", false, true), true);
assert.equal(shouldUseSmartVoice("auto", false, false), false);
assert.equal(shouldUseSmartVoice("auto", true, false), true);
assert.equal(shouldUseSmartVoice("local-whisper", true, true), false);
assert.equal(shouldUseSmartVoice("local-funasr", true, true), false);

assert.equal(resolveLocalEngine({ localAsrEngine: "whisper" }), "whisper");
assert.equal(resolveLocalEngine({ localAsrEngine: "sensevoice" }), "sensevoice");
assert.equal(resolveLocalEngine({ asrProvider: "local-whisper" }), "whisper");
assert.equal(resolveLocalEngine({ asrProvider: "local-funasr" }), "sensevoice");
assert.equal(
	stripSenseVoiceTags("<|zh|><|NEUTRAL|><|Speech|>你好世界"),
	"你好世界",
);

console.log("voice setup self-check passed");
