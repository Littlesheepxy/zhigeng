import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
	canUseSmartAction,
	consumeTrialSmartAction,
	INITIAL_TRIAL_SMART_ACTIONS,
	normalizePlanTier,
	remainingTrialSmartActions,
	resolveEntitlements,
	deriveExecutionFlags,
	normalizeExecutionMode,
	type PlanTier,
} from "@fold/runtime";
import { resolveDataDir } from "./data-dir.js";
import { loadAccountSecret, loadLlmSecretsJson, saveLlmSecretsJson } from "./secure-store.js";
import {
	applyLlmSecretsToEnv,
	extractLlmSecrets,
	stripLlmSecrets,
	upsertLlmSecrets,
	type LlmSecretBag,
} from "./llm-secrets.js";

export type AsrProvider = "auto" | "local-funasr" | "local-whisper" | "dashscope";

export interface FoldConfig {
	planTier?: PlanTier;
	asrProvider?: AsrProvider;
	localWhisperModelPath?: string;
	/** 离线引擎：阿里 SenseVoice 或 Whisper；auto 回退本地时用这个 */
	localAsrEngine?: "whisper" | "sensevoice";
	trialSmartActionsRemaining?: number;
	byokOverrides?: boolean;
	dashscopeApiKey?: string;
	openrouterApiKey?: string;
	openaiApiKey?: string;
	anthropicApiKey?: string;
	deepseekApiKey?: string;
	moonshotApiKey?: string;
	zhipuApiKey?: string;
	zhipuOcrModel?: string;
	plannerProvider?: string;
	plannerModel?: string;
	plannerBaseUrl?: string;
	/** 转写净化、代回草案；留空则用各 Provider 默认快模型 */
	fastProvider?: string;
	fastModel?: string;
	fastBaseUrl?: string;
	mailProvider?: string;
	nangoSecretKey?: string;
	hubApiKey?: string;
	accountUserId?: string;
	accountEmail?: string;
	accountName?: string;
	accountSyncedAt?: number;
	voiceSecondsRemaining?: number;
	smartActionsRemaining?: number;
	voiceSecondsLimit?: number;
	smartActionsLimit?: number;
	periodEnd?: string;
	playwrightMcpExtensionToken?: string;
	asrWsUrl?: string;
	chromeCdpUrl?: string;
	allowScriptExecution?: boolean;
	allowFileWrite?: boolean;
	allowAgentSubagents?: boolean;
	allowUitars?: boolean;
	allowWorkbuddy?: boolean;
	workbuddyGatewayUrl?: string;
	workbuddyMcpToken?: string;
	uitarsVlmBaseUrl?: string;
	uitarsVlmApiKey?: string;
	uitarsVlmModel?: string;
	executionMode?: "auto" | "local_agent" | "fold_only";
	enabledCapabilities?: string[];
	preferredExecutor?: "claude-code" | "codex" | "cursor" | "workbuddy" | "auto";
	skipLocalAgent?: boolean;
	/** 转写整理完成后自动粘贴到前台输入框；默认 true */
	structureAutoInsert?: boolean;
	/** 自动 Aha 主动建议档位：off=关闭（默认），low/normal/high 控制后台刷新与弹出节奏 */
	ahaProactiveFrequency?: "off" | "low" | "normal" | "high";
	/** 转写整理程度：minimal=仅去语气词，smart=智能整理（默认），off=原文直出 */
	speechCleanupLevel?: "minimal" | "smart" | "off";
	/** 转写/代回成功后保持目标 App 的秒数；0=关闭（Mac 默认）。实验可设 8；iOS 另议 */
	voiceStandbySeconds?: number;
	onboarding?: {
		completedAt?: number;
		step?: string;
		profileImportedAt?: number;
		profileImportSkippedAt?: number;
	};
	hotkeys?: {
		trigger?: string;
		agent?: string;
		cancel?: string;
	};
}

export type ExecutionMode = "auto" | "local_agent" | "fold_only";

function configDir(): string {
	return resolveDataDir();
}

function configPath(): string {
	return join(configDir(), "config.json");
}

export function getConfigPath(): string {
	return configPath();
}

function readStoredLlmSecrets(): LlmSecretBag {
	const raw = loadLlmSecretsJson();
	if (!raw) return {};
	try {
		const parsed = JSON.parse(raw) as LlmSecretBag;
		return parsed && typeof parsed === "object" ? parsed : {};
	} catch {
		return {};
	}
}

