import { app, BrowserWindow, clipboard, dialog, ipcMain, Notification, powerSaveBlocker, screen, shell } from "electron";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { ContextEngine, extractClipboardContentQuery, isClipboardContentRecallIntent, isClipboardRecallIntent, resolveClipboardRecall, type ContextEvent } from "@fold/context";
import { captureScreenshot, createNangoConnectLink, openGogAuthInTerminal, openGwsAuthInTerminal, openClaudeLoginInTerminal, openCodexInstallInTerminal, openOfficeSetupInTerminal, openWorkBuddyApp, activateAgentConnectFlow, cancelConnectFlow, pollConnectFlow, resolveConnectTarget, startConnectFlow } from "@fold/connectors";
import { saveContextEvent, listContextEvents, saveVoiceInteraction, listMemoryEntities, saveProductEvent, deactivateMemory, removeProfileConstraint, searchContextEvents, loadProfileMemories, saveProfileMemories, type UserProfileData } from "@fold/memory";
import {
	ahaProactiveTierFor,
	decideAhaProactiveShow,
	hasPlannerApiKey,
	buildWeeklyRecap,
	markWeeklyRecapShown,
	recallHabitsFromUsage,
	resolveEntitlements,
	runTask,
	applyLocalHotwordHints,
	applyContextualAcronymFixes,
	shouldCleanSpeechLocally,
	shouldShowWeeklyRecap,
	startHabitRecallLoop,
	structureSpeechText,
	streamAhaGuess,
	matchUserActionVoice,
	type FoldStateEvent,
	type UserActionRequest,
	type UserActionResponse,
} from "@fold/runtime";
import {
	clearPredictTargetApp,
	getPredictTargetApp,
	getPredictPreviewForHome,
	recordPredictCardFeedback,
	resolveAhaGuess,
	streamAhaGuessForHome,
	refreshPredictCacheEnriched,
	resolveReplyDraftsForInstruction,
	resolveReplyVoiceCard,
	resolvePredictDraftsForIntent,
	resolveReplyPredictions,
	setPredictTargetApp,
} from "./predict-enrich.js";
import * as macosInput from "@fold/macos-input";
import {
	captureTextInsertionTarget,
	clearTextInsertionTarget,
	insertTextToFrontApp,
	undoTextInsertion,
} from "./insert-text.js";
import { canUseUndoReceipt, createUndoReceipt, type UndoReceipt } from "./undo-receipt.js";
import { buildVoiceOverlayContext } from "./voice-overlay-context.js";
import { focusApp, focusUrl } from "./focus-context.js";
import { getAppIconDataUrl, getFirstAppIconDataUrl, resolveAppBundlePath } from "./app-icon.js";
import {
	applyConfigToEnv,
	consumeSmartActionTrial,
	hasRealAsr,
	loadConfig,
	resolveSmartActionAccess,
	saveConfig,
	type FoldConfig,
} from "./config.js";
import {
	cancelPlan,
	checkoutPlan,
	deleteAccount,
	getAccountState,
	logoutAccount,
	requestAccountCode,
	syncAccountEntitlements,
	updateAccountName,
	verifyAccountCode,
} from "./account-sync.js";
import { loadAccountSecret } from "./secure-store.js";
import { buildHomeSnapshot } from "./home-snapshot.js";
import {
	cursorPointInOverlay,
	getDisplayWorkAreaForOverlayPoint,
	getDisplayWorkAreaInOverlay,
	getOverlaySpanBounds,
	getPrimaryDisplayWorkAreaInOverlay,
	overlayPointToScreen,
	positionOverlayForActiveContext,
	positionOverlayForAnchoredScreen,
	positionOverlayForIdle,
} from "./overlay-display.js";
import { openAccessibilitySettings, probeAccessibility, ensureAccessibilityPermission } from "./permissions.js";
import { buildEpisodeDetail, listEpisodesForHome } from "./episode-detail.js";
import {
	buildProfilePrompt,
	copyProfilePrompt,
	executeProfileImport,
	getStoredProfile,
	listProfileImportOptions,
	saveProfileFromResponse,
} from "./profile-import.js";
import {
	getActiveHotkeyBindings,
	getHotkeyStatus,
	hotkeyIdsForSave,
	reloadHotkeysFromConfig,
	startHoldHotkey,
} from "./hotkey.js";
import {
	AGENT_PRESETS,
	CANCEL_PRESETS,
	presetOptionsForRenderer,
	TRIGGER_PRESETS,
	type HotkeyAction,
} from "./hotkey-presets.js";
import { createTray } from "./tray.js";
import { migrateLegacyDataDir, resolveDataDir } from "./data-dir.js";
import {
	startMemoryConsolidationLoop,
	stopMemoryConsolidationLoop,
	triggerMemoryConsolidationNow,
} from "./memory-consolidation.js";
import {
	disableCodexRemoteControl,
	enableCodexRemoteControl,
	getCodexRemoteStatus,
	listCodexRemoteClients,
	pollCodexRemotePairing,
	revokeCodexRemoteClient,
	shutdownCodexAppServer,
	startCodexRemotePairing,
} from "./codex-remote-control.js";
import {
	configureRemoteRelay,
	forwardRemoteState,
	getRemoteRelayStatus,
	listRemoteDevices,
	pollRemotePairing,
	revokeRemoteDevice,
	startRemotePairing,
	startRemoteRelay,
	stopRemoteRelay,
} from "./remote-relay-client.js";
import { PRODUCT_NAME } from "./brand.js";
import {
	FileInteractionStore,
	InteractionBroker,
	toInteractionView,
	type PendingInteractionRecord,
} from "./interaction-broker.js";
import { createZhigengAppIcon } from "./tray-icon.js";
import {
	appendLocalWhisperAudio,
	cancelLocalWhisperSession,
	finishLocalWhisperSession,
	getDefaultLocalModelPath,
	hasLocalWhisperModel,
	resolveLocalModelPath,
	startLocalWhisperSession,
} from "./local-whisper.js";
import {
	downloadVoicePack,
	getVoiceSetupStatus,
	shouldUseSmartVoice,
} from "./voice-setup.js";
import { scanInputHabits, listInstalledInputMethods } from "./input-habit-scanner/index.js";
import { resolveSpeechHotwords } from "@fold/runtime";
import { exportInputHabitsToRime } from "./input-habit-scanner/export-rime.js";
import {
	importInputHabitsOneClick,
	loadImportedInputHabits,
} from "./input-habit-scanner/import.js";
import {
	completeOnboarding,
	getOnboardingState,
	isOnboardingComplete,
	markProfileImported,
	markProfileImportSkipped,
	resetOnboardingForTest,
	setOnboardingStep,
} from "./onboarding.js";
import {
	getOnboardingAhaInput,
	runOnboardingCompareDemo,
	runOnboardingStructureVoice,
} from "./onboarding-compare.js";

// dev 下 turbo/vite 先退出会踩断 stdout 管道，console 写入抛 EPIPE → 主进程崩溃弹窗。
// 日志写不出去可以忍，app 不能死。
for (const stream of [process.stdout, process.stderr]) {
	stream.on("error", (err: NodeJS.ErrnoException) => {
		if (err.code !== "EPIPE") throw err;
	});
}

migrateLegacyDataDir();
applyConfigToEnv();

const contextEngine = new ContextEngine({
	ignoreApps: ["Electron", "Fold", "fold", "知更", "Zhigeng", "zhigeng"],
	getIdleSeconds: () => {
		try {
			return macosInput.idleSeconds();
		} catch {
			return -1;
		}
	},
	frontAppWatcher: {
		start: (cb) => {
			try {
				return macosInput.startFrontAppWatch((change) => {
					cb({ appName: change.appName, appPath: change.appPath });
				});
			} catch {
				return { ok: false, error: "native-watch-unavailable" };
			}
		},
		stop: () => {
			try {
				macosInput.stopFrontAppWatch();
			} catch {
				/* ignore */
			}
		},
	},
	onEvent: (event) => {
		try {
			saveContextEvent(event);
		} catch {
			// Raw retention should never break foreground agent execution.
		}
		settingsWindow?.webContents.send("fold:context-event", event);
		if (predictRefreshTimer) clearTimeout(predictRefreshTimer);
		predictRefreshTimer = setTimeout(() => {
			void refreshPredictCacheEnriched(contextEngine.getLiveContext());
		}, 4000);
	},
});

function hydrateContextFromDb() {
	try {
		const rows = listContextEvents(400);
		if (!rows.length) return;
		const events: ContextEvent[] = rows.map((row) => ({
			id: row.id,
			type: row.type as ContextEvent["type"],
			source: row.source as ContextEvent["source"],
			timestamp: row.timestamp,
			data: {
				appName: typeof row.data.appName === "string" ? row.data.appName : undefined,
				windowTitle:
					typeof row.data.windowTitle === "string" ? row.data.windowTitle : undefined,
				appPath: typeof row.data.appPath === "string" ? row.data.appPath : undefined,
				filePath: typeof row.data.filePath === "string" ? row.data.filePath : undefined,
				url: typeof row.data.url === "string" ? row.data.url : undefined,
				text: typeof row.data.text === "string" ? row.data.text : undefined,
				origin:
					row.data.origin === "fold" || row.data.origin === "user"
						? row.data.origin
						: undefined,
			},
		}));
		contextEngine.hydrate(events);
	} catch {
		// DB hydration should never block startup.
	}
}

let overlayWindow: BrowserWindow | null = null;
let settingsWindow: BrowserWindow | null = null;
let onboardingWindow: BrowserWindow | null = null;
let onboardingStep: string | undefined;
let pendingHomeSection: string | null = null;
let isRecording = false;
type VoiceOutcome = "structure" | "reply" | "agent" | "interaction";
let voiceOutcome: VoiceOutcome = "structure";
let interactionBroker: InteractionBroker | null = null;
let voiceCanUseDirectStructure = false;
/** 代回首轮：松开右 ⌘ 不结束，短按结束 */
let replyLatched = false;
/** 确认卡上按住修改：松开结束 */
let replyRefineHold = false;
let voiceTargetApp: string | null = null;
/** 代回：Overlay 升起前截下的聊天窗，避免松手时截到主屏微信/知更自己 */
let voiceReplyScreenshotPath: string | null = null;
/** 语音待机：保留目标 App，超时或 Esc 退出 */
let voiceStandbyUntil: number | null = null;
let voiceStandbyTimer: ReturnType<typeof setTimeout> | null = null;
let voiceStandbyMode: "structure" | "reply" | null = null;
let voiceStandbyPlacement: { left: number; top: number } | null = null;
/** 进待机时的 ctx.activeApp 快照；唤起时同源比对，判断焦点是否已切到别的真实 App */
let voiceStandbyActiveApp: string | null = null;
let lastIntent = "";
let lastReplyTranscript = "";
/** 代回卡片上做过语音 refine 后再插入 → 记 edited 而非 accept */
let replyWasRefined = false;
let stopHotkey: (() => void) | null = null;
let refreshTrayMenu: (() => void) | null = null;
let stopHabitRecall: (() => void) | null = null;
let activeTaskPowerBlockerId: number | null = null;
let activeTaskPowerAssertionCount = 0;
let activeTaskAbortController: AbortController | null = null;
let devE2eIntentStarted = false;

function startTaskPowerAssertion(): void {
	activeTaskPowerAssertionCount += 1;
	if (activeTaskPowerBlockerId !== null && powerSaveBlocker.isStarted(activeTaskPowerBlockerId)) return;
	activeTaskPowerBlockerId = powerSaveBlocker.start("prevent-app-suspension");
}

function stopTaskPowerAssertion(): void {
	activeTaskPowerAssertionCount = Math.max(0, activeTaskPowerAssertionCount - 1);
	if (activeTaskPowerAssertionCount > 0) return;
	if (activeTaskPowerBlockerId === null) return;
	if (powerSaveBlocker.isStarted(activeTaskPowerBlockerId)) {
		powerSaveBlocker.stop(activeTaskPowerBlockerId);
	}
	activeTaskPowerBlockerId = null;
}

function snapshotContextEvents() {
	return contextEngine.getLiveContext().events.slice(-24).map((e) => ({
		type: e.type,
		source: e.source,
		data: e.data as Record<string, unknown>,
	}));
}

/** 语音纠错热词：profile 专名 + 已导入输入法词库（未导入则只用 profile）。 */
function getSpeechHotwords(limit = 12): string[] {
	const profile: UserProfileData | null = loadProfileMemories();
	const imported = loadImportedInputHabits();
	return resolveSpeechHotwords({
		profile,
		lexicon: imported?.entries ?? [],
		limit,
	});
}

