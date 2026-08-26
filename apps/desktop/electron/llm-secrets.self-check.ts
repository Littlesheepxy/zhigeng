import assert from "node:assert/strict";
import {
	applyLlmSecretsToEnv,
	extractLlmSecrets,
	hasAnyLlmKey,
	stripLlmSecrets,
	upsertLlmSecrets,
} from "./llm-secrets.js";

const extracted = extractLlmSecrets({
	openaiApiKey: " sk-test ",
	planTier: "free",
});
assert.equal(extracted.openaiApiKey, " sk-test ");
assert.equal("planTier" in extracted, false);

const stripped = stripLlmSecrets({
	openaiApiKey: "sk-test",
	plannerProvider: "openai",
});
assert.equal(stripped.openaiApiKey, undefined);
assert.equal(stripped.plannerProvider, "openai");

const merged = upsertLlmSecrets(
	{ openaiApiKey: "old", dashscopeApiKey: "keep" },
	{ openaiApiKey: "new", dashscopeApiKey: "" },
);
assert.equal(merged.openaiApiKey, "new");
assert.equal(merged.dashscopeApiKey, undefined);
assert.equal(hasAnyLlmKey(merged), true);

process.env.OPENAI_API_KEY = "from-dotenv";
process.env.OPENROUTER_API_KEY = "keep-if-unset";
applyLlmSecretsToEnv({
	openaiApiKey: "",
	plannerProvider: "openai",
	plannerBaseUrl: "https://proxy.example/v1",
});
assert.equal(process.env.OPENAI_API_KEY, undefined);
assert.equal(process.env.OPENROUTER_API_KEY, "keep-if-unset");
assert.equal(process.env.OPENAI_BASE_URL, "https://proxy.example/v1");

delete process.env.OPENAI_BASE_URL;
applyLlmSecretsToEnv({
	openaiApiKey: "sk-live",
	plannerProvider: "anthropic",
	plannerBaseUrl: "https://api.anthropic.com/v1",
	fastProvider: "dashscope",
	fastBaseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
});
assert.equal(process.env.OPENAI_API_KEY, "sk-live");
assert.equal(process.env.ANTHROPIC_BASE_URL, "https://api.anthropic.com/v1");
assert.equal(process.env.DASHSCOPE_BASE_URL, "https://dashscope.aliyuncs.com/compatible-mode/v1");
assert.equal(process.env.OPENAI_BASE_URL, undefined);

console.log("llm-secrets self-check passed");