function persistLlmSecrets(secrets: LlmSecretBag): void {
	saveLlmSecretsJson(JSON.stringify(secrets));
}

function withLlmSecrets(config: FoldConfig): FoldConfig {
	return { ...config, ...readStoredLlmSecrets() };
}

export function loadConfig(): FoldConfig {
	const path = configPath();
	try {
		if (!existsSync(path)) {
			return withLlmSecrets({
				planTier: "free",
				asrProvider: "auto",
				executionMode: "auto",
				trialSmartActionsRemaining: INITIAL_TRIAL_SMART_ACTIONS,
			});
		}
		const config = JSON.parse(readFileSync(path, "utf8")) as FoldConfig;
		const fromFile = extractLlmSecrets(config as unknown as Record<string, unknown>);
		if (Object.keys(fromFile).length > 0) {
			persistLlmSecrets(upsertLlmSecrets(readStoredLlmSecrets(), fromFile));
			const stripped = stripLlmSecrets(config as unknown as Record<string, unknown>) as FoldConfig;
			writeFileSync(path, JSON.stringify({
				...stripped,
				planTier: normalizePlanTier(stripped.planTier),
				asrProvider: stripped.asrProvider ?? "auto",
			}, null, 2), "utf8");
		}
		return withLlmSecrets({
			...config,
			planTier: normalizePlanTier(config.planTier),
			asrProvider: config.asrProvider ?? "auto",
			trialSmartActionsRemaining: remainingTrialSmartActions(
				config.trialSmartActionsRemaining,
			),
		});
	} catch {
		return withLlmSecrets({
			planTier: "free",
			asrProvider: "auto",
			trialSmartActionsRemaining: INITIAL_TRIAL_SMART_ACTIONS,
		});
	}
}

export function saveConfig(config: FoldConfig): void {
	const dir = configDir();
	if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
	persistLlmSecrets(
		upsertLlmSecrets(
			readStoredLlmSecrets(),
			extractLlmSecrets(config as unknown as Record<string, unknown>),
		),
	);
	const normalized = stripLlmSecrets({
		...config,
		planTier: normalizePlanTier(config.planTier),
		asrProvider: config.asrProvider ?? "auto",
		trialSmartActionsRemaining: remainingTrialSmartActions(
			config.trialSmartActionsRemaining,
		),
	} as unknown as Record<string, unknown>) as FoldConfig;
	writeFileSync(configPath(), JSON.stringify(normalized, null, 2), "utf8");
}