/** Pro / 试用：下发 ASR 引擎热词；Free 无试用返回空（仅本地轻纠）。 */
function getAsrEngineHotwords(): string[] {
	const config = loadConfig();
	const entitlements = resolveEntitlements(config.planTier);
	const smartAccess = resolveSmartActionAccess(config);
	if (!entitlements.hotwords && !smartAccess.allowed) return [];
	return getSpeechHotwords(48);
}

function recordVoiceInteraction(
	kind: "structure" | "reply" | "agent",
	transcript: string,
	outcome?: string,
	status: "success" | "failed" = "success",
) {
	const ctx = contextEngine.getLiveContext();
	try {
		saveVoiceInteraction({
			kind,
			transcript,
			outcome,
			status,
			appName: ctx.activeApp,
			windowTitle: ctx.activeWindow,
			contextEvents: snapshotContextEvents(),
		});
		if (status === "success") recallHabitsFromUsage();
	} catch {
		// Habit learning should never block voice flows.
	}
}
let predictRefreshTimer: ReturnType<typeof setTimeout> | null = null;
let ahaGuessRunId = 0;
const appIconCache = new Map<string, string>();
let lastOverlayState: FoldStateEvent = { status: "idle" };
let lastUndoReceipt: UndoReceipt | null = null;

function emitState(state: FoldStateEvent) {
	lastOverlayState = { ...lastOverlayState, ...state };
	forwardRemoteState(state);
	if (!overlayWindow || overlayWindow.isDestroyed()) {
		createOverlayWindow();
		return;
	}
	const { webContents } = overlayWindow;
	if (webContents.isDestroyed()) return;
	try {
		webContents.send("fold:state", state);
	} catch {
		// Overlay reload/HMR can dispose the render frame mid-task.
	}
	// 引导窗也要听状态：first-reply 步靠「已插入回复」解锁继续
	if (onboardingWindow && !onboardingWindow.isDestroyed()) {
		try {
			onboardingWindow.webContents.send("fold:state", state);
		} catch {
			/* ignore */
		}
	}
}

function syncDockVisibility() {
	if (process.platform !== "darwin") return;
	const devMode = Boolean(process.env.VITE_DEV_SERVER_URL);
	const settingsOpen = Boolean(settingsWindow && !settingsWindow.isDestroyed());
	const onboardingOpen = Boolean(onboardingWindow && !onboardingWindow.isDestroyed());
	if (devMode || settingsOpen || onboardingOpen) {
		app.dock?.setIcon(createZhigengAppIcon());
		app.dock?.show();
		return;
	}
	app.dock?.hide();
}

function createOverlayWindow() {
	if (overlayWindow && !overlayWindow.isDestroyed()) return;

	const { workArea } = screen.getPrimaryDisplay();

	overlayWindow = new BrowserWindow({
		width: workArea.width,
		height: workArea.height,
		x: workArea.x,
		y: workArea.y,
		frame: false,
		transparent: true,
		backgroundColor: "#00000000",
		alwaysOnTop: true,
		focusable: false,
		skipTaskbar: true,
		hasShadow: false,
		resizable: false,
		movable: false,
		fullscreenable: false,
		type: "panel",
		webPreferences: {
			preload: join(__dirname, "preload.js"),
			contextIsolation: true,
			nodeIntegration: false,
			// overlay 窗 focusable:false，从不获用户手势；否则音效被 autoplay 策略拦掉
			autoplayPolicy: "no-user-gesture-required",
		},
	});

	overlayWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
	overlayWindow.setAlwaysOnTop(true, "floating");
	overlayWindow.showInactive();
	// CSS pointer-events-none is not enough — pass clicks through to apps below.
	overlayWindow.setIgnoreMouseEvents(true, { forward: true });

	if (process.env.VITE_DEV_SERVER_URL) {
		overlayWindow.loadURL(process.env.VITE_DEV_SERVER_URL);
	} else {
		overlayWindow.loadFile(join(__dirname, "../dist/index.html"));
	}

	overlayWindow.on("closed", () => {
		overlayWindow = null;
	});

	overlayWindow.webContents.once("did-finish-load", () => {
		const widgetDisplayBounds = positionOverlayForIdle(overlayWindow);
		console.log(
			`[fold:widget] primary bounds=${widgetDisplayBounds.x},${widgetDisplayBounds.y} ${widgetDisplayBounds.width}x${widgetDisplayBounds.height}`,
		);
		emitState({
			...lastOverlayState,
			voiceTabPlacement: null,
			widgetDisplayBounds,
		});
	});
}

function openSettingsWindow(section?: string) {
	if (section) pendingHomeSection = section;

	if (settingsWindow) {
		settingsWindow.focus();
		if (section) {
			settingsWindow.webContents.send("fold:home-navigate", section);
		}
		syncDockVisibility();
		return;
	}

	settingsWindow = new BrowserWindow({
		width: 1120,
		height: 780,
		title: PRODUCT_NAME,
		resizable: true,
		minWidth: 880,
		minHeight: 640,
		show: false,
		...(process.platform === "darwin"
			? {
					frame: false,
					transparent: true,
					hasShadow: true,
					backgroundColor: "#00000000",
					// hiddenInset 仍会保留标题栏条并显示窗口标题；hidden 才彻底去掉顶栏
					titleBarStyle: "hidden" as const,
					trafficLightPosition: { x: 16, y: 16 },
				}
			: {}),
		webPreferences: {
			preload: join(__dirname, "preload.js"),
			contextIsolation: true,
			nodeIntegration: false,
		},
	});

	const settingsUrl = process.env.VITE_DEV_SERVER_URL
		? `${process.env.VITE_DEV_SERVER_URL}settings.html`
		: pathToFileURL(join(__dirname, "../dist/settings.html")).href;

	settingsWindow.loadURL(settingsUrl);
	settingsWindow.once("ready-to-show", () => {
		settingsWindow?.show();
		syncDockVisibility();
	});
	settingsWindow.webContents.once("did-finish-load", () => {
		if (pendingHomeSection) {
			settingsWindow?.webContents.send("fold:home-navigate", pendingHomeSection);
			pendingHomeSection = null;
		}
	});
	settingsWindow.on("closed", () => {
		settingsWindow = null;
		syncDockVisibility();
	});
}

function isOnboardingHotkeyTestStep(): boolean {
	return Boolean(
		onboardingWindow && !onboardingWindow.isDestroyed() && onboardingStep === "hotkey",
	);
}

function isOnboardingVoiceLiveStep(): boolean {
	return Boolean(
		onboardingWindow && !onboardingWindow.isDestroyed() && onboardingStep === "voice-live",
	);
}

function isOnboardingReplyDemoStep(): boolean {
	return Boolean(
		onboardingWindow && !onboardingWindow.isDestroyed() && onboardingStep === "reply-demo",
	);
}

/** 语音输入引导页：整理结果写回引导窗，不插入前台 App */
let onboardingVoiceApp: string | null = null;
let onboardingVoiceWindowTitle: string | null = null;

function raiseOverlayForVoiceUi() {
	if (!overlayWindow || overlayWindow.isDestroyed()) return;
	overlayWindow.setAlwaysOnTop(true, "screen-saver");
	overlayWindow.showInactive();
	overlayWindow.moveTop();
}

function restoreOverlayZOrder() {
	if (!overlayWindow || overlayWindow.isDestroyed()) return;
	overlayWindow.setAlwaysOnTop(true, "floating");
}

function sendOnboardingVoiceEvent(payload: {
	phase: "listening" | "formatting" | "done" | "error";
	raw?: string;
	cleaned?: string;
	error?: string;
}) {
	if (onboardingWindow && !onboardingWindow.isDestroyed()) {
		onboardingWindow.webContents.send("fold:onboarding-voice-event", payload);
	}
}

function openOnboardingWindow() {
	if (onboardingWindow && !onboardingWindow.isDestroyed()) {
		onboardingStep = getOnboardingState().step;
		onboardingWindow.focus();
		syncDockVisibility();
		return;
	}

	onboardingWindow = new BrowserWindow({
		width: 1120,
		height: 780,
		title: PRODUCT_NAME,
		resizable: true,
		minWidth: 880,
		minHeight: 640,
		show: false,
		...(process.platform === "darwin"
			? {
					frame: false,
					transparent: true,
					hasShadow: true,
					backgroundColor: "#00000000",
					titleBarStyle: "hidden" as const,
					trafficLightPosition: { x: 16, y: 16 },
				}
			: {}),
		webPreferences: {
			preload: join(__dirname, "preload.js"),
			contextIsolation: true,
			nodeIntegration: false,
		},
	});

	const onboardingUrl = process.env.VITE_DEV_SERVER_URL
		? `${process.env.VITE_DEV_SERVER_URL}onboarding.html`
		: pathToFileURL(join(__dirname, "../dist/onboarding.html")).href;

	onboardingWindow.loadURL(onboardingUrl);
	onboardingStep = getOnboardingState().step;
	onboardingWindow.once("ready-to-show", () => {
		onboardingWindow?.show();
		syncDockVisibility();
	});
	onboardingWindow.on("closed", () => {
		onboardingWindow = null;
		onboardingStep = undefined;
		syncDockVisibility();
	});
}

function finishOnboardingFlow() {
	completeOnboarding();
	onboardingStep = undefined;
	if (onboardingWindow && !onboardingWindow.isDestroyed()) {
		onboardingWindow.close();
		onboardingWindow = null;
	}
	openSettingsWindow("overview");
}

async function runUserAction(optionId: string, context?: Record<string, unknown>) {
	switch (optionId) {
		case "gmail:terminal-auth":
			if (context?.backend === "gws") openGwsAuthInTerminal();
			else openGogAuthInTerminal();
			break;
		case "gmail:open-browser":
			await shell.openExternal("https://mail.google.com/mail/u/0/#inbox");
			break;
		case "nango:connect": {
			const link = await createNangoConnectLink();
			await shell.openExternal(link);
			break;
		}
		case "nango:dashboard":
			await shell.openExternal("https://app.nango.dev");
			break;
		case "screen:open-settings":
			await shell.openExternal(
				"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
			);
			break;
		case "accessibility:request":
			void ensureAccessibilityPermission();
			break;
		case "accessibility:open-settings":
			await openAccessibilitySettings();
			break;
		case "cdp:open-chrome-help":
			await shell.openExternal(
				"https://playwright.dev/mcp/configuration/browser-extension",
			);
			break;
		case "cdp:open-remote-debugging":
			await shell.openExternal("chrome://inspect/#remote-debugging");
			break;
		case "cdp:install-bridge":
			await shell.openExternal(
				"https://chromewebstore.google.com/detail/playwright-mcp-bridge/mmlmfjhmonkocbjadbfplnigmagldckm",
			);
			break;
		case "codex:install-terminal":
			openCodexInstallInTerminal();
			break;
		case "office:install-terminal":
		case "office:login-terminal": {
			const channel = typeof context?.channel === "string" ? context.channel : "";
			const kind = optionId === "office:login-terminal" ? "login" : "install";
			const result = openOfficeSetupInTerminal(channel, kind);
			if (!result.opened && result.url) await shell.openExternal(result.url);
			break;
		}
		case "claude:login-terminal":
			openClaudeLoginInTerminal();
			break;
		case "workbuddy:open-app":
			openWorkBuddyApp();
			break;
		default:
			break;
	}
}

function ensureInteractionBroker(): InteractionBroker {
	if (!interactionBroker) {
		interactionBroker = new InteractionBroker(
			new FileInteractionStore(join(app.getPath("userData"), "interaction-state.json")),
		);
	}
	return interactionBroker;
}

function interactionState(record: PendingInteractionRecord): FoldStateEvent {
	const interaction = toInteractionView(record);
	return {
		status: "ask",
		transcript: record.intent,
		askTitle: interaction.title,
		askMessage: interaction.message,
		askHint: interaction.hint,
		askOptions: interaction.options.map(({ id, label }) => ({ id, label })),
		interaction,
		voiceMode: interaction.listening ? "interaction" : null,
	};
}

function emitCurrentInteraction(): PendingInteractionRecord | null {
	const record = ensureInteractionBroker().current();
	if (record) emitState(interactionState(record));
	return record;
}

function requestUserAction(req: UserActionRequest): Promise<string> {
	const broker = ensureInteractionBroker();
	const response = broker.request(req, lastIntent);
	emitCurrentInteraction();
	return response;
}

