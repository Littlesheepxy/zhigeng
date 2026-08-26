import { generateText } from "ai";
import { toLanguageModel } from "./providers.js";
import { hasApiKeyForProvider, resolveModelChoice } from "./model-choice.js";

export async function probeLlm(
	role: "planner" | "fast" = "planner",
): Promise<{ ok: true; provider: string; model: string } | { ok: false; error: string }> {
	const choice = resolveModelChoice(role);
	if (!hasApiKeyForProvider(choice.provider)) {
		return { ok: false, error: `还没有填 ${choice.provider} 的 API Key` };
	}
	try {
		const model = toLanguageModel(choice);
		await generateText({
			model,
			prompt: "Reply with ok",
			maxOutputTokens: 8,
			temperature: choice.provider === "moonshot" ? 1 : 0,
			abortSignal: AbortSignal.timeout(20_000),
		});
		return { ok: true, provider: choice.provider, model: choice.model };
	} catch (error) {
		return { ok: false, error: error instanceof Error ? error.message : String(error) };
	}
}
