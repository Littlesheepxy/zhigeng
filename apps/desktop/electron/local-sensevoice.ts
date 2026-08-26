import { createWriteStream, existsSync, mkdirSync, unlinkSync } from "node:fs";
import { createRequire } from "node:module";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { resolveDataDir } from "./data-dir.js";

const execFileAsync = promisify(execFile);

export const SENSEVOICE_DIR_NAME =
	"sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17";
export const SENSEVOICE_PACK_URL =
	"https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2";
export const LOCAL_SENSEVOICE_SIZE_MB = 230;

type OfflineRecognizer = {
	createStream: () => OfflineStream;
	decode: (stream: OfflineStream) => void;
	getResult: (stream: OfflineStream) => unknown;
};

type OfflineStream = {
	acceptWaveform: (wave: { sampleRate: number; samples: Float32Array }) => void;
};

let recognizer: OfflineRecognizer | null = null;
let transcribeChain: Promise<unknown> = Promise.resolve();

export function getDefaultSenseVoiceDir(): string {
	return join(resolveDataDir(), "models", SENSEVOICE_DIR_NAME);
}

function expandHome(path: string): string {
	return resolve(path.replace(/^~(?=\/|$)/, homedir()));
}

export function resolveSenseVoiceDir(modelDir?: string): string {
	return expandHome(modelDir?.trim() || getDefaultSenseVoiceDir());
}

export function hasLocalSenseVoiceModel(modelDir?: string): boolean {
	const dir = resolveSenseVoiceDir(modelDir);
	return existsSync(join(dir, "model.int8.onnx")) && existsSync(join(dir, "tokens.txt"));
}

export function stripSenseVoiceTags(text: string): string {
	return text.replace(/<\|[^|]*\|>/g, "").replace(/\s+/g, " ").trim();
}

function resultText(result: unknown): string {
	if (typeof result === "string") return stripSenseVoiceTags(result);
	if (result && typeof result === "object" && "text" in result) {
		return stripSenseVoiceTags(String((result as { text: unknown }).text ?? ""));
	}
	return "";
}

function getRecognizer(modelDir: string): OfflineRecognizer {
	if (recognizer) return recognizer;
	const require = createRequire(__filename);
	const sherpa = require("sherpa-onnx-node") as {
		OfflineRecognizer: new (config: Record<string, unknown>) => OfflineRecognizer;
	};
	recognizer = new sherpa.OfflineRecognizer({
		featConfig: { sampleRate: 16000, featureDim: 80 },
		modelConfig: {
			senseVoice: {
				model: join(modelDir, "model.int8.onnx"),
				useInverseTextNormalization: 1,
			},
			tokens: join(modelDir, "tokens.txt"),
			numThreads: 2,
			provider: "cpu",
			debug: 0,
		},
	});
	return recognizer;
}

export async function transcribeSenseVoice(
	pcm: Float32Array,
	modelDir?: string,
): Promise<string> {
	if (!pcm.length) return "";
	const dir = resolveSenseVoiceDir(modelDir);
	if (!hasLocalSenseVoiceModel(dir)) {
		throw new Error("阿里语音包尚未下载。请打开设置，下载 SenseVoice 后即可离线使用。");
	}
	const next = transcribeChain.then(async () => {
		const engine = getRecognizer(dir);
		const stream = engine.createStream();
		stream.acceptWaveform({ sampleRate: 16000, samples: pcm });
		engine.decode(stream);
		return resultText(engine.getResult(stream));
	});
	transcribeChain = next.catch(() => {
		recognizer = null;
	});
	return next as Promise<string>;
}

export async function downloadSenseVoicePack(): Promise<
	{ ok: true; path: string } | { ok: false; error: string }
> {
	const dir = getDefaultSenseVoiceDir();
	if (hasLocalSenseVoiceModel(dir)) return { ok: true, path: dir };
	const modelsRoot = dirname(dir);
	const archivePath = join(modelsRoot, `${SENSEVOICE_DIR_NAME}.tar.bz2`);
	try {
		mkdirSync(modelsRoot, { recursive: true });
		const response = await fetch(SENSEVOICE_PACK_URL);
		if (!response.ok || !response.body) {
			return { ok: false, error: `下载失败（${response.status}）` };
		}
		await pipeline(
			Readable.fromWeb(response.body as import("node:stream/web").ReadableStream),
			createWriteStream(archivePath),
		);
		await execFileAsync("tar", ["-xjf", archivePath, "-C", modelsRoot], {
			timeout: 180_000,
		});
		unlinkSync(archivePath);
		if (!hasLocalSenseVoiceModel(dir)) {
			return { ok: false, error: "下载完成但文件校验失败，请重试。" };
		}
		return { ok: true, path: dir };
	} catch (error) {
		try {
			if (existsSync(archivePath)) unlinkSync(archivePath);
		} catch {
			// ponytail: leftover archive is only a cache; next download overwrites
		}
		return { ok: false, error: error instanceof Error ? error.message : String(error) };
	}
}