/** Auto-complete the active auth HITL when probe says ready (no user click). */
function resolveUserAction(optionId: string): void {
	const broker = ensureInteractionBroker();
	const active = broker.current();
	if (!active) return;
	const resolution = broker.respond({
		requestId: active.id,
		optionId,
		modality: "terminal",
	});
	if (!resolution) return;
	emitState({
		status: "working",
		interaction: null,
		voiceMode: null,
		askTitle: null,
		askMessage: null,
		askHint: null,
		askOptions: undefined,
	});
}

async function handleInteractionResponse(response: UserActionResponse): Promise<void> {
	const broker = ensureInteractionBroker();
	const record = broker.current();
	if (!record) {
		if (lastIntent && (response.optionId || response.text)) {
			await executeTask(`${lastIntent} ${response.optionId ?? response.text}`);
		}
		return;
	}
	if (response.requestId && response.requestId !== record.id) return;

	if (response.optionId === "cancel") {
		broker.cancel("用户取消了授权");
		emitState({
			status: "idle",
			error: null,
			interaction: null,
			voiceMode: null,
			askTitle: null,
			askMessage: null,
			askHint: null,
			askOptions: undefined,
			result: "已取消",
		});
		return;
	}

	if (!response.optionId && response.text?.trim() && !record.request.input.acceptFreeform) {
		broker.updatePresentation({
			listening: false,
			draft: response.text.trim(),
			validationMessage: "没匹配到选项，再说一次或直接点按钮。",
		});
		emitCurrentInteraction();
		return;
	}

	if (response.optionId) {
		await runUserAction(response.optionId, record.runContext);
	}
	const resolution = broker.respond(response);
	if (!resolution) return;
	emitState({
		status: "working",
		interaction: null,
		voiceMode: null,
		askTitle: null,
		askMessage: null,
		askHint: null,
		askOptions: undefined,
	});

	// A restored interaction has no live Promise. Re-enter through the product task path
	// with the durable answer instead of silently losing the paused run.
	// Dev-only E2E HITL cards set skipExecuteOnRestore so clicking allow doesn't
	// re-run a fake intent as a real agent task (was the "部分完成" trap).
	const skipExecute =
		resolution.record.runContext?.skipExecuteOnRestore === true;
	if (!resolution.wasLive && resolution.record.intent && !skipExecute) {
		const answer = response.optionId ?? response.text?.trim() ?? "";
		await executeTask(`${resolution.record.intent}\n已恢复的用户回答：${answer}`);
	}
}

async function handleInteractionVoice(transcript: string): Promise<void> {
	const broker = ensureInteractionBroker();
	const record = broker.current();
	if (!record) return;
	const text = transcript.trim();
	const matched = matchUserActionVoice(text, record.request.options);
	if (matched) {
		await handleInteractionResponse({
			requestId: record.id,
			optionId: matched.id,
			text,
			modality: "voice",
		});
		return;
	}
	await handleInteractionResponse({
		requestId: record.id,
		text,
		modality: "voice",
	});
}

async function executeTask(intent: string) {
	if (!intent.trim()) {
		emitIdleState();
		return;
	}
	lastIntent = intent.trim();
	const smartAccess = resolveSmartActionAccess();
	if (!smartAccess.allowed && !hasPlannerApiKey()) {
		emitState({
			status: "error",
			transcript: lastIntent,
			error: "智能体验次数已用完。可升级版本，或在设置中启用 BYOK 使用自己的模型。",
		});
		return;
	}
	if (!smartAccess.allowed) {
		emitState({
			status: "error",
			transcript: lastIntent,
			error: "智能体验次数已用完。启用 BYOK 后可继续使用你配置的 Planner。",
		});
		return;
	}
	emitState({ status: "understanding", ...clearPredictState() });
	activeTaskAbortController?.abort();
	const abortController = new AbortController();
	activeTaskAbortController = abortController;
	startTaskPowerAssertion();
	try {
		await runTask(lastIntent, emitState, {
			getLiveContext: () => contextEngine.getLiveContext(),
			requestUserAction,
			resolveUserAction,
			runUserAction,
			signal: abortController.signal,
			captureTaskMomentScreenshot: async (taskId, appName) => {
				try {
					const dir = join(app.getPath("home"), ".fold", "moments");
					const outPath = join(dir, `${taskId}.png`);
					let screenRect: ReturnType<typeof macosInput.mouseScreenBounds> | undefined;
					try {
						screenRect = macosInput.mouseScreenBounds();
					} catch {
						/* 多屏定位失败时退化为默认主屏截图 */
					}
					// 优先截该应用窗口本身：排除菜单栏/Dock/其它窗口的 OCR 噪音；
					// 窗口截不到（AX 无窗口、Space 隔离等）时退化为鼠标锚点全屏。
					const trimmedApp = appName?.trim();
					if (trimmedApp && !/^(electron|fold)$/i.test(trimmedApp)) {
						const byApp = await captureScreenshot({
							target: "app",
							appName: trimmedApp,
							outPath,
							screenRect,
						}).catch(() => null);
						if (byApp?.windowId != null) return byApp.path;
					}
					const shot = await captureScreenshot({ target: "screen", outPath, screenRect });
					return shot.path;
				} catch {
					return null;
				}
			},
			ocrImageFile: async (path, region) => {
				try {
					const r = macosInput.ocrImageFile(path, region);
					return r.ok ? { text: r.text } : null;
				} catch {
					return null;
				}
			},
		});
		if (smartAccess.usesTrial && hasPlannerApiKey()) consumeSmartActionTrial();
	} catch (err) {
		emitState({ status: "error", error: (err as Error).message });
	} finally {
		if (activeTaskAbortController === abortController) {
			activeTaskAbortController = null;
		}
		stopTaskPowerAssertion();
		void refreshPredictCacheEnriched(contextEngine.getLiveContext());
	}
}

function getCursorInOverlay(): { x: number; y: number } {
	return cursorPointInOverlay(overlayWindow);
}

// ---- 自动 Aha 主动建议（后台监测 → 系统通知 → 点通知进卡） ----
let ahaProactiveTimer: ReturnType<typeof setInterval> | null = null;
let ahaProactiveLastShownAt = 0;
let ahaProactiveShownToday = 0;
let ahaProactiveShownDay = "";
let ahaProactiveRunning = false;

function startAhaProactiveLoop(): void {
	if (ahaProactiveTimer) return;
	// 每 60s 检查一次档位与冷却；档位内具体节奏由 cooldownMs 控制。
	ahaProactiveTimer = setInterval(() => {
		void runAhaProactiveCheck();
	}, 60_000);
}

async function runAhaProactiveCheck(): Promise<void> {
	if (ahaProactiveRunning) return;
	const frequency = loadConfig().ahaProactiveFrequency ?? "off";
	const tier = ahaProactiveTierFor(frequency);
	if (!tier) return;

	const today = new Date().toDateString();
	if (today !== ahaProactiveShownDay) {
		ahaProactiveShownDay = today;
		ahaProactiveShownToday = 0;
	}
	const msSinceLastShow = ahaProactiveLastShownAt
		? Date.now() - ahaProactiveLastShownAt
		: Infinity;

	ahaProactiveRunning = true;
	try {
		const ctx = contextEngine.getLiveContext();
		const result = await streamAhaGuessForHome(
			ctx,
			undefined,
			() => {},
			() => false,
		);
		const decision = decideAhaProactiveShow({
			enabled: true,
			confidence: {
				score: result.confidenceScore ?? 0,
				level: result.confidenceLevel ?? "low",
				reasons: [],
			},
			suggestions: result.suggestions,
			msSinceLastShow,
			shownToday: ahaProactiveShownToday,
			maxPerDay: tier.maxPerDay,
			cooldownMs: tier.cooldownMs,
			confidenceThreshold: tier.confidenceThreshold,
			suggestionThreshold: tier.suggestionThreshold,
		});
		if (!decision.show) return;

		const top = result.suggestions[0]!;
		const notification = new Notification({
			title: "知更 猜你想做",
			body: `${top.label} · 点「看看」展开`,
			silent: true,
		});
		notification.on("click", () => {
			showAhaProactiveCard(result);
		});
		notification.show();
		ahaProactiveLastShownAt = Date.now();
		ahaProactiveShownToday += 1;
	} catch {
		// 后台监测失败静默，不打扰用户
	} finally {
		ahaProactiveRunning = false;
	}
}

function showAhaProactiveCard(result: Awaited<ReturnType<typeof streamAhaGuessForHome>>): void {
	createOverlayWindow();
	const ctx = contextEngine.getLiveContext();
	emitState({
		status: "predict",
		...clearPredictState(),
		predictMode: "full",
		predictPhase: "pick",
		predictSurface: "task",
		predictAnchor: ctx.activeWindow ?? ctx.activeApp ?? null,
		predictSuggestions: result.suggestions,
		predictCursor: getCursorInOverlay(),
		contextAppName: ctx.activeApp,
		contextAppPath: ctx.activeAppPath,
		contextWindowTitle: ctx.activeWindow,
		ahaProactiveReason: "自动建议",
	});
}

function clearPredictState(): Partial<FoldStateEvent> {
	return {
		predictMode: null,
		predictPhase: null,
		predictSurface: null,
		predictAnchor: null,
		predictSuggestions: undefined,
		predictDrafts: undefined,
		predictSelectedIntent: null,
		predictMemoryRefs: undefined,
		predictDraftsLoading: false,
		predictCursor: null,
		contextPageUrl: null,
		contextPageLabel: null,
		predictRefining: false,
		structureDraftOpen: false,
	};
}

function voiceStandbySeconds(): number {
	const n = loadConfig().voiceStandbySeconds;
	if (typeof n === "number" && Number.isFinite(n)) return Math.max(0, Math.min(60, Math.round(n)));
	// Mac 默认关：全局热键重进成本低，待机复用易插错窗；代码/文档留给 iOS。要开：config.voiceStandbySeconds=8
	return 0;
}

function isVoiceStandbyActive(): boolean {
	return voiceStandbyUntil != null && Date.now() < voiceStandbyUntil;
}

function clearVoiceStandbyTimer() {
	if (voiceStandbyTimer) {
		clearTimeout(voiceStandbyTimer);
		voiceStandbyTimer = null;
	}
}

function exitVoiceStandby(extra: Partial<FoldStateEvent> = {}) {
	clearVoiceStandbyTimer();
	voiceStandbyUntil = null;
	voiceStandbyMode = null;
	voiceStandbyPlacement = null;
	voiceStandbyActiveApp = null;
	voiceTargetApp = null;
	voiceReplyScreenshotPath = null;
	clearPredictTargetApp();
	clearTextInsertionTarget();
	emitIdleState({ voiceStandbyUntil: null, voiceHint: null, ...extra });
}

/** 转写/代回一轮后进入待机：保留 target，不把 overlay 缩回主屏 orb */
function enterVoiceStandby(
	mode: "structure" | "reply",
	opts?: {
		placement?: { left: number; top: number } | null;
		appName?: string | null;
		appPath?: string | null;
		windowTitle?: string | null;
		keepPredictCard?: boolean;
	},
) {
	const secs = voiceStandbySeconds();
	if (secs <= 0 || !voiceTargetApp) {
		if (!opts?.keepPredictCard) emitIdleState({ voiceMode: null, voiceStandbyUntil: null });
		return;
	}
	clearVoiceStandbyTimer();
	voiceStandbyMode = mode;
	voiceStandbyUntil = Date.now() + secs * 1000;
	voiceStandbyActiveApp = contextEngine.getLiveContext().activeApp ?? null;
	voiceStandbyPlacement =
		opts?.placement ?? lastOverlayState.voiceTabPlacement ?? voiceStandbyPlacement;
	if (voiceTargetApp) setPredictTargetApp(voiceTargetApp);

	if (opts?.keepPredictCard) {
		emitState({
			...lastOverlayState,
			voiceStandbyUntil,
			voiceHint: `待机 ${secs}s · 可继续说`,
			contextAppName: opts.appName ?? lastOverlayState.contextAppName ?? voiceTargetApp,
			contextAppPath: opts.appPath ?? lastOverlayState.contextAppPath,
			contextWindowTitle: opts.windowTitle ?? lastOverlayState.contextWindowTitle,
			voiceTabPlacement: voiceStandbyPlacement,
		});
	} else {
		restoreOverlayZOrder();
		emitState({
			status: "idle",
			undoAvailable: lastOverlayState.undoAvailable ?? false,
			verificationChecks: lastOverlayState.verificationChecks,
			voiceMode: mode,
			voiceHint: `待机中 · ${secs}s 内可再按快捷键`,
			voiceStandbyUntil,
			voiceTabPlacement: voiceStandbyPlacement,
			widgetDisplayBounds: null,
			...clearPredictState(),
			contextAppName: opts?.appName ?? lastOverlayState.contextAppName ?? voiceTargetApp,
			contextAppPath: opts?.appPath ?? lastOverlayState.contextAppPath ?? null,
			contextWindowTitle: opts?.windowTitle ?? lastOverlayState.contextWindowTitle ?? null,
		});
	}

	voiceStandbyTimer = setTimeout(() => {
		if (isVoiceStandbyActive() || voiceStandbyUntil != null) {
			exitVoiceStandby({ voiceMode: null });
		}
	}, secs * 1000 + 50);
}

