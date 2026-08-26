export type HomeSection =
	| "overview"
	| "profile"
	| "work"
	| "tasks"
	| "connections"
	| "account"
	| "settings";
export type PlanTier = "free" | "pro" | "ultra";
export type AsrProvider = "auto" | "local-funasr" | "local-whisper" | "dashscope";
export type ExecutionMode = "auto" | "local_agent" | "fold_only";

import type { CapabilityItem, CapabilitySnapshot } from "@fold/runtime";

export type { CapabilityItem, CapabilitySnapshot };

export interface FoldConfig {
	planTier?: PlanTier;
	executionMode?: ExecutionMode;
	enabledCapabilities?: string[];
	preferredExecutor?: "claude-code" | "codex" | "cursor" | "workbuddy" | "auto";
	skipLocalAgent?: boolean;
	structureAutoInsert?: boolean;
	asrProvider?: AsrProvider;
	localWhisperModelPath?: string;
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
	/** 自动 Aha 主动建议档位 */
	ahaProactiveFrequency?: "off" | "low" | "normal" | "high";
	/** 转写整理程度：minimal=仅去语气词，smart=智能整理（默认），off=原文直出 */
	speechCleanupLevel?: "minimal" | "smart" | "off";
}

export type HotkeyAction = "trigger" | "agent" | "cancel";

export interface HotkeySettingsSnapshot {
	bindings: {
		trigger: { id: string; label: string };
		agent: { id: string; label: string; keys: string[] };
		cancel: { id: string; label: string; keys: string[] };
	};
	options: {
		trigger: Array<{ id: string; label: string }>;
		agent: Array<{ id: string; label: string; keys: string[] }>;
		cancel: Array<{ id: string; label: string; keys: string[] }>;
	};
	status: {
		trigger: boolean;
		agent: boolean;
		cancel: boolean;
		triggerUsesFallback: boolean;
	};
}

export interface HomeEpisode {
	id: string;
	intent: string;
	status: string;
	timestamp: number;
	summary: string;
}

export interface EpisodeSummary extends HomeEpisode {
	durationMs: number;
	goal?: string;
	steps?: Array<{ stepId?: string; skill: string; label: string; status: string }>;
	apps?: Array<{ name: string; path?: string | null }>;
	stepCount?: number;
	successCount?: number;
}

export interface EpisodeDetail {
	id: string;
	intent: string;
	goal: string;
	status: string;
	timestamp: number;
	summary: string;
	durationMs: number;
	thinkingText: string;
	resultDetail: string | null;
	probeSummary: string | null;
	steps: Array<{
		stepId: string;
		label: string;
		skill: string;
		status: string;
		durationMs: number;
		error?: string;
	}>;
	validationChecks: Array<{ rule: string; passed: boolean; message?: string }>;
	agentEvents: Array<{
		taskId: string;
		sequence: number;
		timestamp: number;
		source: string;
		status: string;
		message: string;
		elapsedMs?: number;
	}>;
	artifacts: Array<{ type: string; value: string; label?: string }>;
	memoryCandidates: Array<{
		type: string;
		key: string;
		value: string;
		confidence: number;
		reason?: string;
		requiresConfirmation: true;
	}>;
	contextEvents: Array<{
		id: string;
		type: string;
		timestamp: number;
		data: {
			appName?: string;
			windowTitle?: string;
			appPath?: string;
			filePath?: string;
			url?: string;
			text?: string;
		};
	}>;
}

export interface HomeConnection {
	id: string;
	label: string;
	status: "ok" | "warn" | "error";
	detail?: string;
	meta?: Record<string, string | boolean | null | undefined>;
}

export interface HomeConfigSummary {
	hasPlannerKey: boolean;
	hasAsr: boolean;
	mailProvider: string;
	allowAgentSubagents: boolean;
	allowWorkbuddy: boolean;
	allowUitars: boolean;
}

export interface HomeAhaGuess {
	reply: string;
	confidenceLevel?: "high" | "medium" | "low";
	confidenceScore?: number;
	suggestions: Array<{
		label: string;
		intent: string;
		reason: string;
		confidence: number;
	}>;
}

export interface HomePredictPreview {
	anchor: string | null;
	phase: "silent" | "pick" | "result";
	activeApp: string | null;
	activeWindow: string | null;
	suggestions: Array<{
		label: string;
		intent: string;
		reason: string;
		confidence: number;
	}>;
}

export interface HomeSnapshot {
	episodes: HomeEpisode[];
	liveContext: {
		activeApp: string | null;
		activeWindow: string | null;
		recentUrls: Array<{ url: string; title: string }>;
		recentFiles: Array<{ path: string; name: string }>;
	};
	connections: HomeConnection[];
	capabilitySnapshot: CapabilitySnapshot;
	configSummary: HomeConfigSummary;
	userProfile: UserProfileData | null;
}

export interface HomeContextEvent {
	id: string;
	type: string;
	timestamp: number;
	data: {
		appName?: string;
		windowTitle?: string;
		appPath?: string;
		filePath?: string;
		url?: string;
		text?: string;
		origin?: "user" | "fold";
	};
}

export interface ClipboardHistoryItem {
	id: string;
	timestamp: number;
	text: string;
	appName: string | null;
	windowTitle: string | null;
	appPath: string | null;
}

export interface LiveContextLite {
	activeApp: string | null;
	activeWindow: string | null;
	activeAppPath: string | null;
	recentUrls: Array<{ url: string; title: string }>;
	recentFiles: Array<{ path: string; name: string }>;
	clipboardPreview: string | null;
	recentClipboards: ClipboardHistoryItem[];
	focusDwells?: Array<{
		app: string;
		windowTitle?: string;
		dwellMs: number;
	}>;
	events: HomeContextEvent[];
}

export interface UserProfileData {
	summary?: string;
	role?: string;
	domains?: string[];
	preferredTools?: string[];
	workPatterns?: string[];
	communicationStyle?: string;
	constraints?: string[];
	migrationArchive?: string;
	updatedAt?: number;
}

export interface PersonMemoryValue {
	name: string;
	role?: string;
	commitment?: string;
	projectKeys?: string[];
	episodeIds: string[];
	lastSeenDate: string;
	history?: Array<{ date: string; note: string }>;
}

export interface ProjectMemoryValue {
	name: string;
	status?: string;
	nextStep?: string;
	personKeys?: string[];
	filePaths?: string[];
	episodeIds: string[];
	lastActiveDate: string;
	history?: Array<{ date: string; note: string }>;
}

export type MemoryEntityRecord =
	| {
			id: string;
			type: "entity.person";
			key: string;
			value: PersonMemoryValue;
			confidence: number;
			updatedAt: number;
	  }
	| {
			id: string;
			type: "entity.project";
			key: string;
			value: ProjectMemoryValue;
			confidence: number;
			updatedAt: number;
	  };
