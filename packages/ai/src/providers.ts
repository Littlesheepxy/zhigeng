import { createOpenAICompatible } from "@ai-sdk/openai-compatible";
import type { LanguageModel } from "ai";
import { PROVIDER_TABLE, type ModelChoice, type Provider } from "./types.js";

export function extraProviderHeaders(provider: Provider): Record<string, string> | undefined {
	if (provider === "openrouter") {
		return {
			"HTTP-Referer": process.env.OPENROUTER_REFERER ?? "https://fold.local",
			"X-Title": process.env.OPENROUTER_TITLE ?? "Fold Runtime",
		};
	}
	if (provider === "anthropic") {
		return { "anthropic-version": "2023-06-01" };
	}
	return undefined;
}

export function toLanguageModel(choice: ModelChoice): LanguageModel {
	const cfg = PROVIDER_TABLE[choice.provider as Provider];
	if (!cfg) throw new Error(`[providers] unknown provider: ${choice.provider}`);

	const rawKey = process.env[cfg.apiKeyEnv];
	if (!rawKey) {
		throw new Error(`[providers] ${cfg.displayName} missing API key (env: ${cfg.apiKeyEnv})`);
	}
	const apiKey = rawKey.trim().replace(/^["']|["']$/g, "");
	const baseURL =
		process.env[`${choice.provider.toUpperCase()}_BASE_URL`]?.trim() || cfg.baseURL;

	const provider = createOpenAICompatible({
		name: choice.provider,
		baseURL,
		apiKey,
		headers: extraProviderHeaders(choice.provider as Provider),
	});

	return provider(choice.model);
}
