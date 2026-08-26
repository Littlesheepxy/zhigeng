export { runTask, runMockTask } from "./orchestrator.js";
export {
	canUseSmartAction,
	consumeTrialSmartAction,
	INITIAL_TRIAL_SMART_ACTIONS,
	normalizePlanTier,
	remainingTrialSmartActions,
	resolveEntitlements,
	type Entitlements,
	type PlanTier,
	type UpgradeReason,
} from "./entitlements.js";
export {
	buildPredictions,
	buildSituationFingerprint,
	clearPredictCache,
	episodeSituationFingerprint,
	getPredictCacheKey,
	getPredictions,
	needsScreenCalibration,
	refreshPredictCache,
	similarityScore,
	type PredictEnrichment,
	type PredictMode,
	type PredictPhase,
	type PredictResult,
	type PredictSuggestion,
	type SituationFingerprint,
} from "./predict.js";
export { generatePredictDrafts, type PredictDraftLine } from "./predict-drafts.js";
export {
	generateAhaGuess,
	ruleBasedAhaReply,
	applyContextualAcronymFixes,
	applyLocalHotwordHints,
	shouldCleanSpeechLocally,
	streamAhaGuess,
	structureSpeechText,
	type AhaGuessInput,
	type AhaGuessPage,
	type StreamAhaGuessOptions,
	type StructuredSpeech,
} from "@fold/ai";
export { hasPlannerApiKey, hasFastVisionApiKey, probeLlm } from "@fold/ai";
export { inferPredictSurface, surfaceActionLabel, type PredictSurface } from "./predict-surface.js";
export { predictContextSnippet } from "./predict-fallback.js";
export {
	buildAgentPlannerContextSummary,
	enrichContext,
	formatEnrichedPlannerSummary,
	runAgentPlannerContextSelfCheck,
	type ContextEnrichScope,
	type EnrichedContext,
} from "./context-enrich.js";
export {
	computeFocusDwells,
	formatDwellDuration,
	hedgedPrefix,
	scoreContextConfidence,
	type ContextConfidence,
	type ContextConfidenceLevel,
	type FocusDwell,
} from "@fold/context";
export { extractEntityTokens } from "./entity-extract.js";
export {
	formatPlannerMemory,
	formatTracesForPlanner,
	retrieveSimilarTraces,
	type EpisodeTrace,
} from "./trace-retrieval.js";
export {
	anchorFromObjects,
	primaryInformationObject,
	resolveInformationObjects,
	type InformationObject,
	type InformationObjectInput,
	type InformationObjectKind,
} from "./information-object.js";
export {
	matchRoutinesForTrail,
	mineRoutinesFromEpisodes,
	trailTokensFromEpisode,
	type MinedRoutine,
} from "./routine-mining.js";
export { recallHabitsFromUsage, startHabitRecallLoop } from "./habit-recall.js";
export {
	formatRecentRejectBrief,
	promoteFeedbackConstraints,
	recordPredictFeedback,
	runFeedbackRecallSelfCheck,
	type PredictFeedbackInput,
	type PredictFeedbackKind,
} from "./feedback-recall.js";
export {
	buildWeeklyRecap,
	currentWeekKey,
	markWeeklyRecapShown,
	runWeeklyRecapSelfCheck,
	shouldShowWeeklyRecap,
	type WeeklyRecap,
} from "./weekly-recap.js";
export {
	buildResultDetail,
	buildUserVisibleSummary,
	formatEpisodeSummaryDisplay,
	formatThinkingText,
	isRawPayloadText,
	summaryFromJsonPayload,
} from "./format-result.js";
export { labelForSkill, labelForStep } from "./step-labels.js";
export {
	buildProfileImportPrompt,
	parseProfileImportResponse,
	type ProfileImportFields,
} from "./profile-prompt.js";
export {
	buildProfileBrief,
	buildProfileChecklist,
	buildOnboardingDemoSentence,
	extractProfileKeywords,
	type OnboardingDemoSentence,
} from "./profile-brief.js";
export {
	resolveSpeechHotwords,
	type SpeechHotwordLexiconEntry,
} from "./speech-hotwords.js";
export {
	ahaProactiveTierFor,
	AHA_PROACTIVE_TIERS,
	decideAhaProactiveShow,
	DEFAULT_AHA_PROACTIVE,
	type AhaProactiveFrequency,
	type AhaProactiveGateInput,
	type AhaProactiveGateDecision,
	type AhaProactiveTier,
} from "./aha-proactive.js";
export { runPlan } from "./executor.js";
export { formatRelevantEpisodes } from "./episode-context.js";
export { formatProbeSummary, runProbes } from "./probe-runner.js";
export {
	resolveTier,
	tryCompiledPlan,
	type CompiledMatch,
	type ExecutionTier,
	type RouteDecision,
} from "./router.js";
export {
	buildCapabilitySnapshot,
	deriveExecutionFlags,
	listCapabilityDefs,
	normalizeExecutionMode,
	type CapabilityConfig,
	type CapabilityItem,
	type CapabilitySnapshot,
	type ExecutionMode,
	type ExecutorItem,
} from "./capability-catalog.js";
export { validatePlan } from "./validator.js";
export { buildReactAgentPlan, buildRepairBrief } from "./repair.js";
export {
	isGuiIntent,
	resolveSendChannel,
	isExplicitMailIntent,
	isFeishuSelfMessageIntent,
	extractFeishuSelfMessageText,
} from "./capability-resolver.js";
export type { SendChannel, OfficeChannelHint } from "./capability-resolver.js";
export {
	buildRecoveryPlan,
	classifyFailure,
	DEFAULT_REPAIR_BUDGET,
	GUI_REPAIR_BUDGET,
	handleFailure,
	resolveRepairBudget,
	selectRepairBackend,
	type RecoveryAction,
	type RepairBackend,
	type RepairBudget,
} from "./recovery.js";
export {
	getAgentProbe,
	getCdpConnected,
	getUitarsProbe,
	getWorkbuddyProbe,
	runRecoveryLoop,
	type RecoveryRunResult,
} from "./recovery-runner.js";
export type {
	FoldStateEvent,
	OverlayStatus,
	OrchestratorDeps,
	StateEmitter,
	StepView,
	TaskResult,
	StepResult,
	UserActionInputPolicy,
	UserActionKind,
	UserActionOption,
	UserActionRequest,
	UserActionResponse,
	UserActionRisk,
	UserInteractionView,
} from "./types.js";
export {
	matchUserActionVoice,
	normalizeUserActionRequest,
	type NormalizedUserActionRequest,
} from "./interaction.js";
