export { probeLlm } from "./probe-llm.js";
export { extraProviderHeaders, toLanguageModel } from "./providers.js";
export {
	generateAhaGuess,
	ruleBasedAhaReply,
	streamAhaGuess,
	type AhaGuessInput,
	type AhaGuessPage,
	type StreamAhaGuessOptions,
} from "./aha-guess.js";
export {
	buildPlannerPrompt,
	buildReplannerPrompt,
	type PlannerPromptInput,
	type ReplannerPromptInput,
} from "./prompt.js";
export {
	generateActionPlan,
	generateRecoveryPlan,
	isMailCountIntent,
	mockActionPlan,
	ActionPlanSchema,
	ActionStepSchema,
	type ActionPlan,
	type ActionStep,
} from "./planner.js";
export {
	generatePredictDrafts,
	type PredictDraftInput,
	type PredictDraftLine,
	type PredictSurface,
} from "./predict-drafts.js";
export {
	applyContextualAcronymFixes,
	applyLocalHotwordHints,
	shouldCleanSpeechLocally,
	structureSpeechText,
	type StructuredSpeech,
} from "./structure-speech.js";
export {
	PROVIDER_TABLE,
	type Provider,
	type ModelChoice,
	type ModelRole,
} from "./types.js";
export {
	defaultFastModel,
	defaultFastVisionModel,
	hasApiKeyForProvider,
	hasFastModelApiKey,
	hasFastVisionApiKey,
	hasPlannerApiKey,
	resolveModelChoice,
} from "./model-choice.js";
export { generateFastText } from "./fast-text.js";
export {
	generateFastVision,
	describeFastVisionChoice,
	type FastVisionImage,
	type FastVisionOptions,
} from "./fast-vision.js";
export {
	gatewayGenerateText,
	gatewayStreamText,
	type FundingSource,
	type GatewayFeature,
	type LlmCallContext,
	type UsageUnits,
} from "./gateway.js";
