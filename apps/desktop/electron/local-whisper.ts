import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { promisify } from "node:util";
import { resolveDataDir } from "./data-dir.js";

export const LOCAL_VOICE_MODEL_NAME = "ggml-small.bin";
export const LOCAL_VOICE_MODEL_SIZE_MB = 470;

export function getDefaultLocalModelPath(): string {
	return join(resolveDataDir(), "models", LOCAL_VOICE_MODEL_NAME);
}

function expandHome(path: string): string {
	return resolve(path.replace(/^~(?=\/|$)/, homedir()));
}

export function resolveLocalModelPath(modelPath?: string): string {
	return expandHome(
		modelPath ??
			process.env.FOLD_LOCAL_WHISPER_MODEL_PATH ??
			getDefaultLocalModelPath(),
	);
}

let pcmChunks: Int16Array[] = [];
let transcribeChain: Promise<unknown> = Promise.resolve();
let whisperTranscribe:
	| ((options: Record<string, unknown>) => Promise<{ transcription?: unknown }>)
	| null = null;

function getWhisperTranscribe() {
	if (whisperTranscribe) return whisperTranscribe;
	const require = createRequire(__filename);
	const packageDir = dirname(require.resolve("@kutalia/whisper-node-addon/package.json"));
	const platform = process.platform === "darwin" ? "mac" : process.platform;
	let addonPath = join(packageDir, "dist", `${platform}-${process.arch}`, "whisper.node");
	if (addonPath.includes(".asar/")) addonPath = addonPath.replace(".asar/", ".asar.unpacked/");
	const addon = require(addonPath) as {
		whisper: (
			options: Record<string, unknown>,
			callback: (error: Error | null, result: { transcription?: unknown }) => void,
		) => void;
	};
	whisperTranscribe = promisify(addon.whisper);
	return whisperTranscribe;
}

export function hasLocalWhisperModel(modelPath?: string): boolean {
	const resolved = modelPath?.trim()
		? expandHome(modelPath)
		: resolveLocalModelPath();
	return existsSync(resolved);
}

export function startLocalWhisperSession(): void {
	pcmChunks = [];
}

export function takeLocalPcmf32(): Float32Array {
	const sampleCount = pcmChunks.reduce((sum, chunk) => sum + chunk.length, 0);
	const pcm = new Float32Array(sampleCount);
	let offset = 0;
	for (const chunk of pcmChunks) {
		for (let i = 0; i < chunk.length; i += 1) {
			pcm[offset + i] = chunk[i] / 32768;
		}
		offset += chunk.length;
	}
	pcmChunks = [];
	return pcm;
}

export function appendLocalWhisperAudio(chunk: ArrayBuffer | Uint8Array): void {
	const bytes =
		chunk instanceof Uint8Array
			? chunk
			: new Uint8Array(chunk);
	const copy = new Uint8Array(bytes.byteLength);
	copy.set(bytes);
	pcmChunks.push(new Int16Array(copy.buffer));
}

function transcriptionText(transcription: unknown): string {
	if (!Array.isArray(transcription)) return "";
	return transcription
		.map((segment: unknown) => {
			if (typeof segment === "string") return segment;
			if (!Array.isArray(segment)) return "";
			return String(segment[2] ?? segment.at(-1) ?? "");
		})
		.join(" ")
		.replace(/\s+/g, " ")
		.trim();
}

export async function transcribeLocalWhisper(
	pcm: Float32Array,
	modelPath?: string,
): Promise<string> {
	if (!pcm.length) return "";
	if (!modelPath?.trim()) {
		throw new Error("请先在设置中下载语音包。");
	}
	const resolvedModel = expandHome(modelPath);
	if (!existsSync(resolvedModel)) {
		throw new Error("语音包尚未下载。请打开设置，下载后即可使用本地语音识别。");
	}

	const next = transcribeChain.then(async () => {
		const transcribe = getWhisperTranscribe();
		const result = await transcribe({
			model: resolvedModel,
			pcmf32: pcm,
			language: "zh",
			use_gpu: true,
			translate: false,
			no_timestamps: true,
			no_prints: true,
		});
		return transcriptionText(result.transcription);
	});
	transcribeChain = next.catch(() => undefined);
	return next as Promise<string>;
}

export async function finishLocalWhisperSession(modelPath?: string): Promise<string> {
	return transcribeLocalWhisper(takeLocalPcmf32(), modelPath);
}

export function cancelLocalWhisperSession(): void {
	pcmChunks = [];
}
