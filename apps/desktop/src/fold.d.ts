import type { FoldStateEvent } from "@fold/runtime";
import type {
	FoldConfig,
	EpisodeDetail,
	EpisodeSummary,
	HomeContextEvent,
	HomeAhaGuess,
	HomePredictPreview,
	HomeSnapshot,
	LiveContextLite,
	UserProfileData,
	MemoryEntityRecord,
	PersonMemoryValue,
	ProjectMemoryValue,
	HotkeyAction,
	HotkeySettingsSnapshot,
} from "./settings/types.js";

interface ProfileImportOption {
	id: string;
	label: string;
	hasOpenTab: boolean;
	tabUrl?: string;
	tabTitle?: string;
	defaultUrl: string;
	automationSupported: boolean;
}

interface VoiceSessionStart {
	mode: "structure" | "reply" | "agent" | "interaction";
	app?: string | null;
	windowTitle?: string | null;
}

interface FoldApi {
	onState(cb: (state: FoldStateEvent) => void): () => void;
	onTranscript(cb: (text: string) => void): () => void;
	onVoiceLevel(cb: (level: number) => void): () => void;
	getUseMockAsr(): Promise<boolean>;
	getVoiceSetup(): Promise<{
		planTier: "free" | "pro" | "ultra";
		mode: "cloud" | "local" | "download-needed";
		ready: boolean;
		title: string;
		detail: string;
		downloadSizeMb?: number;
		trialRemaining?: number;
	}>;
	downloadVoicePack(): Promise<{ ok: true; path: string } | { ok: false; error: string }>;
	getAsrRuntime(): Promise<{
		provider: "mock" | "dashscope" | "local-whisper";
		modelPath?: string;
		ready: boolean;
		authToken?: string;
		hotWords?: string[];
	}>;
	localAsrStart(): Promise<{ ok: boolean }>;
	localAsrAudio(chunk: ArrayBuffer): void;
	localAsrFinish(): Promise<string>;
	localAsrCancel(): Promise<{ ok: boolean }>;
	runTask(intent: string): Promise<void>;
	structureVoice(transcript: string, opts?: { directStructured?: boolean }): Promise<void>;
	replyVoice(transcript: string): Promise<void>;
	retryTask(): Promise<void>;
	undoLastInsert(): Promise<{ ok: boolean; error?: string }>;
	askResponse(
		response:
			| string
			| {
					requestId?: string;
					optionId?: string;
					text?: string;
					modality: "click" | "voice" | "text" | "terminal";
			  },
	): Promise<void>;
	interactionVoice(transcript: string): Promise<void>;
	toggleInteractionVoice(): Promise<void>;
	getConfig(): Promise<FoldConfig>;
	getHotkeySettings(): Promise<HotkeySettingsSnapshot>;
	setHotkeyBinding(
		action: HotkeyAction,
		presetId: string,
	): Promise<
		| { ok: true; settings: HotkeySettingsSnapshot }
		| { ok: false; reason: "occupied" | "conflict" | "duplicate-accelerator" | "invalid" }
	>;
	getHomeSnapshot(): Promise<HomeSnapshot>;
	getPredictPreview(): Promise<HomePredictPreview>;
	startAhaGuess(): Promise<{ ok: boolean; runId?: number }>;
	cancelAhaGuess(): Promise<{ ok: boolean }>;
	onAhaGuessChunk(cb: (payload: { runId: number; chunk: string }) => void): () => void;
	onAhaGuessDone(
		cb: (payload: {
			runId: number;
			suggestions?: HomeAhaGuess["suggestions"];
			reply?: string;
			error?: string;
			confidenceLevel?: HomeAhaGuess["confidenceLevel"];
			confidenceScore?: number;
		}) => void,
	): () => void;
	getLiveContext(): Promise<LiveContextLite>;
	restoreClipboard(payload: { id?: string; text?: string }): Promise<{ ok: boolean }>;
	focusContext(
		target: { kind: "app"; appName: string } | { kind: "url"; url: string },
	): Promise<{ ok: boolean }>;
	getAppIcon(appPath: string, appName?: string): Promise<string | null>;
	getFirstAppIcon(appNames: string[]): Promise<string | null>;
	listEpisodes(): Promise<EpisodeSummary[]>;
	listMemoryEntities(): Promise<MemoryEntityRecord[]>;
	deactivateMemory(id: string): Promise<{ ok: boolean }>;
	removeProfileConstraint(text: string): Promise<{ ok: boolean }>;
	runMemoryConsolidation(): Promise<{ ok: boolean; dates: string[] }>;
	codexRemoteStatus(): Promise<{
		status: "disabled" | "connecting" | "connected" | "errored" | "unknown";
		serverName?: string | null;
		environmentId?: string | null;
		error?: string;
	}>;
	codexRemoteEnable(): Promise<{
		status: "disabled" | "connecting" | "connected" | "errored" | "unknown";
		serverName?: string | null;
		environmentId?: string | null;
		error?: string;
	}>;
	codexRemoteDisable(): Promise<{
		status: "disabled" | "connecting" | "connected" | "errored" | "unknown";
		serverName?: string | null;
		environmentId?: string | null;
		error?: string;
	}>;
	codexRemotePairStart(): Promise<{
		pairingCode?: string;
		manualPairingCode?: string;
		environmentId?: string;
		expiresAt?: number;
	}>;
	codexRemotePairPoll(input: {
		pairingCode?: string;
		manualPairingCode?: string;
	}): Promise<{ claimed: boolean }>;
	codexRemoteClients(): Promise<{
		environmentId: string | null;
		clients: Array<{
			clientId: string;
			name?: string;
			lastConnectedAt?: number;
			platform?: string;
		}>;
		error?: string;
	}>;
	codexRemoteRevoke(clientId: string): Promise<{ ok: boolean; error?: string }>;
	zhigengRemoteStatus(): Promise<{
		configured: boolean;
		deviceId: string | null;
		state: "disabled" | "connecting" | "connected" | "error";
		error: string | null;
	}>;
	zhigengRemotePairStart(): Promise<{
		pairingId: string;
		code: string;
		qrPayload: string;
		expiresAt: string;
	}>;
	zhigengRemotePairPoll(pairingId: string): Promise<{
		status: "pending" | "claimed" | "expired" | "canceled";
	}>;
	zhigengRemoteDevices(): Promise<{
		devices: Array<{
			id: string;
			kind: "mac" | "ios";
			name: string;
			lastSeenAt: string | null;
			revokedAt: string | null;
		}>;
	}>;
	zhigengRemoteRevoke(deviceId: string): Promise<{ ok: true }>;
	getEpisode(id: string): Promise<EpisodeDetail | null>;
	predictPickIntent(intent: string): Promise<{ ok: boolean }>;
	predictInsertDraft(text: string): Promise<{ ok: boolean; pasted: boolean; error?: string }>;
	predictFeedback(payload: {
		kind: "dismiss" | "reject" | "accept" | "edited" | "undo" | "ignore";
		surface?: string | null;
		intent?: string | null;
		draft?: string | null;
		anchor?: string | null;
	}): Promise<{ ok: boolean }>;
	structureInsertDraft(text: string, targetAppName?: string | null): Promise<{
		ok: boolean;
		pasted: boolean;
		error?: string;
	}>;
	copyText(text: string): Promise<{ ok: boolean }>;
	predictStartVoice(): Promise<{ ok: boolean }>;
	predictRefineVoice(): Promise<{ ok: boolean }>;
	profileImportOptions(): Promise<ProfileImportOption[]>;
	profileBuildPrompt(): Promise<string>;
	profileCopyPrompt(): Promise<{ prompt: string }>;
	profileGet(): Promise<UserProfileData | null>;
	profileRunImport(
		platformId: string,
		tabUrl?: string,
	): Promise<{ ok: boolean; response?: string; error?: string; prompt: string }>;
	profileSaveResponse(responseText: string): Promise<{
		ok: boolean;
		error?: string;
		profile?: UserProfileData;
	}>;
	profileSaveSeed(input: {
		role?: string;
		domains?: string[];
		keywords?: string[];
	}): Promise<{ ok: boolean }>;
	onContextEvent(cb: (event: HomeContextEvent) => void): () => void;
	runConnectionAction(action: string, context?: Record<string, unknown>): Promise<{ ok: boolean }>;
	startConnectFlow(
		connectionId: string,
		kind: "login" | "install",
	): Promise<{
		sessionId: string;
		title: string;
		message: string;
		authUrl?: string;
		userCode?: string;
		opensBrowserAutomatically?: boolean;
		copyText?: string;
		copyThenOpen?: boolean;
		requiresAction?: boolean;
		actionLabel?: string;
	}>;
	pollConnectFlow(sessionId: string): Promise<{
		status: "pending" | "success" | "error";
		message?: string;
		error?: string;
	}>;
	activateConnectFlow(sessionId: string): Promise<{ ok: boolean; opened: boolean; url?: string }>;
	cancelConnectFlow(sessionId: string): Promise<{ ok: boolean }>;
	openExternal(url: string): Promise<{ ok: boolean }>;
	openDataDir(): Promise<{ ok: boolean; path?: string; error?: string }>;
	saveConfig(config: FoldConfig): Promise<{ ok: boolean }>;
	accountGetState(): Promise<{
		signedIn: boolean;
		email?: string;
		name?: string;
		userId?: string;
		planTier: "free" | "pro" | "ultra";
		voiceSecondsRemaining?: number;
		smartActionsRemaining?: number;
		voiceSecondsLimit?: number;
		smartActionsLimit?: number;
		periodEnd?: string;
		syncedAt?: number;
	}>;
	accountRequestCode(email: string): Promise<{ ok: true; mode: string } | { ok: false; error: string }>;
	accountVerifyCode(input: {
		email: string;
		code: string;
	}): Promise<
		| {
				ok: true;
				state: {
					signedIn: boolean;
					email?: string;
					name?: string;
					userId?: string;
					planTier: "free" | "pro" | "ultra";
					voiceSecondsRemaining?: number;
					smartActionsRemaining?: number;
					syncedAt?: number;
				};
		  }
		| { ok: false; error: string }
	>;
	accountLogout(): Promise<{
		signedIn: boolean;
		planTier: "free" | "pro" | "ultra";
	}>;
	accountSync(): Promise<{
		signedIn: boolean;
		email?: string;
		name?: string;
		userId?: string;
		planTier: "free" | "pro" | "ultra";
		voiceSecondsRemaining?: number;
		smartActionsRemaining?: number;
		syncedAt?: number;
	}>;
	accountUpdateName(
		name: string,
	): Promise<{ ok: true; state: { name?: string } } | { ok: false; error: string }>;
	accountCheckout(input: {
		productId: string;
	}): Promise<
		| {
				ok: true;
				mode: string;
				activated?: boolean;
				checkoutUrl?: string;
				state: { planTier: "free" | "pro" | "ultra" };
		  }
		| { ok: false; error: string }
	>;
	accountCancelPlan(): Promise<
		{ ok: true; state: { planTier: "free" | "pro" | "ultra" } } | { ok: false; error: string }
	>;
	accountDelete(): Promise<
		{ ok: true; state: { signedIn: boolean } } | { ok: false; error: string }
	>;
	setMousePassthrough(ignore: boolean): void;
	getDisplayWorkArea(overlayPoint?: { x: number; y: number }): Promise<{
		x: number;
		y: number;
		width: number;
		height: number;
	}>;
	getOverlayState(): Promise<FoldStateEvent>;
	dismiss(opts?: { skipFeedback?: boolean; soft?: boolean }): Promise<void>;
	voiceEmpty(): Promise<{ ok: boolean; standby: boolean }>;
	toggleVoice(): Promise<void>;
	voiceError(message: string): Promise<void>;
	openSettings(section?: string): Promise<void>;
	scanInputHabits(): Promise<Record<string, unknown>>;
	listInstalledInputMethods(): Promise<Record<string, unknown>[]>;
	importInputHabits(): Promise<Record<string, unknown>>;
	getImportedInputHabits(): Promise<Record<string, unknown> | null>;
	exportInputHabitsRime(): Promise<Record<string, unknown> & { canceled?: boolean }>;
	quit(): Promise<void>;
	onHotkeyDown(cb: (session: VoiceSessionStart) => void): () => void;
	onVoiceWarm(cb: () => void): () => void;
	onHotkeyUp(cb: (mode: "structure" | "reply" | "agent" | "interaction") => void): () => void;
	onHotkeyCancel(cb: () => void): () => void;
	onHomeNavigate(cb: (section: string) => void): () => void;
	probeAccessibility(): Promise<{
		available: boolean;
		appLabel: string;
		bundlePath?: string;
		error?: string;
	}>;
	openAccessibilitySettings(): Promise<{ ok: boolean }>;
	onboardingGetState(): Promise<{
		completedAt?: number;
		step?: string;
		profileImportedAt?: number;
		profileImportSkippedAt?: number;
	}>;
	openOnboarding(opts?: { reset?: boolean }): Promise<{ ok: boolean }>;
	onboardingSetStep(step: string): Promise<Record<string, unknown>>;
	onboardingComplete(): Promise<{ ok: boolean }>;
	onboardingSkipProfile(): Promise<Record<string, unknown>>;
	onboardingCompareDemo(opts: { withProfile: boolean }): Promise<OnboardingCompareResult>;
	onboardingStructureVoice(transcript: string): Promise<string>;
	onboardingSetVoiceApp(app: string, windowTitle?: string): Promise<{ ok: boolean }>;
	onboardingAhaGuess(): Promise<{ ok: boolean; runId?: number }>;
	onboardingSimulateClipboard(lines: string[]): Promise<{
		ok: boolean;
		previous?: { id: string; text: string; appName?: string };
		current?: { id: string; text: string; appName?: string };
	}>;
	onOnboardingHotkeyEvent(cb: (payload: {
		key: string;
		phase: "down" | "up";
		longPress?: boolean;
	}) => void): () => void;
	onOnboardingVoiceEvent(cb: (payload: {
		phase: "listening" | "formatting" | "done" | "error";
		raw?: string;
		cleaned?: string;
		error?: string;
	}) => void): () => void;
}

interface OnboardingCompareResult {
	incoming: string;
	before: { transcript: string; reply: string };
	after: { transcript: string; reply: string };
	keywords: string[];
	checklist: string[];
	profileSummary?: {
		role?: string;
		domains?: string[];
		communicationStyle?: string;
	};
}

declare global {
	interface Window {
		fold: FoldApi;
	}
}

export {};
