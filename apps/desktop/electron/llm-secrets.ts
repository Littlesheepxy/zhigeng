export const LLM_KEY_FIELDS = [
	"dashscopeApiKey",
	"openrouterApiKey",
	"openaiApiKey",
	"anthropicApiKey",
	"deepseekApiKey",
	"moonshotApiKey",
	"zhipuApiKey",
] as const;

export type LlmKeyField = (typeof LLM_KEY_FIELDS)[number];

export const PROVIDER_TO_KEY_FIELD: Record<string, LlmKeyField> = {
	dashscope: "dashscopeApiKey",
	openrouter: "openrouterApiKey",
	openai: "openaiApiKey",
	anthropic: "anthropicApiKey",
	deepseek: "deepseekApiKey",
	moonshot: "moonshotApiKey",
	zhipu: "zhipuApiKey",
};

export const KEY_FIELD_TO_ENV: Record<LlmKeyField, string> = {
	dashscopeApiKey: "DASHSCOPE_API_KEY",
	openrouterApiKey: "OPENROUTER_API_KEY",
	openaiApiKey: "OPENAI_API_KEY",
	anthropicApiKey: "ANTHROPIC_API_KEY",
	deepseekApiKey: "DEEPSEEK_API_KEY",
	moonshotApiKey: "MOONSHOT_API_KEY",
	zhipuApiKey: "ZHIPU_API_KEY",
};

export type LlmSecretBag = Partial<Record<LlmKeyField, string>>;

export function extractLlmSecrets(config: Record<string, unknown>): LlmSecretBag {
	const secrets: LlmSecretBag = {};
	for (const field of LLM_KEY_FIELDS) {
		const value = config[field];
		if (typeof value === "string") secrets[field] = value;
	}
	return secrets;
}

export function mergeLlmSecrets(
	config: Record<string, unknown>,
	secrets: LlmSecretBag,
): Record<string, unknown> {
	return { ...config, ...secrets };
}

export function stripLlmSecrets<T extends Record<string, unknown>>(config: T): T {
	const next = { ...config };
	for (const field of LLM_KEY_FIELDS) {
		delete next[field];
	}
	return next;
}

/** Incoming empty string deletes; omitted fields keep existing. */
export function upsertLlmSecrets(existing: LlmSecretBag, incoming: LlmSecretBag): LlmSecretBag {
	const next = { ...existing };
	for (const field of LLM_KEY_FIELDS) {
		if (!(field in incoming)) continue;
		const value = incoming[field]?.trim() ?? "";
		if (value) next[field] = value;
		else delete next[field];
	}
	return next;
}

export function applyLlmSecretsToEnv(
	config: {
		plannerProvider?: string;
		fastProvider?: string;
		plannerBaseUrl?: string;
		fastBaseUrl?: string;
	} & LlmSecretBag,
): void {
	for (const field of LLM_KEY_FIELDS) {
		const envName = KEY_FIELD_TO_ENV[field];
		const value = config[field];
		if (typeof value === "string") {
			if (value.trim()) process.env[envName] = value.trim();
			else delete process.env[envName];
		}
	}

	const applyBaseUrl = (provider: string | undefined, url: string | undefined) => {
		const name = provider?.trim();
		if (!name || typeof url !== "string") return;
		const envName = `${name.toUpperCase()}_BASE_URL`;
		if (url.trim()) process.env[envName] = url.trim();
		else delete process.env[envName];
	};

	applyBaseUrl(config.plannerProvider, config.plannerBaseUrl);
	if (config.fastProvider?.trim()) {
		applyBaseUrl(config.fastProvider, config.fastBaseUrl);
	}
}

export function hasAnyLlmKey(secrets: LlmSecretBag): boolean {
	return LLM_KEY_FIELDS.some((field) => Boolean(secrets[field]?.trim()));
}