function emitIdleState(extra: Partial<FoldStateEvent> = {}) {
	restoreOverlayZOrder();
	const widgetDisplayBounds = positionOverlayForIdle(overlayWindow);
	emitState({
		status: "idle",
		undoAvailable: false,
		verificationChecks: undefined,
		voiceTabPlacement: null,
		voiceHint: null,
		voiceStandbyUntil: null,
		widgetDisplayBounds,
		...clearPredictState(),
		...extra,
	});
}

function emitPredictResult(result: Awaited<ReturnType<typeof resolveReplyPredictions>>) {
	emitState({
		status: "predict",
		...clearPredictState(),
		predictMode: result.mode,
		predictPhase: result.phase,
		predictSurface: result.surface,
		predictAnchor: result.anchor,
		predictSuggestions: result.suggestions,
		predictDrafts: result.drafts,
		predictMemoryRefs: result.memoryRefs,
		predictCursor: getCursorInOverlay(),
	});
}

function showReplyPredictions() {
	createOverlayWindow();
	const ctx = contextEngine.getLiveContext();
	const targetApp = ctx.activeApp;
	void (async () => {
		let precapture: string | null = null;
		try {
			const shot = await captureScreenshot({ target: "frontmost" });
			precapture = shot.path;
		} catch {
			// enrichForReply 会按 app 名再试
		}
		await contextEngine.refreshActiveApp();
		const fresh = contextEngine.getLiveContext();
		const app = fresh.activeApp ?? targetApp;
		const voiceTabPlacement = await positionOverlayForActiveContext(overlayWindow, app);
		emitState({
			status: "predict",
			...clearPredictState(),
			predictMode: "fast",
			predictPhase: "pick",
			predictSurface: "reply",
			predictAnchor: "正在读取对话…",
			predictSuggestions: [],
			predictCursor: getCursorInOverlay(),
			voiceTabPlacement,
			contextAppName: app,
			contextAppPath: fresh.activeAppPath,
		});
		const result = await resolveReplyPredictions(fresh, app, precapture);
		const placement = await positionOverlayForActiveContext(overlayWindow, app);
		emitState({
			status: "predict",
			...clearPredictState(),
			predictMode: result.mode,
			predictPhase: result.phase,
			predictSurface: result.surface,
			predictAnchor: result.anchor,
			predictSuggestions: result.suggestions,
			predictDrafts: result.drafts,
			predictMemoryRefs: result.memoryRefs,
			predictCursor: getCursorInOverlay(),
			voiceTabPlacement: placement,
			contextAppName: app,
			contextAppPath: fresh.activeAppPath,
			contextWindowTitle: result.anchor,
		});
	})();
}

async function structureVoiceTranscript(
	transcript: string,
	opts: { directStructured?: boolean } = {},
) {
	const text = transcript.trim();
	if (!text) {
		emitIdleState();
		return;
	}
	const ctx = contextEngine.getLiveContext();
	const smartAccess = resolveSmartActionAccess();
	const cleanupLevel = loadConfig().speechCleanupLevel ?? "smart";
	// 付费/试用：短命令也上云做专名增强；免费：本地快路径 + 轻量热词
	const preferCloudStructure = smartAccess.allowed && cleanupLevel === "smart";
	const useLocal = !preferCloudStructure && shouldCleanSpeechLocally(text);

	if (isOnboardingVoiceLiveStep()) {
		const app = onboardingVoiceApp ?? "微信";
		// 引导窗（Electron 自身）在前台：锚定到活跃屏底中，overlay 只覆盖该屏避免多屏 span 飘移
		const voiceTabPlacement = await positionOverlayForAnchoredScreen(
			overlayWindow,
			voiceTargetApp,
		);
		raiseOverlayForVoiceUi();
		sendOnboardingVoiceEvent({ phase: "formatting", raw: text });
		emitState({
			status: "formatting",
			transcript: text,
			voiceMode: "structure",
			voiceTabPlacement,
			voiceHint: null,
			...clearPredictState(),
			contextAppName: app,
			contextWindowTitle: onboardingVoiceWindowTitle,
		});
		try {
			const structured = opts.directStructured
				? { headline: text, detail: "" }
				: await structureSpeechText(text, {
						app,
						windowTitle: onboardingVoiceWindowTitle ?? "Onboarding",
						profileKeywords: getSpeechHotwords(),
						allowCloud: smartAccess.allowed,
						preferQuality: true,
						cleanupLevel,
					});
			const body = [structured.headline, structured.detail]
				.map((part) => part.trim())
				.filter(Boolean)
				.filter((part, index, arr) => index === 0 || part !== arr[0])
				.join("\n\n");
			const output = body || text;
			sendOnboardingVoiceEvent({ phase: "done", raw: text, cleaned: output });
			emitIdleState({ voiceMode: null });
		} catch (err) {
			sendOnboardingVoiceEvent({
				phase: "error",
				raw: text,
				error: (err as Error).message,
			});
			emitState({ status: "error", error: (err as Error).message, transcript: text, voiceHint: null });
		}
		return;
	}

	const voiceTabPlacement = await positionOverlayForActiveContext(
		overlayWindow,
		voiceTargetApp ?? ctx.activeApp,
	);
	emitState({
		status: "formatting",
		transcript: text,
		voiceMode: "structure",
		voiceTabPlacement,
		...clearPredictState(),
		...buildVoiceOverlayContext(ctx),
	});
	try {
		if (isClipboardRecallIntent(text)) {
			let recall = resolveClipboardRecall(text, ctx.recentClipboards ?? []);
			if (!recall.ok && isClipboardContentRecallIntent(text)) {
				const hits = searchContextEvents(extractClipboardContentQuery(text), 5);
				const clipHit = hits.find((h) => h.row.type === "clipboard.changed");
				if (clipHit && typeof clipHit.row.data.text === "string") {
					const when = new Date(clipHit.row.timestamp).toLocaleString("zh-CN", {
						month: "numeric",
						day: "numeric",
						hour: "2-digit",
						minute: "2-digit",
					});
					const where = (clipHit.row.data.appName as string) ?? "未知应用";
					recall = {
						ok: true,
						summary: `找到匹配的复制（${when} · ${where}）：${clipHit.row.data.text.slice(0, 240)}`,
						text: clipHit.row.data.text,
						entry: {
							id: clipHit.row.id,
							text: clipHit.row.data.text,
							timestamp: clipHit.row.timestamp,
							appName: (clipHit.row.data.appName as string) ?? null,
							windowTitle: (clipHit.row.data.windowTitle as string) ?? null,
							appPath: (clipHit.row.data.appPath as string) ?? null,
						},
					};
				}
			}
			recordVoiceInteraction("structure", text, recall.summary);
			emitState({
				status: "done",
				transcript: text,
				voiceMode: "structure",
				result: recall.ok ? "已找到复制记录" : "未找到复制记录",
				resultDetail: recall.summary,
			});
			setTimeout(() => {
				if (lastOverlayState.status === "done" && lastOverlayState.voiceMode === "structure") {
					enterVoiceStandby("structure", { placement: lastOverlayState.voiceTabPlacement });
				}
			}, 2500);
			return;
		}

		const structured = opts.directStructured
			? {
					headline: preferCloudStructure
						? applyContextualAcronymFixes(
								applyLocalHotwordHints(text, getSpeechHotwords()),
								getSpeechHotwords(),
							)
						: applyLocalHotwordHints(text, getSpeechHotwords()),
					detail: "",
				}
			: (
					await Promise.all([
						structureSpeechText(text, {
							app: ctx.activeApp,
							windowTitle: ctx.activeWindow,
							profileKeywords: getSpeechHotwords(),
							allowCloud: preferCloudStructure,
							preferQuality: preferCloudStructure,
							cleanupLevel,
							onCloudSuccess: smartAccess.usesTrial
								? () => {
										consumeSmartActionTrial();
									}
								: undefined,
						}),
						useLocal ? new Promise((r) => setTimeout(r, 240)) : Promise.resolve(),
					])
				)[0];
		const body = [structured.headline, structured.detail]
			.map((part) => part.trim())
			.filter(Boolean)
			.filter((part, index, arr) => index === 0 || part !== arr[0])
			.join("\n\n");
		const output = body || text;
		if (opts.directStructured && smartAccess.usesTrial) {
			consumeSmartActionTrial();
		}
		const targetApp = voiceTargetApp ?? ctx.activeApp;
		const autoInsert = loadConfig().structureAutoInsert !== false;
		recordVoiceInteraction("structure", text, output);

		if (autoInsert) {
			contextEngine.suppressClipboardCapture(5000);
			const insertResult = await insertTextToFrontApp(output, targetApp);
			console.log(
				`[fold:voice-insert] targetApp=${targetApp ?? "—"} ok=${insertResult.ok} pasted=${insertResult.pasted}`,
			);
			if (insertResult.pasted) {
				lastUndoReceipt = createUndoReceipt(targetApp);
				clearTextInsertionTarget();
				emitState({
					status: "done",
					transcript: text,
					voiceMode: "structure",
					result: "已输入",
					resultDetail: output,
					voiceTabPlacement,
					structureDraftOpen: false,
					undoAvailable: true,
					verificationChecks: [
						{
							rule: "text.inserted",
							passed: insertResult.verified !== false,
							message: insertResult.verified === false ? "目标输入框未确认变化" : "已写入目标输入框",
						},
					],
				});
				setTimeout(() => {
					if (lastOverlayState.status === "done" && lastOverlayState.voiceMode === "structure") {
						enterVoiceStandby("structure", {
							placement: voiceTabPlacement,
							appName: targetApp,
						});
					}
				}, 2500);
			} else {
				emitState({
					status: "done",
					transcript: text,
					voiceMode: "structure",
					result: "转写完成，点击插入",
					resultDetail: output,
					voiceTabPlacement,
					structureDraftOpen: true,
					...buildVoiceOverlayContext(ctx),
				});
			}
		} else {
			emitState({
				status: "done",
				transcript: text,
				voiceMode: "structure",
				result: "转写完成",
				resultDetail: output,
				voiceTabPlacement,
				structureDraftOpen: true,
				...buildVoiceOverlayContext(ctx),
			});
		}
	} catch (err) {
		emitState({ status: "error", error: (err as Error).message, transcript: text });
		recordVoiceInteraction("structure", text, (err as Error).message, "failed");
	}
}

async function replyVoiceTranscript(transcript: string) {
	const text = transcript.trim();
	if (!text) {
		emitIdleState();
		return;
	}
	lastReplyTranscript = text;

	const onboardingReply = isOnboardingReplyDemoStep();
	await contextEngine.refreshActiveApp();
	const ctx = contextEngine.getLiveContext();
	const contextAppName = onboardingReply
		? onboardingVoiceApp ?? "飞书"
		: voiceTargetApp ?? ctx.activeApp;
	const contextAppPath = onboardingReply ? null : ctx.activeAppPath;
	const contextWindowTitle = onboardingReply
		? onboardingVoiceWindowTitle
		: ctx.activeWindow;

	createOverlayWindow();
	const voiceTabPlacement = onboardingReply
		? await positionOverlayForAnchoredScreen(overlayWindow, null)
		: await positionOverlayForActiveContext(overlayWindow, contextAppName);
	if (onboardingReply) raiseOverlayForVoiceUi();
	emitState({
		status: "predict",
		voiceMode: null,
		voiceTabPlacement,
		...clearPredictState(),
		predictMode: "full",
		predictPhase: "result",
		predictSurface: "reply",
		predictAnchor: "正在生成回复…",
		predictSelectedIntent: text,
		predictDraftsLoading: true,
		predictRefining: false,
		predictCursor: getCursorInOverlay(),
		contextAppName,
		contextAppPath,
		contextWindowTitle,
	});

	try {
		const card = await resolveReplyVoiceCard(
			ctx,
			text,
			contextAppName,
			voiceReplyScreenshotPath,
		);
		const sceneTitle =
			onboardingReply
				? contextWindowTitle ?? contextAppName ?? "智能代回"
				: card.sceneTitle;
		recordVoiceInteraction("reply", text, card.drafts[0]?.text);
		emitState({
			status: "predict",
			voiceMode: null,
			voiceTabPlacement,
			predictMode: "full",
			predictPhase: "result",
			predictSurface: "reply",
			predictAnchor: sceneTitle,
			predictSelectedIntent: text,
			predictDrafts: card.drafts,
			predictMemoryRefs: card.memoryRefs,
			predictDraftsLoading: false,
			predictRefining: false,
			predictCursor: getCursorInOverlay(),
			contextAppName: onboardingReply ? contextAppName : card.appName ?? contextAppName,
			contextAppPath: onboardingReply ? null : card.appPath ?? contextAppPath,
			contextWindowTitle: sceneTitle,
		});
		if (!onboardingReply) {
			// 保留 voiceTargetApp，进入待机（卡片仍开着）
			enterVoiceStandby("reply", {
				placement: voiceTabPlacement,
				appName: onboardingReply ? contextAppName : card.appName ?? contextAppName,
				appPath: onboardingReply ? null : card.appPath ?? contextAppPath,
				windowTitle: sceneTitle,
				keepPredictCard: true,
			});
		}
	} catch (err) {
		recordVoiceInteraction("reply", text, (err as Error).message, "failed");
		emitState({
			status: "error",
			error: (err as Error).message,
			transcript: text,
			...clearPredictState(),
		});
	}
}

