import assert from "node:assert/strict";
import { extraProviderHeaders } from "./providers.js";
import { probeLlm } from "./probe-llm.js";

assert.equal(extraProviderHeaders("anthropic")?.["anthropic-version"], "2023-06-01");
assert.ok(extraProviderHeaders("openrouter")?.["HTTP-Referer"]);

const saved = {
	OPENROUTER_API_KEY: process.env.OPENROUTER_API_KEY,
	FOLD_PLANNER_PROVIDER: process.env.FOLD_PLANNER_PROVIDER,
};
delete process.env.OPENROUTER_API_KEY;
process.env.FOLD_PLANNER_PROVIDER = "openrouter";

const missing = await probeLlm("planner");
assert.equal(missing.ok, false);
if (!missing.ok) {
	assert.match(missing.error, /openrouter/i);
}

if (saved.OPENROUTER_API_KEY) process.env.OPENROUTER_API_KEY = saved.OPENROUTER_API_KEY;
else delete process.env.OPENROUTER_API_KEY;
if (saved.FOLD_PLANNER_PROVIDER) process.env.FOLD_PLANNER_PROVIDER = saved.FOLD_PLANNER_PROVIDER;
else delete process.env.FOLD_PLANNER_PROVIDER;

console.log("probe-llm self-check passed");
