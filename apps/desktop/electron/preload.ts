import { contextBridge, ipcRenderer } from "electron";

type VoiceMode = "structure" | "reply" | "agent" | "interaction";
type UserActionResponse = {
	requestId?: string;
	optionId?: string;
	text?: string;
	modality: "click" | "voice" | "text" | "terminal";
};
type VoiceSessionStart = {
	mode: VoiceMode;
	app?: string | null;
	windowTitle?: string | null;
};

export interface FoldStateEvent {
	status: string;
	transcript?: string;
	steps?: Array<{ id: string; label: string; status: string }>;
	currentApp?: string | null;
	result?: string | null;
	resultDetail?: string | null;
	verificationChecks?: Array<{ rule: string; passed: boolean; message?: string }>;
	undoAvailable?: boolean;
	error?: string | null;
	askOptions?: Array<{ id: string; label: string }>;
}

contextBridge.exposeInMainWorld("fold", {
	onState(cb: (state: FoldStateEvent) => void) {
		const handler = (_: unknown, state: FoldStateEvent) => cb(state);
		ipcRenderer.on("fold:state", handler);
		return () => ipcRenderer.removeListener("fold:state", handler);
	},
	onTranscript(cb: (text: string) => void) {
		const handler = (_: unknown, text: string) => cb(text);
		ipcRenderer.on("fold:transcript", handler);
		return () => ipcRenderer.removeListener("fold:transcript", handler);
	},
	onVoiceLevel(cb: (level: number) => void) {
		const handler = (_: unknown, level: number) => cb(level);
		ipcRenderer.on("fold:voice-level", handler);
		return () => ipcRenderer.removeListener("fold:voice-level", handler);
	},
	getUseMockAsr: () => ipcRenderer.invoke("fold:get-mock-asr") as Promise<boolean>,
	getVoiceSetup: () =>
		ipcRenderer.invoke("fold:get-voice-setup") as Promise<{
			planTier: "free" | "pro" | "ultra";
			mode: "cloud" | "local" | "download-needed";
			ready: boolean;
			title: string;
			detail: string;
			downloadSizeMb?: number;
			trialRemaining?: number;
		}>,
	downloadVoicePack: () =>
		ipcRenderer.invoke("fold:download-voice-pack") as Promise<
			{ ok: true; path: string } | { ok: false; error: string }
		>,
	getAsrRuntime: () =>
		ipcRenderer.invoke("fold:get-asr-runtime") as Promise<{
			provider: "mock" | "dashscope" | "local-whisper";
			modelPath?: string;
			ready: boolean;
			authToken?: string;
			hotWords?: string[];
		}>,
	localAsrStart: () =>
		ipcRenderer.invoke("fold:local-asr-start") as Promise<{ ok: boolean }>,
	localAsrAudio: (chunk: ArrayBuffer) => {
		ipcRenderer.send("fold:local-asr-audio", chunk);
	},
	localAsrFinish: () =>
		ipcRenderer.invoke("fold:local-asr-finish") as Promise<string>,
	localAsrCancel: () =>
		ipcRenderer.invoke("fold:local-asr-cancel") as Promise<{ ok: boolean }>,
	runTask: (intent: string) => ipcRenderer.invoke("fold:run-task", intent) as Promise<void>,
	structureVoice: (transcript: string, opts?: { directStructured?: boolean }) =>
		ipcRenderer.invoke("fold:structure-voice", transcript, opts) as Promise<void>,
	replyVoice: (transcript: string) =>
		ipcRenderer.invoke("fold:reply-voice", transcript) as Promise<void>,
	retryTask: () => ipcRenderer.invoke("fold:retry-task") as Promise<void>,
	undoLastInsert: () =>
		ipcRenderer.invoke("fold:undo-last-insert") as Promise<{ ok: boolean; error?: string }>,
	askResponse: (response: string | UserActionResponse) =>
		ipcRenderer.invoke("fold:ask-response", response) as Promise<void>,
	interactionVoice: (transcript: string) =>
		ipcRenderer.invoke("fold:interaction-voice", transcript) as Promise<void>,
	toggleInteractionVoice: () =>
		ipcRenderer.invoke("fold:toggle-interaction-voice") as Promise<void>,
	getConfig: () => ipcRenderer.invoke("fold:get-config") as Promise<Record<string, unknown>>,
	getHotkeySettings: () =>
		ipcRenderer.invoke("fold:get-hotkey-settings") as Promise<{
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
		}>,
	setHotkeyBinding: (action: "trigger" | "agent" | "cancel", presetId: string) =>
		ipcRenderer.invoke("fold:set-hotkey-binding", action, presetId) as Promise<
			| { ok: true; settings: Record<string, unknown> }
			| { ok: false; reason: "occupied" | "conflict" | "duplicate-accelerator" | "invalid" }
		>,
	getHomeSnapshot: () => ipcRenderer.invoke("fold:get-home-snapshot") as Promise<Record<string, unknown>>,
	getPredictPreview: () => ipcRenderer.invoke("fold:get-predict-preview") as Promise<Record<string, unknown>>,
	startAhaGuess: () =>
		ipcRenderer.invoke("fold:start-aha-guess") as Promise<{ ok: boolean; runId?: number }>,
	cancelAhaGuess: () => ipcRenderer.invoke("fold:cancel-aha-guess") as Promise<{ ok: boolean }>,
	getLiveContext: () => ipcRenderer.invoke("fold:get-live-context") as Promise<Record<string, unknown>>,
	restoreClipboard: (payload: { id?: string; text?: string }) =>
		ipcRenderer.invoke("fold:restore-clipboard", payload) as Promise<{ ok: boolean }>,
	focusContext: (target: { kind: "app"; appName: string } | { kind: "url"; url: string }) =>
		ipcRenderer.invoke("fold:focus-context", target) as Promise<{ ok: boolean }>,
	getAppIcon: (appPath: string, appName?: string) =>
		ipcRenderer.invoke("fold:get-app-icon", appPath, appName) as Promise<string | null>,
	getFirstAppIcon: (appNames: string[]) =>
		ipcRenderer.invoke("fold:get-first-app-icon", appNames) as Promise<string | null>,
	listEpisodes: () => ipcRenderer.invoke("fold:list-episodes") as Promise<Record<string, unknown>[]>,
	listMemoryEntities: () =>
		ipcRenderer.invoke("fold:list-memory-entities") as Promise<Record<string, unknown>[]>,
	deactivateMemory: (id: string) =>
		ipcRenderer.invoke("fold:deactivate-memory", id) as Promise<{ ok: boolean }>,
	removeProfileConstraint: (text: string) =>
		ipcRenderer.invoke("fold:remove-profile-constraint", text) as Promise<{ ok: boolean }>,
	runMemoryConsolidation: () =>
		ipcRenderer.invoke("fold:run-memory-consolidation") as Promise<{ ok: boolean; dates: string[] }>,
	codexRemoteStatus: () =>
		ipcRenderer.invoke("fold:codex-remote-status") as Promise<{
			status: string;
			serverName?: string | null;
			environmentId?: string | null;
			error?: string;
		}>,
	codexRemoteEnable: () =>
		ipcRenderer.invoke("fold:codex-remote-enable") as Promise<{
			status: string;
			serverName?: string | null;
			environmentId?: string | null;
			error?: string;
		}>,
	codexRemoteDisable: () =>
		ipcRenderer.invoke("fold:codex-remote-disable") as Promise<{
			status: string;
			serverName?: string | null;
			environmentId?: string | null;
			error?: string;
		}>,
	codexRemotePairStart: () =>
		ipcRenderer.invoke("fold:codex-remote-pair-start") as Promise<{
			pairingCode?: string;
			manualPairingCode?: string;
			environmentId?: string;
			expiresAt?: number;
		}>,
	codexRemotePairPoll: (input: { pairingCode?: string; manualPairingCode?: string }) =>
		ipcRenderer.invoke("fold:codex-remote-pair-poll", input) as Promise<{ claimed: boolean }>,
	codexRemoteClients: () =>
		ipcRenderer.invoke("fold:codex-remote-clients") as Promise<{
			environmentId: string | null;
			clients: Array<{
				clientId: string;
				name?: string;
				lastConnectedAt?: number;
				platform?: string;
			}>;
			error?: string;
		}>,
	codexRemoteRevoke: (clientId: string) =>
		ipcRenderer.invoke("fold:codex-remote-revoke", clientId) as Promise<{
			ok: boolean;
			error?: string;
		}>,
	zhigengRemoteStatus: () =>
		ipcRenderer.invoke("fold:zhigeng-remote-status") as Promise<{
			configured: boolean;
			deviceId: string | null;
			state: "disabled" | "connecting" | "connected" | "error";
			error: string | null;
		}>,
	zhigengRemotePairStart: () =>
		ipcRenderer.invoke("fold:zhigeng-remote-pair-start") as Promise<{
			pairingId: string;
			code: string;
			qrPayload: string;
			expiresAt: string;
		}>,
	zhigengRemotePairPoll: (pairingId: string) =>
		ipcRenderer.invoke("fold:zhigeng-remote-pair-poll", pairingId) as Promise<{
			status: "pending" | "claimed" | "expired" | "canceled";
		}>,
	zhigengRemoteDevices: () =>
		ipcRenderer.invoke("fold:zhigeng-remote-devices") as Promise<{
			devices: Array<{
				id: string;
				kind: "mac" | "ios";
				name: string;
				lastSeenAt: string | null;
				revokedAt: string | null;
			}>;
		}>,
	zhigengRemoteRevoke: (deviceId: string) =>
		ipcRenderer.invoke("fold:zhigeng-remote-revoke", deviceId) as Promise<{ ok: true }>,
	getEpisode: (id: string) =>
		ipcRenderer.invoke("fold:get-episode", id) as Promise<Record<string, unknown> | null>,
	predictPickIntent: (intent: string) =>
		ipcRenderer.invoke("fold:predict-pick-intent", intent) as Promise<{ ok: boolean }>,
	predictInsertDraft: (text: string) =>
		ipcRenderer.invoke("fold:predict-insert-draft", text) as Promise<{
			ok: boolean;
			pasted: boolean;
			error?: string;
		}>,
	predictFeedback: (payload: {
		kind: "dismiss" | "reject" | "accept" | "edited" | "undo" | "ignore";
		surface?: string | null;
		intent?: string | null;
		draft?: string | null;
		anchor?: string | null;
	}) => ipcRenderer.invoke("fold:predict-feedback", payload) as Promise<{ ok: boolean }>,
	structureInsertDraft: (text: string, targetAppName?: string | null) =>
		ipcRenderer.invoke("fold:structure-insert-draft", text, targetAppName) as Promise<{
			ok: boolean;
			pasted: boolean;
			error?: string;
		}>,
	copyText: (text: string) =>
		ipcRenderer.invoke("fold:copy-text", text) as Promise<{ ok: boolean }>,
	predictStartVoice: () =>
		ipcRenderer.invoke("fold:predict-start-voice") as Promise<{ ok: boolean }>,
	predictRefineVoice: () =>
		ipcRenderer.invoke("fold:predict-refine-voice") as Promise<{ ok: boolean }>,
	profileImportOptions: () =>
		ipcRenderer.invoke("fold:profile-import-options") as Promise<
			Array<{
				id: string;
				label: string;
				hasOpenTab: boolean;
				tabUrl?: string;
				tabTitle?: string;
				defaultUrl: string;
				automationSupported: boolean;
			}>
		>,
	profileBuildPrompt: () => ipcRenderer.invoke("fold:profile-build-prompt") as Promise<string>,
	profileCopyPrompt: () =>
		ipcRenderer.invoke("fold:profile-copy-prompt") as Promise<{ prompt: string }>,
	profileGet: () => ipcRenderer.invoke("fold:profile-get") as Promise<Record<string, unknown> | null>,
	profileRunImport: (platformId: string, tabUrl?: string) =>
		ipcRenderer.invoke("fold:profile-run-import", platformId, tabUrl) as Promise<{
			ok: boolean;
			response?: string;
			error?: string;
			prompt: string;
		}>,
	profileSaveResponse: (responseText: string) =>
		ipcRenderer.invoke("fold:profile-save-response", responseText) as Promise<{
			ok: boolean;
			error?: string;
			profile?: Record<string, unknown>;
		}>,
	profileSaveSeed: (input: { role?: string; domains?: string[]; keywords?: string[] }) =>
		ipcRenderer.invoke("fold:profile-save-seed", input) as Promise<{ ok: boolean }>,
	onContextEvent(cb: (event: Record<string, unknown>) => void) {
		const handler = (_: unknown, event: Record<string, unknown>) => cb(event);
		ipcRenderer.on("fold:context-event", handler);
		return () => ipcRenderer.removeListener("fold:context-event", handler);
	},
	onAhaGuessChunk(cb: (payload: { runId: number; chunk: string }) => void) {
		const handler = (_: unknown, payload: { runId: number; chunk: string }) => cb(payload);
		ipcRenderer.on("fold:aha-guess-chunk", handler);
		return () => ipcRenderer.removeListener("fold:aha-guess-chunk", handler);
	},
	onAhaGuessDone(
		cb: (payload: {
			runId: number;
			suggestions?: Array<{
				label: string;
				intent: string;
				reason: string;
				confidence: number;
			}>;
			reply?: string;
			error?: string;
		}) => void,
	) {
		const handler = (
			_: unknown,
			payload: {
				runId: number;
				suggestions?: Array<{
					label: string;
					intent: string;
					reason: string;
					confidence: number;
				}>;
				reply?: string;
				error?: string;
			},
		) => cb(payload);
		ipcRenderer.on("fold:aha-guess-done", handler);
		return () => ipcRenderer.removeListener("fold:aha-guess-done", handler);
	},
	runConnectionAction: (action: string, context?: Record<string, unknown>) =>
		ipcRenderer.invoke("fold:connection-action", action, context) as Promise<{ ok: boolean }>,
	startConnectFlow: (connectionId: string, kind: "login" | "install") =>
		ipcRenderer.invoke("fold:connect-flow-start", connectionId, kind) as Promise<{
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
		}>,
	pollConnectFlow: (sessionId: string) =>
		ipcRenderer.invoke("fold:connect-flow-poll", sessionId) as Promise<{
			status: "pending" | "success" | "error";
			message?: string;
			error?: string;
		}>,
	activateConnectFlow: (sessionId: string) =>
		ipcRenderer.invoke("fold:connect-flow-activate", sessionId) as Promise<{
			ok: boolean;
			opened: boolean;
			url?: string;
		}>,
	cancelConnectFlow: (sessionId: string) =>
		ipcRenderer.invoke("fold:connect-flow-cancel", sessionId) as Promise<{ ok: boolean }>,
	openExternal: (url: string) => ipcRenderer.invoke("fold:open-external", url) as Promise<{ ok: boolean }>,
	openDataDir: () =>
		ipcRenderer.invoke("fold:open-data-dir") as Promise<{ ok: boolean; path?: string; error?: string }>,
	saveConfig: (config: Record<string, unknown>) =>
		ipcRenderer.invoke("fold:save-config", config) as Promise<{ ok: boolean }>,
	accountGetState: () =>
		ipcRenderer.invoke("fold:account-get-state") as Promise<{
			signedIn: boolean;
			email?: string;
			name?: string;
			userId?: string;
			planTier: "free" | "pro" | "ultra";
			voiceSecondsRemaining?: number;
			smartActionsRemaining?: number;
			voiceSecondsLimit?: number;
			smartActionsLimit?: number;
			syncedAt?: number;
		}>,
	accountRequestCode: (email: string) =>
		ipcRenderer.invoke("fold:account-request-code", email) as Promise<
			{ ok: true; mode: string } | { ok: false; error: string }
		>,
	accountVerifyCode: (input: { email: string; code: string }) =>
		ipcRenderer.invoke("fold:account-verify-code", input) as Promise<
			| { ok: true; state: Record<string, unknown> }
			| { ok: false; error: string }
		>,
	accountLogout: () =>
		ipcRenderer.invoke("fold:account-logout") as Promise<{
			signedIn: boolean;
			planTier: "free" | "pro" | "ultra";
		}>,
	accountSync: () =>
		ipcRenderer.invoke("fold:account-sync") as Promise<{
			signedIn: boolean;
			email?: string;
			name?: string;
			userId?: string;
			planTier: "free" | "pro" | "ultra";
			voiceSecondsRemaining?: number;
			smartActionsRemaining?: number;
			syncedAt?: number;
		}>,
	accountUpdateName: (name: string) =>
		ipcRenderer.invoke("fold:account-update-name", name) as Promise<
			| { ok: true; state: Record<string, unknown> }
			| { ok: false; error: string }
		>,
	accountCheckout: (input: { productId: string }) =>
		ipcRenderer.invoke("fold:account-checkout", input) as Promise<
			| {
					ok: true;
					mode: string;
					activated?: boolean;
					checkoutUrl?: string;
					state: Record<string, unknown>;
			  }
			| { ok: false; error: string }
		>,
	accountCancelPlan: () =>
		ipcRenderer.invoke("fold:account-cancel-plan") as Promise<
			| { ok: true; state: Record<string, unknown> }
			| { ok: false; error: string }
		>,
	accountDelete: () =>
		ipcRenderer.invoke("fold:account-delete") as Promise<
			| { ok: true; state: Record<string, unknown> }
			| { ok: false; error: string }
		>,
	setMousePassthrough: (ignore: boolean) => {
		ipcRenderer.send("fold:mouse-passthrough", ignore);
	},
	getDisplayWorkArea: (overlayPoint?: { x: number; y: number }) =>
		ipcRenderer.invoke("fold:get-display-work-area", overlayPoint) as Promise<{
			x: number;
			y: number;
			width: number;
			height: number;
		}>,
	getOverlayState: () => ipcRenderer.invoke("fold:get-overlay-state") as Promise<Record<string, unknown>>,
	dismiss: (opts?: { skipFeedback?: boolean; soft?: boolean }) =>
		ipcRenderer.invoke("fold:dismiss", opts) as Promise<void>,
	voiceEmpty: () =>
		ipcRenderer.invoke("fold:voice-empty") as Promise<{ ok: boolean; standby: boolean }>,
	toggleVoice: () => ipcRenderer.invoke("fold:toggle-voice") as Promise<void>,
	voiceError: (message: string) => ipcRenderer.invoke("fold:voice-error", message) as Promise<void>,
	openSettings: (section?: string) =>
		ipcRenderer.invoke("fold:open-settings", section) as Promise<void>,
	scanInputHabits: () => ipcRenderer.invoke("fold:scan-input-habits") as Promise<Record<string, unknown>>,
	listInstalledInputMethods: () =>
		ipcRenderer.invoke("fold:list-installed-input-methods") as Promise<Record<string, unknown>[]>,
	importInputHabits: () => ipcRenderer.invoke("fold:import-input-habits") as Promise<Record<string, unknown>>,
	getImportedInputHabits: () =>
		ipcRenderer.invoke("fold:get-imported-input-habits") as Promise<Record<string, unknown> | null>,
	exportInputHabitsRime: () =>
		ipcRenderer.invoke("fold:export-input-habits-rime") as Promise<
			Record<string, unknown> & { canceled?: boolean }
		>,
	quit: () => ipcRenderer.invoke("fold:quit") as Promise<void>,
	onHotkeyDown(cb: (session: VoiceSessionStart) => void) {
		const handler = (_: unknown, payload?: VoiceMode | VoiceSessionStart) =>
			cb(
				typeof payload === "string"
					? { mode: payload }
					: payload ?? { mode: "structure" },
			);
		ipcRenderer.on("fold:hotkey-down", handler);
		return () => ipcRenderer.removeListener("fold:hotkey-down", handler);
	},
	onVoiceWarm(cb: () => void) {
		const handler = () => cb();
		ipcRenderer.on("fold:voice-warm", handler);
		return () => ipcRenderer.removeListener("fold:voice-warm", handler);
	},
	onHotkeyUp(cb: (mode: VoiceMode) => void) {
		const handler = (_: unknown, mode?: VoiceMode) => cb(mode ?? "structure");
		ipcRenderer.on("fold:hotkey-up", handler);
		return () => ipcRenderer.removeListener("fold:hotkey-up", handler);
	},
	onHotkeyCancel(cb: () => void) {
		const handler = () => cb();
		ipcRenderer.on("fold:hotkey-cancel", handler);
		return () => ipcRenderer.removeListener("fold:hotkey-cancel", handler);
	},
	onHomeNavigate(cb: (section: string) => void) {
		const handler = (_: unknown, section: string) => cb(section);
		ipcRenderer.on("fold:home-navigate", handler);
		return () => ipcRenderer.removeListener("fold:home-navigate", handler);
	},
	probeAccessibility: () =>
		ipcRenderer.invoke("fold:probe-accessibility") as Promise<{
			available: boolean;
			appLabel: string;
			bundlePath?: string;
			error?: string;
		}>,
	openAccessibilitySettings: () =>
		ipcRenderer.invoke("fold:connection-action", "accessibility:open-settings") as Promise<{
			ok: boolean;
		}>,
	onboardingGetState: () => ipcRenderer.invoke("fold:onboarding-get-state") as Promise<{
		completedAt?: number;
		step?: string;
		profileImportedAt?: number;
		profileImportSkippedAt?: number;
	}>,
	openOnboarding: (opts?: { reset?: boolean }) =>
		ipcRenderer.invoke("fold:open-onboarding", opts) as Promise<{ ok: boolean }>,
	onboardingSetStep: (step: string) =>
		ipcRenderer.invoke("fold:onboarding-set-step", step) as Promise<Record<string, unknown>>,
	onboardingComplete: () =>
		ipcRenderer.invoke("fold:onboarding-complete") as Promise<{ ok: boolean }>,
	onboardingSkipProfile: () =>
		ipcRenderer.invoke("fold:onboarding-skip-profile") as Promise<Record<string, unknown>>,
	onboardingCompareDemo: (opts: { withProfile: boolean }) =>
		ipcRenderer.invoke("fold:onboarding-compare-demo", opts) as Promise<Record<string, unknown>>,
	onboardingStructureVoice: (transcript: string) =>
		ipcRenderer.invoke("fold:onboarding-structure-voice", transcript) as Promise<string>,
	onboardingSetVoiceApp: (app: string, windowTitle?: string) =>
		ipcRenderer.invoke("fold:onboarding-set-voice-app", app, windowTitle) as Promise<{ ok: boolean }>,
	onboardingAhaGuess: () =>
		ipcRenderer.invoke("fold:onboarding-aha-guess") as Promise<{ ok: boolean; runId?: number }>,
	onboardingSimulateClipboard: (lines: string[]) =>
		ipcRenderer.invoke("fold:onboarding-simulate-clipboard", lines) as Promise<{
			ok: boolean;
			previous?: Record<string, unknown>;
			current?: Record<string, unknown>;
		}>,
	onOnboardingHotkeyEvent(cb: (payload: {
		key: string;
		phase: "down" | "up";
		longPress?: boolean;
	}) => void) {
		const handler = (
			_: unknown,
			payload: { key: string; phase: "down" | "up"; longPress?: boolean },
		) => cb(payload);
		ipcRenderer.on("fold:onboarding-hotkey-event", handler);
		return () => ipcRenderer.removeListener("fold:onboarding-hotkey-event", handler);
	},
	onOnboardingVoiceEvent(cb: (payload: {
		phase: "listening" | "formatting" | "done" | "error";
		raw?: string;
		cleaned?: string;
		error?: string;
	}) => void) {
		const handler = (
			_: unknown,
			payload: {
				phase: "listening" | "formatting" | "done" | "error";
				raw?: string;
				cleaned?: string;
				error?: string;
			},
		) => cb(payload);
		ipcRenderer.on("fold:onboarding-voice-event", handler);
		return () => ipcRenderer.removeListener("fold:onboarding-voice-event", handler);
	},
});