const IPC_HANDLE_CHANNELS = [
	"fold:get-config",
	"fold:save-config",
	"fold:get-mock-asr",
	"fold:get-asr-runtime",
	"fold:get-voice-setup",
	"fold:download-voice-pack",
	"fold:local-asr-start",
	"fold:local-asr-finish",
	"fold:local-asr-cancel",
	"fold:get-home-snapshot",
	"fold:get-live-context",
	"fold:get-app-icon",
	"fold:list-episodes",
	"fold:get-episode",
	"fold:connection-action",
	"fold:connect-flow-start",
	"fold:connect-flow-poll",
	"fold:connect-flow-cancel",
	"fold:open-external",
	"fold:run-task",
	"fold:structure-voice",
	"fold:reply-voice",
	"fold:retry-task",
	"fold:undo-last-insert",
	"fold:ask-response",
	"fold:interaction-voice",
	"fold:toggle-interaction-voice",
	"fold:dismiss",
	"fold:voice-empty",
	"fold:toggle-voice",
	"fold:voice-error",
	"fold:open-settings",
	"fold:quit",
	"fold:probe-accessibility",
	"fold:onboarding-get-state",
	"fold:open-onboarding",
	"fold:onboarding-set-step",
	"fold:onboarding-complete",
	"fold:onboarding-skip-profile",
	"fold:onboarding-compare-demo",
	"fold:onboarding-structure-voice",
	"fold:onboarding-set-voice-app",
	"fold:onboarding-aha-guess",
	"fold:onboarding-simulate-clipboard",
	"fold:account-get-state",
	"fold:account-request-code",
	"fold:account-verify-code",
	"fold:account-logout",
	"fold:account-sync",
	"fold:account-update-name",
	"fold:account-checkout",
	"fold:account-cancel-plan",
	"fold:account-delete",
	"fold:get-hotkey-settings",
	"fold:set-hotkey-binding",
	"fold:profile-save-seed",
] as const;

function buildHotkeySettingsSnapshot() {
	const bindings = getActiveHotkeyBindings();
	return {
		bindings: {
			trigger: { id: bindings.trigger.id, label: bindings.trigger.label },
			agent: {
				id: bindings.agent.id,
				label: bindings.agent.label,
				keys: bindings.agent.keys,
			},
			cancel: {
				id: bindings.cancel.id,
				label: bindings.cancel.label,
				keys: bindings.cancel.keys,
			},
		},
		options: presetOptionsForRenderer(),
		status: getHotkeyStatus(),
	};
}

function isValidHotkeyPreset(action: HotkeyAction, presetId: string): boolean {
	if (action === "trigger") return TRIGGER_PRESETS.some((preset) => preset.id === presetId);
	if (action === "agent") return AGENT_PRESETS.some((preset) => preset.id === presetId);
	return CANCEL_PRESETS.some((preset) => preset.id === presetId);
}

function resolveAsrRuntime() {
	const config = loadConfig();
	const requested = config.asrProvider ?? "auto";
	const modelPath =
		config.localWhisperModelPath ?? getDefaultLocalModelPath();
	const resolvedModelPath = resolveLocalModelPath(modelPath);
	const hasLocal = hasLocalWhisperModel(modelPath);
	const hasCloud = hasRealAsr(config);
	const tier = resolveEntitlements(config.planTier);
	const smartAccess = resolveSmartActionAccess(config);

	if (requested === "local-whisper" || requested === "local-funasr") {
		return { provider: "local-whisper" as const, modelPath: resolvedModelPath, ready: hasLocal };
	}
	if (requested === "dashscope") {
		return {
			provider: hasCloud ? ("dashscope" as const) : ("mock" as const),
			ready: hasCloud,
		};
	}
	// 会员或仍有智能体验次数：自动走云端；额度耗尽后回退到本地。
	if (shouldUseSmartVoice(requested, tier.cloudAsr, smartAccess.allowed)) {
		return {
			provider: hasCloud ? ("dashscope" as const) : ("dashscope" as const),
			ready: hasCloud,
		};
	}
	// 免费版：仅本地语音包
	if (hasLocal) {
		return { provider: "local-whisper" as const, modelPath: resolvedModelPath, ready: true };
	}
	return { provider: "local-whisper" as const, modelPath: resolvedModelPath, ready: false };
}

