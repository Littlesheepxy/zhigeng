import type { FoldConfig } from "./config.js";
import { loadConfig } from "./config.js";
import {
	appendLocalWhisperAudio,
	cancelLocalWhisperSession,
	hasLocalWhisperModel,
	LOCAL_VOICE_MODEL_SIZE_MB,
	resolveLocalModelPath,
	startLocalWhisperSession,
	takeLocalPcmf32,
	transcribeLocalWhisper,
} from "./local-whisper.js";
import {
	hasLocalSenseVoiceModel,
	LOCAL_SENSEVOICE_SIZE_MB,
	transcribeSenseVoice,
} from "./local-sensevoice.js";

export type LocalAsrEngine = "whisper" | "sensevoice";

export {
	appendLocalWhisperAudio as appendLocalAsrAudio,
	cancelLocalWhisperSession as cancelLocalAsrSession,
	startLocalWhisperSession as startLocalAsrSession,
};

export function resolveLocalEngine(config: Pick<FoldConfig, "localAsrEngine" | "asrProvider" | "localWhisperModelPath">): LocalAsrEngine {
	if (config.localAsrEngine === "whisper" || config.localAsrEngine === "sensevoice") {
		return config.localAsrEngine;
	}
	if (config.asrProvider === "local-whisper") return "whisper";
	if (config.asrProvider === "local-funasr") return "sensevoice";
	if (hasLocalSenseVoiceModel()) return "sensevoice";
	if (hasLocalWhisperModel(config.localWhisperModelPath)) return "whisper";
	return "sensevoice";
}

export function hasSelectedLocalModel(config: FoldConfig): boolean {
	return resolveLocalEngine(config) === "sensevoice"
		? hasLocalSenseVoiceModel()
		: hasLocalWhisperModel(config.localWhisperModelPath);
}

export function downloadSizeMbFor(engine: LocalAsrEngine): number {
	return engine === "whisper" ? LOCAL_VOICE_MODEL_SIZE_MB : LOCAL_SENSEVOICE_SIZE_MB;
}

export async function finishLocalAsrSession(): Promise<string> {
	const config = loadConfig();
	const pcm = takeLocalPcmf32();
	if (!pcm.length) return "";
	if (resolveLocalEngine(config) === "sensevoice") {
		return transcribeSenseVoice(pcm);
	}
	return transcribeLocalWhisper(pcm, resolveLocalModelPath(config.localWhisperModelPath));
}
