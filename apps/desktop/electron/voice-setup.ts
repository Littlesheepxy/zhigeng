import { createWriteStream, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { remainingTrialSmartActions, resolveEntitlements } from "@fold/runtime";
import { loadConfig, saveConfig, applyConfigToEnv } from "./config.js";
import {
	downloadSizeMbFor,
	hasSelectedLocalModel,
	resolveLocalEngine,
	type LocalAsrEngine,
} from "./local-asr.js";
import { downloadSenseVoicePack } from "./local-sensevoice.js";
import {
	getDefaultLocalModelPath,
	hasLocalWhisperModel,
	resolveLocalModelPath,
} from "./local-whisper.js";

const VOICE_PACK_URL =
	"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";

export type VoiceSetupMode = "cloud" | "local" | "download-needed";

export interface VoiceSetupStatus {
	planTier: "free" | "pro" | "ultra";
	mode: VoiceSetupMode;
	ready: boolean;
	title: string;
	detail: string;
	downloadSizeMb?: number;
	trialRemaining?: number;
	localEngine: LocalAsrEngine;
	whisperReady: boolean;
	sensevoiceReady: boolean;
}

export function shouldUseSmartVoice(
	provider: string | undefined,
	hasCloudEntitlement: boolean,
	hasSmartTrial: boolean,
): boolean {
	const localSelected = provider === "local-whisper" || provider === "local-funasr";
	return !localSelected && (hasCloudEntitlement || hasSmartTrial);
}

export function getVoiceSetupStatus(): VoiceSetupStatus {
	const config = loadConfig();
	const tier = resolveEntitlements(config.planTier);
	const localEngine = resolveLocalEngine(config);
	const whisperReady = hasLocalWhisperModel(config.localWhisperModelPath);
	const sensevoiceReady = hasSelectedLocalModel({ ...config, localAsrEngine: "sensevoice" });
	const hasLocal = hasSelectedLocalModel(config);
	const trialRemaining = remainingTrialSmartActions(config.trialSmartActionsRemaining);
	const base = {
		planTier: tier.tier,
		trialRemaining,
		localEngine,
		whisperReady,
		sensevoiceReady,
	};

	if (shouldUseSmartVoice(config.asrProvider, tier.cloudAsr, trialRemaining > 0)) {
		return {
			...base,
			mode: "cloud",
			ready: true,
			title: "知更智能转写",
			detail: tier.cloudAsr
				? "Pro 已包含场景理解、改口整理与专有名词增强。"
				: `可免费体验 ${trialRemaining} 次场景理解、改口整理与智能代回。`,
		};
	}

	if (hasLocal) {
		return {
			...base,
			mode: "local",
			ready: true,
			title: "本地语音已就绪",
			detail:
				localEngine === "sensevoice"
					? "阿里 SenseVoice 在设备本地识别，中文更准，不上传云端。"
					: "Whisper 在设备本地识别，不上传云端，随时可用。",
		};
	}

	const downloadSizeMb = downloadSizeMbFor(localEngine);
	return {
		...base,
		mode: "download-needed",
		ready: false,
		title: "需要下载离线语音包",
		detail:
			localEngine === "sensevoice"
				? `下载阿里开源 SenseVoice，约 ${downloadSizeMb} MB，中文离线识别更准。`
				: `下载 Whisper 离线包，约 ${downloadSizeMb} MB。`,
		downloadSizeMb,
	};
}

async function downloadWhisperPack(): Promise<
	{ ok: true; path: string } | { ok: false; error: string }
> {
	const config = loadConfig();
	const targetPath = resolveLocalModelPath(config.localWhisperModelPath);
	try {
		mkdirSync(dirname(targetPath), { recursive: true });
		const response = await fetch(VOICE_PACK_URL);
		if (!response.ok || !response.body) {
			return { ok: false, error: `下载失败（${response.status}）` };
		}
		await pipeline(
			Readable.fromWeb(response.body as import("node:stream/web").ReadableStream),
			createWriteStream(targetPath),
		);
		if (!hasLocalWhisperModel(config.localWhisperModelPath)) {
			return { ok: false, error: "下载完成但文件校验失败，请重试。" };
		}
		const next = {
			...config,
			localAsrEngine: "whisper" as const,
			localWhisperModelPath: config.localWhisperModelPath ?? getDefaultLocalModelPath(),
		};
		saveConfig(next);
		applyConfigToEnv(next);
		return { ok: true, path: targetPath };
	} catch (error) {
		return { ok: false, error: error instanceof Error ? error.message : String(error) };
	}
}

export async function downloadVoicePack(
	engine?: LocalAsrEngine,
): Promise<{ ok: true; path: string } | { ok: false; error: string }> {
	const config = loadConfig();
	const selected = engine ?? resolveLocalEngine(config);
	if (selected === "sensevoice") {
		const result = await downloadSenseVoicePack();
		if (result.ok) {
			const next = { ...loadConfig(), localAsrEngine: "sensevoice" as const };
			saveConfig(next);
			applyConfigToEnv(next);
		}
		return result;
	}
	return downloadWhisperPack();
}