function registerIpc() {
	for (const channel of IPC_HANDLE_CHANNELS) {
		ipcMain.removeHandler(channel);
	}

	ipcMain.handle("fold:get-config", () => loadConfig());

	ipcMain.handle("fold:save-config", (_e, config: FoldConfig) => {
		saveConfig(config);
		applyConfigToEnv(config);
		return { ok: true };
	});

	ipcMain.handle("fold:account-get-state", () => getAccountState());
	ipcMain.handle("fold:account-request-code", (_e, email: string) => requestAccountCode(email));
	ipcMain.handle("fold:account-verify-code", (_e, input: { email: string; code: string }) =>
		verifyAccountCode(input),
	);
	ipcMain.handle("fold:account-logout", () => logoutAccount());
	ipcMain.handle("fold:account-sync", () => syncAccountEntitlements());
	ipcMain.handle("fold:account-update-name", (_e, name: string) => updateAccountName(name));
	ipcMain.handle(
		"fold:account-checkout",
		(_e, input: { productId: string }) => checkoutPlan(input),
	);
	ipcMain.handle("fold:account-cancel-plan", () => cancelPlan());
	ipcMain.handle("fold:account-delete", () => deleteAccount());

	ipcMain.handle("fold:get-hotkey-settings", () => buildHotkeySettingsSnapshot());

	ipcMain.handle(
		"fold:set-hotkey-binding",
		(_e, action: HotkeyAction, presetId: string) => {
			if (!isValidHotkeyPreset(action, presetId)) {
				return { ok: false as const, reason: "invalid" as const };
			}
			const config = loadConfig();
			const nextHotkeys = { ...config.hotkeys, [action]: presetId };
			const result = reloadHotkeysFromConfig(nextHotkeys);
			if (!result.ok) {
				return { ok: false as const, reason: result.reason };
			}
			saveConfig({ ...config, hotkeys: hotkeyIdsForSave() });
			refreshTrayMenu?.();
			return {
				ok: true as const,
				settings: buildHotkeySettingsSnapshot(),
			};
		},
	);

	ipcMain.handle("fold:get-mock-asr", () => resolveAsrRuntime().provider === "mock");

	ipcMain.handle("fold:get-voice-setup", () => getVoiceSetupStatus());

	ipcMain.handle("fold:download-voice-pack", () => downloadVoicePack());

	ipcMain.handle("fold:get-asr-runtime", () => {
		const runtime = resolveAsrRuntime();
		const authToken = loadAccountSecret() ?? loadConfig().hubApiKey?.trim() ?? undefined;
		const hotWords = getAsrEngineHotwords();
		return { ...runtime, authToken, hotWords };
	});

	ipcMain.handle("fold:local-asr-start", () => {
		startLocalWhisperSession();
		return { ok: true };
	});

	ipcMain.removeAllListeners("fold:local-asr-audio");
	ipcMain.on("fold:local-asr-audio", (_event, chunk: ArrayBuffer | Uint8Array) => {
		appendLocalWhisperAudio(chunk);
	});

	ipcMain.handle("fold:local-asr-finish", async () => {
		const config = loadConfig();
		return finishLocalWhisperSession(
			resolveLocalModelPath(config.localWhisperModelPath),
		);
	});

	ipcMain.handle("fold:local-asr-cancel", () => {
		cancelLocalWhisperSession();
		return { ok: true };
	});

	ipcMain.handle("fold:get-home-snapshot", () =>
		buildHomeSnapshot(() => contextEngine.getLiveContext()),
	);

	ipcMain.handle("fold:get-predict-preview", () =>
		getPredictPreviewForHome(contextEngine.getLiveContext()),
	);

	ipcMain.handle("fold:start-aha-guess", async () => {
		const runId = ++ahaGuessRunId;
		const win = settingsWindow;
		if (!win || win.isDestroyed()) return { ok: false };

		const send = (channel: string, payload: Record<string, unknown>) => {
			if (runId !== ahaGuessRunId || win.isDestroyed()) return;
			win.webContents.send(channel, { runId, ...payload });
		};

		void (async () => {
			try {
				const result = await streamAhaGuessForHome(
					contextEngine.getLiveContext(),
					undefined,
					(chunk) => send("fold:aha-guess-chunk", { chunk }),
					() => runId !== ahaGuessRunId,
				);
				if (runId !== ahaGuessRunId) return;
				send("fold:aha-guess-done", {
					suggestions: result.suggestions,
					reply: result.reply,
					confidenceLevel: result.confidenceLevel,
					confidenceScore: result.confidenceScore,
				});
			} catch {
				if (runId !== ahaGuessRunId) return;
				send("fold:aha-guess-done", {
					error: "暂时没看清楚，稍后再试。",
					suggestions: [],
				});
			}
		})();

		return { ok: true, runId };
	});

	ipcMain.handle("fold:cancel-aha-guess", () => {
		ahaGuessRunId += 1;
		return { ok: true };
	});

	// 轻量版实时上下文（不带连接探测），供 Home 窗口高频刷新
	ipcMain.handle("fold:get-live-context", () => {
		const ctx = contextEngine.getLiveContext();
		return {
			activeApp: ctx.activeApp,
			activeWindow: ctx.activeWindow,
			activeAppPath: ctx.activeAppPath,
			recentUrls: ctx.recentUrls.slice(0, 10).map((u) => ({
				url: u.url,
				title: u.title,
			})),
			recentFiles: ctx.recentFiles.slice(0, 10).map((f) => ({
				path: f.path,
				name: f.name,
			})),
			clipboardPreview: ctx.clipboard?.text
				? ctx.clipboard.text.slice(0, 80) + (ctx.clipboard.text.length > 80 ? "…" : "")
				: null,
			recentClipboards: ctx.recentClipboards.slice(0, 50).map((item) => ({
				id: item.id,
				timestamp: item.timestamp,
				text: item.text,
				appName: item.appName,
				windowTitle: item.windowTitle,
				appPath: item.appPath,
			})),
			focusDwells: (ctx.focusDwells ?? []).slice(0, 6).map((d) => ({
				app: d.app,
				windowTitle: d.windowTitle,
				dwellMs: d.dwellMs,
			})),
			events: ctx.events.slice(-80),
		};
	});

	ipcMain.handle("fold:restore-clipboard", async (_e, payload: { id?: string; text?: string }) => {
		const id = typeof payload?.id === "string" ? payload.id : "";
		const directText = typeof payload?.text === "string" ? payload.text.trim() : "";
		const ctx = contextEngine.getLiveContext();
		const entry =
			(id ? ctx.recentClipboards.find((item) => item.id === id) : null) ??
			(directText
				? {
						id: "direct",
						text: directText,
						timestamp: Date.now(),
						appName: null,
						windowTitle: null,
						appPath: null,
					}
				: null);
		if (!entry?.text) return { ok: false };
		const { clipboard } = await import("electron");
		contextEngine.suppressClipboardCapture(2500);
		clipboard.writeText(entry.text);
		return { ok: true };
	});

	ipcMain.handle(
		"fold:focus-context",
		async (_e, target: { kind: "app"; appName: string } | { kind: "url"; url: string }) => {
			if (target?.kind === "app") return focusApp(target.appName);
			if (target?.kind === "url") return focusUrl(target.url);
			return { ok: false };
		},
	);

	ipcMain.handle("fold:get-app-icon", (_e, appPath: string, appName?: string) => {
		const cacheKey = appPath?.endsWith(".app") ? appPath : `name:${appName ?? appPath}`;
		if (!cacheKey || cacheKey === "name:") return null;
		const cached = appIconCache.get(cacheKey);
		if (cached) return cached;
		const dataUrl = getAppIconDataUrl(appPath, appName);
		// ponytail: 只缓存成功结果——图标一旦拿到不会变，但失败可能是瞬时的（sips 临时文件竞争等），
		// 缓存 null 会让某个 app 的图标在整个进程生命周期内永久丢失，只能重启桌面端才能恢复。
		if (dataUrl) appIconCache.set(cacheKey, dataUrl);
		return dataUrl;
	});

	ipcMain.handle("fold:get-first-app-icon", (_e, appNames: string[]) => {
		const key = `names:${appNames.join("|")}`;
		if (!appNames.length) return null;
		const cached = appIconCache.get(key);
		if (cached) return cached;
		const dataUrl = getFirstAppIconDataUrl(appNames);
		if (dataUrl) appIconCache.set(key, dataUrl);
		return dataUrl;
	});

	ipcMain.handle("fold:list-episodes", () => listEpisodesForHome(50));

	ipcMain.handle("fold:list-memory-entities", () => listMemoryEntities());
	ipcMain.handle("fold:deactivate-memory", (_e, id: string) => {
		const ok = deactivateMemory(String(id ?? ""));
		return { ok };
	});
	ipcMain.handle("fold:remove-profile-constraint", (_e, text: string) => {
		const ok = removeProfileConstraint(String(text ?? ""));
		return { ok };
	});

	ipcMain.handle("fold:run-memory-consolidation", async () => triggerMemoryConsolidationNow());

	ipcMain.handle("fold:codex-remote-status", () => getCodexRemoteStatus());
	ipcMain.handle("fold:codex-remote-enable", () => enableCodexRemoteControl());
	ipcMain.handle("fold:codex-remote-disable", () => disableCodexRemoteControl());
	ipcMain.handle("fold:codex-remote-pair-start", () => startCodexRemotePairing());
	ipcMain.handle(
		"fold:codex-remote-pair-poll",
		(_e, input: { pairingCode?: string; manualPairingCode?: string }) =>
			pollCodexRemotePairing(input),
	);
	ipcMain.handle("fold:codex-remote-clients", () => listCodexRemoteClients());
	ipcMain.handle("fold:codex-remote-revoke", (_e, clientId: string) =>
		revokeCodexRemoteClient(clientId),
	);
	ipcMain.handle("fold:zhigeng-remote-status", () => getRemoteRelayStatus());
	ipcMain.handle("fold:zhigeng-remote-pair-start", () => startRemotePairing());
	ipcMain.handle("fold:zhigeng-remote-pair-poll", (_e, pairingId: string) =>
		pollRemotePairing(pairingId),
	);
	ipcMain.handle("fold:zhigeng-remote-devices", () => listRemoteDevices());
	ipcMain.handle("fold:zhigeng-remote-revoke", (_e, deviceId: string) =>
		revokeRemoteDevice(deviceId),
	);

	ipcMain.handle("fold:get-episode", (_e, id: string) => {
		if (!id) return null;
		return buildEpisodeDetail(id);
	});

	ipcMain.handle("fold:profile-import-options", () => listProfileImportOptions());
	ipcMain.handle("fold:profile-build-prompt", () => buildProfilePrompt());
	ipcMain.handle("fold:profile-copy-prompt", () => ({ prompt: copyProfilePrompt() }));
	ipcMain.handle("fold:profile-get", () => getStoredProfile());
	ipcMain.handle("fold:profile-run-import", (_e, platformId: string, tabUrl?: string) =>
		executeProfileImport(platformId, tabUrl),
	);
	ipcMain.handle("fold:profile-save-response", (_e, responseText: string) => {
		const result = saveProfileFromResponse(responseText);
		if (result.ok) markProfileImported();
		return result;
	});
	ipcMain.handle(
		"fold:profile-save-seed",
		(
			_e,
			input: { role?: string; domains?: string[]; keywords?: string[] },
		) => {
			const existing = loadProfileMemories() ?? {};
			const split = (raw: string[] | undefined) =>
				(raw ?? [])
					.flatMap((s) => s.split(/[,，、;；\n]/))
					.map((s) => s.trim())
					.filter((s) => s.length >= 2);
			const domains = [...new Set([...(existing.domains ?? []), ...split(input.domains)])];
			const preferredTools = [
				...new Set([...(existing.preferredTools ?? []), ...split(input.keywords)]),
			];
			const role = input.role?.trim() || existing.role;
			saveProfileMemories(
				{
					...existing,
					...(role ? { role } : {}),
					...(domains.length ? { domains } : {}),
					...(preferredTools.length ? { preferredTools } : {}),
					updatedAt: Date.now(),
				},
				"onboarding-know-you",
			);
			return { ok: true as const };
		},
	);

	ipcMain.handle("fold:probe-accessibility", () => probeAccessibility(false));
	ipcMain.handle("fold:onboarding-get-state", () => getOnboardingState());
	ipcMain.handle("fold:open-onboarding", (_e, opts?: { reset?: boolean }) => {
		if (opts?.reset) resetOnboardingForTest();
		openOnboardingWindow();
		return { ok: true };
	});
	ipcMain.handle("fold:onboarding-set-step", (_e, step: string) => {
		if (typeof step === "string" && step.trim()) {
			const next = step.trim();
			onboardingStep = next;
			setOnboardingStep(next);
			if (next === "first-reply") {
				// 真实代回：清掉 demo 伪 App，用前台上下文
				onboardingVoiceApp = null;
				onboardingVoiceWindowTitle = null;
			}
			try {
				saveProductEvent({ name: "onboarding_step_enter", props: { step: next } });
			} catch {
				/* ignore */
			}
		}
		return getOnboardingState();
	});
	ipcMain.handle("fold:onboarding-complete", () => {
		try {
			saveProductEvent({ name: "onboarding_step_complete", props: { step: "summary" } });
		} catch {
			/* ignore */
		}
		finishOnboardingFlow();
		return { ok: true };
	});
	ipcMain.handle("fold:onboarding-skip-profile", () => {
		markProfileImportSkipped();
		return getOnboardingState();
	});
	ipcMain.handle("fold:onboarding-compare-demo", (_e, opts: { withProfile?: boolean }) =>
		runOnboardingCompareDemo({ withProfile: Boolean(opts?.withProfile) }),
	);
	ipcMain.handle("fold:onboarding-structure-voice", (_e, transcript: string) =>
		runOnboardingStructureVoice(String(transcript ?? "")),
	);
	ipcMain.handle("fold:onboarding-set-voice-app", (_e, app: string, windowTitle?: string) => {
		onboardingVoiceApp = typeof app === "string" && app.trim() ? app.trim() : null;
		onboardingVoiceWindowTitle =
			typeof windowTitle === "string" && windowTitle.trim() ? windowTitle.trim() : null;
		return { ok: true };
	});
	ipcMain.handle("fold:onboarding-aha-guess", async () => {
		const runId = ++ahaGuessRunId;
		const win = onboardingWindow;
		if (!win || win.isDestroyed()) return { ok: false };

		const send = (channel: string, payload: Record<string, unknown>) => {
			if (runId !== ahaGuessRunId || win.isDestroyed()) return;
			win.webContents.send(channel, { runId, ...payload });
		};

		void (async () => {
			try {
				const input = getOnboardingAhaInput();
				const reply = await streamAhaGuess(input, {
					allowCloud: resolveSmartActionAccess().allowed,
					onChunk: (chunk: string) => send("fold:aha-guess-chunk", { chunk }),
					isCancelled: () => runId !== ahaGuessRunId,
				});
				if (runId !== ahaGuessRunId) return;
				send("fold:aha-guess-done", {
					reply,
					suggestions: [
						{
							label: "回复进度",
							intent: "回复同事关于预算评审的时间安排",
							reason: "当前在飞书预算文档",
							confidence: 0.72,
						},
					],
					confidenceLevel: "medium",
					confidenceScore: 0.72,
				});
			} catch {
				if (runId !== ahaGuessRunId) return;
				send("fold:aha-guess-done", {
					error: "暂时没看清楚，稍后再试。",
					suggestions: [],
				});
			}
		})();

		return { ok: true, runId };
	});
	ipcMain.handle("fold:onboarding-simulate-clipboard", (_e, lines: string[]) => {
		const texts = Array.isArray(lines) ? lines.filter((t) => typeof t === "string" && t.trim()) : [];
		if (texts.length < 2) return { ok: false };
		const now = Date.now();
		contextEngine.pushEvent({
			type: "clipboard.changed",
			source: "clipboard",
			timestamp: now - 2000,
			data: { text: texts[0]!.trim(), origin: "user", appName: "Safari" },
		});
		contextEngine.pushEvent({
			type: "clipboard.changed",
			source: "clipboard",
			timestamp: now,
			data: { text: texts[1]!.trim(), origin: "user", appName: "备忘录" },
		});
		const ctx = contextEngine.getLiveContext();
		return {
			ok: true,
			previous: ctx.recentClipboards[1] ?? null,
			current: ctx.recentClipboards[0] ?? null,
		};
	});

	ipcMain.handle("fold:predict-pick-intent", async (_e, intent: string) => {
		if (!intent?.trim()) return { ok: false };
		emitState({
			...lastOverlayState,
			status: "predict",
			predictDraftsLoading: true,
			predictSelectedIntent: intent.trim(),
			predictCursor: getCursorInOverlay(),
		});
		const ctx = contextEngine.getLiveContext();
		const { surface, drafts } = await resolvePredictDraftsForIntent(ctx, intent.trim());
		emitState({
			...lastOverlayState,
			status: "predict",
			predictPhase: "result",
			predictSurface: surface,
			predictSelectedIntent: intent.trim(),
			predictDrafts: drafts,
			predictDraftsLoading: false,
			predictCursor: getCursorInOverlay(),
		});
		return { ok: true };
	});

	ipcMain.handle("fold:predict-insert-draft", async (_e, text: string) => {
		if (isOnboardingReplyDemoStep()) {
			sendOnboardingVoiceEvent({ phase: "done", cleaned: text });
			if (lastReplyTranscript.trim()) {
				recordVoiceInteraction("reply", lastReplyTranscript, text);
			}
			lastReplyTranscript = "";
			replyWasRefined = false;
			clearPredictTargetApp();
			emitIdleState();
			return { ok: true, pasted: true };
		}
		const feedbackMeta = {
			surface: lastOverlayState.predictSurface ?? null,
			intent:
				lastOverlayState.predictSelectedIntent ??
				lastOverlayState.predictSuggestions?.[0]?.intent ??
				null,
			draft: text,
			anchor: lastOverlayState.predictAnchor ?? null,
		};
		const edited = replyWasRefined;
		const targetApp = getPredictTargetApp() ?? contextEngine.getLiveContext().activeApp;
		const refreshedTarget = captureTextInsertionTarget();
		overlayWindow?.setIgnoreMouseEvents(true, { forward: true });
		contextEngine.suppressClipboardCapture(5000);
		const result = await insertTextToFrontApp(text, refreshedTarget?.appName ?? targetApp);
		const replyTranscript = lastReplyTranscript.trim();
		lastReplyTranscript = "";
		replyWasRefined = false;
		clearPredictTargetApp();
		if (result.pasted) {
			if (replyTranscript) {
				recordVoiceInteraction("reply", replyTranscript, text);
			}
			// 只有真正贴进输入框才记正反馈，避免插入失败也算 adopt
			recordPredictCardFeedback({
				kind: edited ? "edited" : "accept",
				...feedbackMeta,
			});
			lastUndoReceipt = createUndoReceipt(refreshedTarget?.appName ?? targetApp);
			clearTextInsertionTarget();
			emitState({
				status: "done",
				result: "已插入回复",
				resultDetail: text,
				undoAvailable: true,
				verificationChecks: [{ rule: "text.inserted", passed: result.verified !== false, message: "已写入目标输入框" }],
			});
		} else {
			if (replyTranscript) {
				recordVoiceInteraction("reply", replyTranscript, result.error ?? "插入失败", "failed");
			}
			emitState({ status: "error", error: result.error ?? "插入失败" });
		}
		return result;
	});

	ipcMain.handle(
		"fold:structure-insert-draft",
		async (_e, text: string, targetAppName?: string | null) => {
			const trimmed = String(text ?? "").trim();
			if (!trimmed) return { ok: false, pasted: false };
			const targetApp =
				String(targetAppName ?? "").trim() ||
				voiceTargetApp ||
				contextEngine.getLiveContext().activeApp;
			const refreshedTarget = captureTextInsertionTarget();
			overlayWindow?.setIgnoreMouseEvents(true, { forward: true });
			contextEngine.suppressClipboardCapture(5000);
			const result = await insertTextToFrontApp(
				trimmed,
				refreshedTarget?.appName ?? targetApp,
			);
			if (result.pasted) {
				lastUndoReceipt = createUndoReceipt(refreshedTarget?.appName ?? targetApp);
				voiceTargetApp = null;
				clearTextInsertionTarget();
				emitState({
					status: "done",
					voiceMode: "structure",
					result: "已插入文字",
					resultDetail: trimmed,
					undoAvailable: true,
					structureDraftOpen: false,
					verificationChecks: [{ rule: "text.inserted", passed: result.verified !== false, message: "已写入目标输入框" }],
				});
			}
			return result;
		},
	);

	ipcMain.handle("fold:copy-text", (_e, text: string) => {
		const trimmed = String(text ?? "").trim();
		if (!trimmed) return { ok: false };
		clipboard.writeText(trimmed);
		return { ok: true };
	});

	ipcMain.handle("fold:predict-start-voice", () => {
		emitIdleState();
		toggleVoiceRecording("structure");
		return { ok: true };
	});

	ipcMain.handle("fold:predict-refine-voice", () => {
		if (!isReplyPredictCard()) return { ok: false };
		startReplyRefineRecording();
		return { ok: true };
	});

	ipcMain.handle("fold:connection-action", async (_e, action: string, context?: Record<string, unknown>) => {
		await runUserAction(action, context);
		return { ok: true };
	});

	ipcMain.handle("fold:connect-flow-start", async (_e, connectionId: string, kind: "login" | "install") => {
		const target = resolveConnectTarget(connectionId);
		if (!target) throw new Error(`未知连接: ${connectionId}`);
		return startConnectFlow(target, kind);
	});

	ipcMain.handle("fold:connect-flow-poll", async (_e, sessionId: string) => pollConnectFlow(sessionId));

	ipcMain.handle("fold:connect-flow-cancel", async (_e, sessionId: string) => {
		cancelConnectFlow(sessionId);
		return { ok: true };
	});

	ipcMain.handle("fold:connect-flow-activate", async (_e, sessionId: string) => {
		if (typeof sessionId !== "string" || !sessionId) {
			return { ok: false, opened: false };
		}
		const result = activateAgentConnectFlow(sessionId);
		return { ok: true, opened: result.opened, url: result.url };
	});

	ipcMain.handle("fold:open-external", async (_e, url: string) => {
		if (typeof url === "string" && /^(https?:|mailto:)/i.test(url)) {
			await shell.openExternal(url);
		}
		return { ok: true };
	});

	ipcMain.handle("fold:open-data-dir", async () => {
		const dir = resolveDataDir();
		const err = await shell.openPath(dir);
		return err ? { ok: false as const, error: err, path: dir } : { ok: true as const, path: dir };
	});

	ipcMain.handle("fold:run-task", async (_e, intent: string) => {
		isRecording = false;
		await executeTask(intent);
	});

	ipcMain.handle("fold:structure-voice", async (
		_e,
		transcript: string,
		opts?: { directStructured?: boolean },
	) => {
		isRecording = false;
		const directStructured =
			voiceCanUseDirectStructure && opts?.directStructured === true;
		voiceCanUseDirectStructure = false;
		await structureVoiceTranscript(transcript, { directStructured });
	});

	ipcMain.handle("fold:reply-voice", async (_e, transcript: string) => {
		isRecording = false;
		await replyVoiceTranscript(transcript);
	});

	ipcMain.handle("fold:retry-task", async () => {
		if (lastIntent) await executeTask(lastIntent);
	});

	ipcMain.handle("fold:undo-last-insert", async () => {
		if (!canUseUndoReceipt(lastUndoReceipt)) {
			lastUndoReceipt = null;
			return { ok: false, error: "撤销时限已过" };
		}
		const receipt = lastUndoReceipt;
		const result = await undoTextInsertion(receipt?.targetApp);
		if (result.ok) {
			lastUndoReceipt = null;
			recordPredictCardFeedback({
				kind: "undo",
				surface: lastOverlayState.predictSurface ?? "reply",
				intent: lastOverlayState.predictSelectedIntent ?? null,
				draft: lastOverlayState.resultDetail ?? null,
				anchor: lastOverlayState.predictAnchor ?? null,
			});
			emitState({ status: "done", result: "已撤销刚才的输入", undoAvailable: false });
		}
		return result;
	});

	ipcMain.handle("fold:ask-response", async (_e, input: string | UserActionResponse) => {
		const response: UserActionResponse =
			typeof input === "string"
				? { optionId: input, modality: "click" }
				: input;
		await handleInteractionResponse(response);
	});

	ipcMain.handle("fold:interaction-voice", async (_e, transcript: string) => {
		isRecording = false;
		await handleInteractionVoice(transcript);
	});

	ipcMain.handle("fold:toggle-interaction-voice", () => {
		toggleVoiceRecording("interaction");
	});

	ipcMain.on("fold:transcript-forward", (_e, text: string) => {
		emitState({ status: "listening", transcript: text });
	});

	ipcMain.on("fold:voice-level-forward", (_e, level: number) => {
		overlayWindow?.webContents.send("fold:voice-level", level);
	});

	ipcMain.on("fold:mouse-passthrough", (_e, ignore: boolean) => {
		overlayWindow?.setIgnoreMouseEvents(ignore, { forward: ignore });
	});

	ipcMain.handle(
		"fold:get-display-work-area",
		(_e, overlayPoint?: { x: number; y: number }) => {
			if (overlayPoint) {
				const savedArea = getDisplayWorkAreaForOverlayPoint(overlayPoint);
				if (savedArea) return savedArea;
				const screenPoint = overlayPointToScreen(overlayPoint, overlayWindow);
				return getDisplayWorkAreaInOverlay(screenPoint, overlayWindow);
			}
			return getPrimaryDisplayWorkAreaInOverlay(overlayWindow);
		},
	);

	ipcMain.handle("fold:get-overlay-state", () => lastOverlayState);

	ipcMain.handle(
		"fold:predict-feedback",
		(
			_e,
			payload: {
				kind: "dismiss" | "reject" | "accept" | "edited" | "undo" | "ignore";
				surface?: string | null;
				intent?: string | null;
				draft?: string | null;
				anchor?: string | null;
			},
		) => {
			recordPredictCardFeedback({
				kind: payload?.kind ?? "dismiss",
				surface: payload?.surface ?? lastOverlayState.predictSurface ?? null,
				intent:
					payload?.intent ??
					lastOverlayState.predictSelectedIntent ??
					lastOverlayState.predictSuggestions?.[0]?.intent ??
					null,
				draft: payload?.draft ?? null,
				anchor: payload?.anchor ?? lastOverlayState.predictAnchor ?? null,
			});
			return { ok: true };
		},
	);

	ipcMain.handle("fold:dismiss", (_e, opts?: { skipFeedback?: boolean; soft?: boolean }) => {
		if (!opts?.skipFeedback && lastOverlayState.status === "predict") {
			const phase = lastOverlayState.predictPhase;
			const hasDrafts = (lastOverlayState.predictDrafts?.length ?? 0) > 0;
			// pick / 还没出草案时关掉 = ignore，不参与晋升；出过草案再关才记 dismiss
			const kind =
				phase === "pick" || phase === "silent" || !hasDrafts ? "ignore" : "dismiss";
			recordPredictCardFeedback({
				kind,
				surface: lastOverlayState.predictSurface ?? null,
				intent:
					lastOverlayState.predictSelectedIntent ??
					lastOverlayState.predictSuggestions?.[0]?.intent ??
					null,
				draft: lastOverlayState.predictDrafts?.[0]?.text ?? null,
				anchor: lastOverlayState.predictAnchor ?? null,
			});
		}
		isRecording = false;
		replyWasRefined = false;
		if (ensureInteractionBroker().current()) {
			ensureInteractionBroker().cancel("用户取消了授权");
		}
		// 软关闭：只关卡片，待机继续（空 ASR / 关确认卡）
		if (opts?.soft && isVoiceStandbyActive() && voiceTargetApp) {
			enterVoiceStandby(voiceStandbyMode ?? "structure", {
				placement: voiceStandbyPlacement ?? lastOverlayState.voiceTabPlacement,
				appName: lastOverlayState.contextAppName ?? voiceTargetApp,
				appPath: lastOverlayState.contextAppPath,
				windowTitle: lastOverlayState.contextWindowTitle,
			});
			return;
		}
		exitVoiceStandby();
	});

	ipcMain.handle("fold:voice-empty", () => {
		isRecording = false;
		if (voiceOutcome === "interaction" && ensureInteractionBroker().current()) {
			// 空结果静默结束听写，不刷成失败态（短按/开麦竞态很常见）
			ensureInteractionBroker().updatePresentation({
				listening: false,
				validationMessage: undefined,
			});
			emitCurrentInteraction();
			return { ok: true, standby: false };
		}
		if (isVoiceStandbyActive() && voiceTargetApp) {
			enterVoiceStandby(voiceStandbyMode ?? "structure", {
				placement: voiceStandbyPlacement ?? lastOverlayState.voiceTabPlacement,
				appName: lastOverlayState.contextAppName ?? voiceTargetApp,
			});
			return { ok: true, standby: true };
		}
		exitVoiceStandby();
		return { ok: true, standby: false };
	});

	ipcMain.handle("fold:toggle-voice", () => {
		toggleVoiceRecording();
	});

	ipcMain.handle("fold:voice-error", (_e, message: string) => {
		isRecording = false;
		console.warn(`[fold:voice-error] ${String(message ?? "")}`);
		if (voiceOutcome === "interaction" && ensureInteractionBroker().current()) {
			ensureInteractionBroker().updatePresentation({
				listening: false,
				validationMessage: message,
			});
			emitCurrentInteraction();
			return;
		}
		emitState({ status: "error", error: message });
	});

	ipcMain.handle("fold:open-settings", (_e, section?: string) => {
		openSettingsWindow(section);
	});

	ipcMain.handle("fold:scan-input-habits", () => scanInputHabits());
	ipcMain.handle("fold:list-installed-input-methods", () => listInstalledInputMethods());

	ipcMain.handle("fold:import-input-habits", () => importInputHabitsOneClick());
	ipcMain.handle("fold:get-imported-input-habits", () => loadImportedInputHabits());
	ipcMain.handle("fold:export-input-habits-rime", async () => {
		const { canceled, filePaths } = await dialog.showOpenDialog({
			title: "选择搜狗词库备份（偏好设置 → 词库 → 导出）",
			filters: [{ name: "搜狗词库备份", extensions: ["bin"] }],
			properties: ["openFile"],
		});
		if (canceled || !filePaths[0]) return { canceled: true as const };
		return exportInputHabitsToRime({ sogouBinPath: filePaths[0] });
	});

	ipcMain.handle("fold:quit", () => {
		app.quit();
	});
}