/** Merge saved config into process.env for runtime packages. */
export function applyConfigToEnv(config: FoldConfig = loadConfig()): void {
	process.env.FOLD_PLAN_TIER = normalizePlanTier(config.planTier);
	process.env.FOLD_EXECUTION_MODE = normalizeExecutionMode(config.executionMode);
	if (config.preferredExecutor) {
		process.env.FOLD_PREFERRED_EXECUTOR = config.preferredExecutor;
	}
	const flags = deriveExecutionFlags({
		executionMode: config.executionMode ?? "auto",
		enabledCapabilities: config.enabledCapabilities,
	});
	process.env.FOLD_ALLOW_AGENT_SUBAGENTS = flags.allowAgentSubagents ? "1" : "0";
	process.env.FOLD_ALLOW_WORKBUDDY = flags.allowWorkbuddy ? "1" : "0";
	process.env.FOLD_ASR_PROVIDER = config.asrProvider ?? "auto";
	if (config.localWhisperModelPath) {
		process.env.FOLD_LOCAL_WHISPER_MODEL_PATH = config.localWhisperModelPath;
	}
	process.env.FOLD_TRIAL_SMART_ACTIONS_REMAINING = String(
		remainingTrialSmartActions(config.trialSmartActionsRemaining),
	);
	applyLlmSecretsToEnv(config);
	if (config.zhipuOcrModel) process.env.ZHIPU_OCR_MODEL = config.zhipuOcrModel;
	if (config.plannerProvider) process.env.FOLD_PLANNER_PROVIDER = config.plannerProvider;
	if (config.plannerModel) process.env.FOLD_PLANNER_MODEL = config.plannerModel;
	if (config.fastProvider) process.env.FOLD_FAST_PROVIDER = config.fastProvider;
	if (config.fastModel) process.env.FOLD_FAST_MODEL = config.fastModel;
	if (config.mailProvider) process.env.FOLD_MAIL_PROVIDER = config.mailProvider;
	if (config.nangoSecretKey) process.env.FOLD_NANGO_SECRET_KEY = config.nangoSecretKey;
	if (config.hubApiKey) process.env.FOLD_HUB_API_KEY = config.hubApiKey;
	const accountSecret = loadAccountSecret();
	if (accountSecret) process.env.FOLD_HUB_API_KEY = accountSecret;
	if (config.playwrightMcpExtensionToken) {
		process.env.PLAYWRIGHT_MCP_EXTENSION_TOKEN = config.playwrightMcpExtensionToken;
	}
	if (config.asrWsUrl) process.env.FOLD_ASR_WS_URL = config.asrWsUrl;
	if (config.chromeCdpUrl) process.env.FOLD_CHROME_CDP_URL = config.chromeCdpUrl;
	if (typeof config.allowScriptExecution === "boolean") {
		process.env.FOLD_ALLOW_SCRIPT_EXECUTION = config.allowScriptExecution ? "1" : "0";
	}
	if (typeof config.allowFileWrite === "boolean") {
		process.env.FOLD_ALLOW_FILE_WRITE = config.allowFileWrite ? "1" : "0";
	}
	if (typeof config.allowAgentSubagents === "boolean") {
		process.env.FOLD_ALLOW_AGENT_SUBAGENTS = config.allowAgentSubagents ? "1" : "0";
	}
	if (typeof config.allowUitars === "boolean") {
		process.env.FOLD_ALLOW_UITARS = config.allowUitars ? "1" : "0";
	}
	if (typeof config.allowWorkbuddy === "boolean") {
		process.env.FOLD_ALLOW_WORKBUDDY = config.allowWorkbuddy ? "1" : "0";
	}
	if (config.workbuddyGatewayUrl?.trim()) {
		process.env.FOLD_WORKBUDDY_GATEWAY_URL_MANUAL = config.workbuddyGatewayUrl.trim();
	} else {
		delete process.env.FOLD_WORKBUDDY_GATEWAY_URL_MANUAL;
	}
	if (config.workbuddyMcpToken?.trim()) {
		process.env.FOLD_WORKBUDDY_MCP_TOKEN_MANUAL = config.workbuddyMcpToken.trim();
	} else {
		delete process.env.FOLD_WORKBUDDY_MCP_TOKEN_MANUAL;
	}
	delete process.env.FOLD_WORKBUDDY_GATEWAY_URL;
	delete process.env.FOLD_WORKBUDDY_MCP_TOKEN;
	if (config.uitarsVlmBaseUrl) {
		process.env.FOLD_UITARS_VLM_BASE_URL = config.uitarsVlmBaseUrl;
	}
	if (config.uitarsVlmApiKey) {
		process.env.FOLD_UITARS_VLM_API_KEY = config.uitarsVlmApiKey;
	}
	if (config.uitarsVlmModel) {
		process.env.FOLD_UITARS_VLM_MODEL = config.uitarsVlmModel;
	}
}

export function hasRealAsr(config: FoldConfig = loadConfig()): boolean {
	const key = config.dashscopeApiKey ?? process.env.DASHSCOPE_API_KEY;
	return Boolean(key?.trim());
}

export function resolveSmartActionAccess(config: FoldConfig = loadConfig()): {
	allowed: boolean;
	usesTrial: boolean;
} {
	const entitlements = resolveEntitlements(config.planTier);
	const hasByok = config.byokOverrides === true;
	return {
		allowed: canUseSmartAction(
			entitlements,
			config.trialSmartActionsRemaining,
			hasByok,
		),
		usesTrial: entitlements.tier === "free" && !hasByok,
	};
}

export function consumeSmartActionTrial(config: FoldConfig = loadConfig()): FoldConfig {
	const access = resolveSmartActionAccess(config);
	if (!access.usesTrial || !access.allowed) return config;
	const next = {
		...config,
		trialSmartActionsRemaining: consumeTrialSmartAction(
			config.trialSmartActionsRemaining,
		),
	};
	saveConfig(next);
	applyConfigToEnv(next);
	return next;
}