registerIpc();

async function startVoiceRecording(outcome: VoiceOutcome) {
	if (isRecording) return;
	const standbyEligible =
		(outcome === "structure" || outcome === "reply") &&
		isVoiceStandbyActive() &&
		Boolean(voiceTargetApp);
	// Capture synchronously before any async work so the exact focused field is retained.
	// 待机复用时先不抓，避免覆盖 native 里保留的原目标输入框。
	let insertionTarget =
		outcome === "interaction" || standbyEligible ? null : captureTextInsertionTarget();
	voiceOutcome = outcome;
	voiceCanUseDirectStructure =
		outcome === "structure" && resolveAsrRuntime().provider === "dashscope";
	isRecording = true;
	// 立刻让渲染层开麦（音频进本地预缓冲），截图/定位等上下文工作并行进行，
	// 否则串行等下来首音节全部丢失。app/windowTitle 用缓存值即可，仅供 ASR 语境提示。
	createOverlayWindow();
	{
		const cachedCtx = contextEngine.getLiveContext();
		overlayWindow?.webContents.send("fold:hotkey-down", {
			mode: outcome,
			app: cachedCtx.activeApp,
			windowTitle: cachedCtx.activeWindow,
		});
	}
	if (outcome === "interaction") {
		const broker = ensureInteractionBroker();
		if (!broker.current()?.request.input.allowVoice) {
			isRecording = false;
			overlayWindow?.webContents.send("fold:hotkey-cancel");
			return;
		}
		broker.updatePresentation({
			listening: true,
			validationMessage: undefined,
		});
		emitCurrentInteraction();
		return;
	}
	await contextEngine.refreshActiveApp();
	const ctx = contextEngine.getLiveContext();
	// 待机复用仅当焦点没有主动切到别的真实 App。与进待机时的快照同源比对
	// （都取 ContextEngine.activeApp，ignoreApps 已滤掉知更自己），
	// 切走了就跟随当前光标重新锁定（Typeless 语义）。
	// ponytail: 同 App 内换输入框仍复用旧 target，粒度到 App 为止。
	let standbyReuse = standbyEligible;
	if (
		standbyEligible &&
		voiceStandbyActiveApp &&
		ctx.activeApp &&
		ctx.activeApp !== voiceStandbyActiveApp
	) {
		standbyReuse = false;
		insertionTarget = captureTextInsertionTarget();
		console.log(
			`[fold:standby] focus moved ${voiceStandbyActiveApp} -> ${ctx.activeApp}, abandon reuse`,
		);
	}
	if (!standbyReuse) {
		voiceTargetApp = insertionTarget?.appName ?? ctx.activeApp ?? null;
	}
	clearVoiceStandbyTimer();
	voiceStandbyUntil = null;

	// 代回必须在 raise overlay 之前截聊天窗：松手时 frontmost 常是 Electron，
	// 全屏回退又会落到主屏上一次微信会话。
	if (outcome === "reply") {
		if (!standbyReuse || !voiceReplyScreenshotPath) {
			voiceReplyScreenshotPath = null;
			try {
				const shot = standbyReuse && voiceTargetApp
					? await captureScreenshot({ target: "app", appName: voiceTargetApp })
					: await captureScreenshot({ target: "frontmost" });
				voiceReplyScreenshotPath = shot.path;
				console.log(
					`[fold:reply] precapture screenshot=${shot.path} frontmostApp=${voiceTargetApp ?? "?"} standby=${standbyReuse}`,
				);
			} catch (err) {
				console.warn("[fold:reply] precapture screenshot failed", err);
			}
		}
	} else {
		voiceReplyScreenshotPath = null;
	}

	const isOnboardingVoiceDemo =
		(outcome === "structure" && isOnboardingVoiceLiveStep()) ||
		(outcome === "reply" && isOnboardingReplyDemoStep());
	if (isOnboardingVoiceDemo) {
		voiceTargetApp = onboardingVoiceApp ?? (outcome === "reply" ? "飞书" : "微信");
		const voiceTabPlacement = await positionOverlayForAnchoredScreen(
			overlayWindow,
			null,
		);
		raiseOverlayForVoiceUi();
		emitState({
			status: "listening",
			transcript: "",
			result: null,
			resultDetail: null,
			voiceMode: outcome,
			voiceTabPlacement,
			voiceHint: null,
			predictRefining: false,
			...clearPredictState(),
			contextAppName: voiceTargetApp,
			contextAppPath: null,
			contextWindowTitle: onboardingVoiceWindowTitle,
			contextPageUrl: null,
			contextPageLabel: null,
		});
		if (outcome === "structure") sendOnboardingVoiceEvent({ phase: "listening" });
		return;
	}

	const voiceTabPlacement = await positionOverlayForActiveContext(overlayWindow, voiceTargetApp);
	raiseOverlayForVoiceUi();
	emitState({
		status: "listening",
		transcript: "",
		result: null,
		resultDetail: null,
		voiceMode: outcome,
		voiceTabPlacement,
		voiceHint: null,
		predictRefining: false,
		...clearPredictState(),
		...buildVoiceOverlayContext(ctx),
	});
}

function startReplyLatchedRecording() {
	replyLatched = true;
	replyRefineHold = false;
	startVoiceRecording("reply");
}

function startReplyRefineRecording() {
	if (isRecording) return;
	replyLatched = false;
	replyRefineHold = true;
	replyWasRefined = true;
	voiceOutcome = "reply";
	voiceCanUseDirectStructure = false;
	isRecording = true;
	createOverlayWindow();
	const app = voiceTargetApp ?? contextEngine.getLiveContext().activeApp;
	void positionOverlayForActiveContext(overlayWindow, app).then((voiceTabPlacement) => {
		raiseOverlayForVoiceUi();
		emitState({
			...lastOverlayState,
			status: "predict",
			voiceMode: "reply",
			predictRefining: true,
			predictDraftsLoading: false,
			voiceTabPlacement,
		});
	});
	const ctx = contextEngine.getLiveContext();
	overlayWindow?.webContents.send("fold:hotkey-down", {
		mode: "reply",
		app: voiceTargetApp ?? ctx.activeApp,
		windowTitle: ctx.activeWindow,
	});
}

function stopVoiceRecording() {
	if (!isRecording) return;
	isRecording = false;
	replyLatched = false;
	replyRefineHold = false;
	overlayWindow?.webContents.send("fold:hotkey-up", voiceOutcome);
}

function toggleVoiceRecording(outcome: VoiceOutcome = "structure") {
	if (isRecording) stopVoiceRecording();
	else startVoiceRecording(outcome);
}

function isReplyPredictCard(): boolean {
	return lastOverlayState.status === "predict" && lastOverlayState.predictSurface === "reply";
}

function cancelActiveSession() {
	replyLatched = false;
	replyRefineHold = false;
	voiceCanUseDirectStructure = false;
	if (isRecording) {
		const canceledOutcome = voiceOutcome;
		isRecording = false;
		overlayWindow?.webContents.send("fold:hotkey-cancel");
		if (canceledOutcome === "interaction") {
			ensureInteractionBroker().updatePresentation({ listening: false });
			emitCurrentInteraction();
			return;
		}
		exitVoiceStandby();
		return;
	}
	if (activeTaskAbortController && !activeTaskAbortController.signal.aborted) {
		activeTaskAbortController.abort();
		if (ensureInteractionBroker().current()) {
			ensureInteractionBroker().cancel("任务已取消");
		}
		emitState({ status: "error", error: "任务已取消" });
		return;
	}
	if (isVoiceStandbyActive() || lastOverlayState.status === "predict") {
		exitVoiceStandby();
	}
}

function registerHotkeys() {
	stopHotkey = startHoldHotkey(
		{
		onAgentToggle: () => {
			if (isOnboardingHotkeyTestStep()) return;
			if (ensureInteractionBroker().current()) {
				toggleVoiceRecording("interaction");
				return;
			}
			toggleVoiceRecording("agent");
		},
		onTriggerDown: () => {
			if (isOnboardingHotkeyTestStep() || isRecording) return;
			// keydown 即预热麦克风：短按/长按最终都要开麦，提前 ~300ms 消除开麦死区
			createOverlayWindow();
			overlayWindow?.webContents.send("fold:voice-warm");
		},
		onStructureToggle: () => {
			if (isOnboardingHotkeyTestStep()) return;
			if (ensureInteractionBroker().current()) {
				toggleVoiceRecording("interaction");
				return;
			}
			if (isRecording && voiceOutcome === "reply" && replyLatched) {
				stopVoiceRecording();
				return;
			}
			if (isRecording && voiceOutcome === "reply") return;
			toggleVoiceRecording("structure");
		},
		onReplyHoldStart: () => {
			if (isOnboardingHotkeyTestStep()) return;
			if (isReplyPredictCard() && !isRecording) {
				startReplyRefineRecording();
				return;
			}
			if (isRecording && voiceOutcome === "structure") {
				isRecording = false;
				overlayWindow?.webContents.send("fold:hotkey-cancel");
			}
			if (!isRecording) startReplyLatchedRecording();
		},
		onReplyHoldEnd: () => {
			if (isOnboardingHotkeyTestStep()) return;
			if (isRecording && voiceOutcome === "reply" && replyRefineHold) {
				stopVoiceRecording();
			}
		},
		onReplyToggle: () => {
			if (isOnboardingHotkeyTestStep()) return;
			toggleVoiceRecording("reply");
		},
		onCancel: cancelActiveSession,
		onHotkeyTest: (event) => {
			if (onboardingWindow && !onboardingWindow.isDestroyed()) {
				onboardingWindow.webContents.send("fold:onboarding-hotkey-event", event);
			}
		},
		},
		loadConfig().hotkeys ?? {},
	);
}

function maybeShowWeeklyRecap() {
	if (!shouldShowWeeklyRecap()) return;
	if (
		isRecording ||
		lastOverlayState.status === "predict" ||
		lastOverlayState.status === "listening" ||
		lastOverlayState.status === "ask"
	) {
		return;
	}
	const recap = buildWeeklyRecap();
	markWeeklyRecapShown(recap.weekKey);
	createOverlayWindow();
	emitState({
		status: "done",
		result: recap.title,
		resultDetail: recap.body,
		undoAvailable: false,
	});
}

app.whenReady().then(() => {
	if (process.platform === "darwin") {
		app.setName(PRODUCT_NAME);
	}
	syncDockVisibility();

	contextEngine.start();
	hydrateContextFromDb();
	configureRemoteRelay({ executeTask, handleInteractionResponse });
	startRemoteRelay();
	stopHabitRecall = startHabitRecallLoop(() => recallHabitsFromUsage());
	startMemoryConsolidationLoop();
	const restoredInteraction = ensureInteractionBroker().current();
	if (restoredInteraction) {
		lastIntent = restoredInteraction.intent;
		lastOverlayState = {
			...lastOverlayState,
			...interactionState(restoredInteraction),
		};
	}
	createOverlayWindow();
	registerHotkeys();
	void refreshPredictCacheEnriched(contextEngine.getLiveContext());
	startAhaProactiveLoop();

	// Development-only product E2E entry. This deliberately enters through
	// executeTask (the same IPC/voice path), never by calling runtime/connectors directly.
	const devE2eIntent = process.env.VITE_DEV_SERVER_URL
		? process.env.FOLD_E2E_INTENT?.trim()
		: undefined;
	if (devE2eIntent && !devE2eIntentStarted) {
		devE2eIntentStarted = true;
		setTimeout(() => void executeTask(devE2eIntent), 1_500);
	}
	if (process.env.VITE_DEV_SERVER_URL && process.env.FOLD_E2E_HITL === "1") {
		lastIntent = "发送飞书 E2E 结果到产品讨论群";
		setTimeout(() => {
			void requestUserAction({
				title: "发送飞书消息前，请确认",
				message: "产品讨论群\nE2E 已通过，日历打包路径还需处理。",
				hint: "将向外部发送消息",
				kind: "confirm",
				risk: "external",
				runContext: { skipExecuteOnRestore: true },
				options: [
					{ id: "allow-once", label: "允许这一次", tone: "primary" },
					{ id: "edit", label: "编辑后发送" },
					{ id: "cancel", label: "取消任务", tone: "danger" },
				],
			}).then((choice) => {
				emitState({ status: "done", result: `已记录 HITL 选择：${choice}` });
			}).catch((error: Error) => {
				emitState({ status: "error", error: error.message });
			});
		}, 1_200);
	}

	// 启动后错开 onboarding：若本周该看回顾，弹一张完成态卡片
	setTimeout(() => {
		try {
			maybeShowWeeklyRecap();
		} catch {
			/* ignore */
		}
	}, 12_000);

	const trayApi = createTray({
		onVoiceStructure: () => toggleVoiceRecording("structure"),
		onReplyPredict: () => showReplyPredictions(),
		onVoiceAgent: () => toggleVoiceRecording("agent"),
		onCancel: cancelActiveSession,
		onOpenSettings: openSettingsWindow,
		onQuit: () => app.quit(),
		getSessionState: () => ({
			recording: isRecording,
			predicting: lastOverlayState.status === "predict",
		}),
		getHotkeyLabels: () => {
			const bindings = getActiveHotkeyBindings();
			return {
				structure: bindings.trigger.trayShort,
				reply: bindings.trigger.trayHold,
				agent: bindings.agent.trayLabel,
				cancel: bindings.cancel.trayLabel,
			};
		},
	});
	refreshTrayMenu = trayApi.refreshMenu;

	if (!isOnboardingComplete()) {
		openOnboardingWindow();
	} else {
		setTimeout(() => void ensureAccessibilityPermission(), 1200);
	}
});

app.on("will-quit", () => {
	activeTaskPowerAssertionCount = 0;
	stopTaskPowerAssertion();
	stopHotkey?.();
	stopHabitRecall?.();
	stopMemoryConsolidationLoop();
	stopRemoteRelay();
	void shutdownCodexAppServer();
	contextEngine.stop();
});

app.on("window-all-closed", () => {
	// menu bar app — keep running
});
