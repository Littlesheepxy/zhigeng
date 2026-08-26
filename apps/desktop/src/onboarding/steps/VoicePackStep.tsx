import { useEffect, useState } from "react";
import { Check, Download, ShieldCheck, Sparkles } from "lucide-react";
import {
	OnboardingPrimaryBtn,
	OnboardingShell,
} from "../components/OnboardingShell";

type VoiceChoice = "smart" | "local";
type LocalEngine = "whisper" | "sensevoice";

export function VoicePackStep({ onNext, onBack }: { onNext: () => void; onBack: () => void }) {
	const [setup, setSetup] = useState<Awaited<ReturnType<typeof window.fold.getVoiceSetup>> | null>(null);
	const [config, setConfig] = useState<Awaited<ReturnType<typeof window.fold.getConfig>> | null>(null);
	const [choice, setChoice] = useState<VoiceChoice>("smart");
	const [localEngine, setLocalEngine] = useState<LocalEngine>("sensevoice");
	const [downloading, setDownloading] = useState(false);
	const [error, setError] = useState<string | null>(null);

	useEffect(() => {
		void Promise.all([window.fold.getVoiceSetup(), window.fold.getConfig()]).then(
			([nextSetup, nextConfig]) => {
				setSetup(nextSetup);
				setConfig(nextConfig);
				const localSelected =
					nextConfig.asrProvider === "local-whisper" ||
					nextConfig.asrProvider === "local-funasr";
				const smartAvailable =
					nextSetup.planTier !== "free" || (nextSetup.trialRemaining ?? 0) > 0;
				setChoice(localSelected || !smartAvailable ? "local" : "smart");
				if (nextConfig.localAsrEngine === "whisper" || nextConfig.asrProvider === "local-whisper") {
					setLocalEngine("whisper");
				}
			},
		);
	}, []);

	const smartAvailable =
		setup?.planTier !== "free" || (setup?.trialRemaining ?? 0) > 0;
	const smartMeta =
		setup?.planTier === "free"
			? smartAvailable
				? `免费体验 ${setup?.trialRemaining ?? 20} 次`
				: "智能体验已用完"
			: "Pro 已包含";

	async function continueWithSmart() {
		if (!config || !smartAvailable) return;
		setError(null);
		const nextConfig = { ...config, asrProvider: "auto" as const };
		await window.fold.saveConfig(nextConfig);
		setConfig(nextConfig);
		onNext();
	}

	async function downloadAndContinue() {
		if (!config) return;
		setDownloading(true);
		setError(null);
		const nextConfig = {
			...config,
			asrProvider: localEngine === "whisper" ? ("local-whisper" as const) : ("local-funasr" as const),
			localAsrEngine: localEngine,
		};
		await window.fold.saveConfig(nextConfig);
		setConfig(nextConfig);
		const localSetup = await window.fold.getVoiceSetup();
		const alreadyReady =
			localEngine === "whisper" ? localSetup.whisperReady : localSetup.sensevoiceReady;
		if (alreadyReady) {
			setSetup(localSetup);
			setDownloading(false);
			onNext();
			return;
		}
		const result = await window.fold.downloadVoicePack(localEngine);
		setDownloading(false);
		if (!result.ok) {
			setError(result.error);
			return;
		}
		setSetup(await window.fold.getVoiceSetup());
		onNext();
	}

	return (
		<OnboardingShell
			step="voice-pack"
			onBack={onBack}
			left={
				<>
					<h1 className="fold-onboarding-title">让知更听懂你的意思</h1>
					<p className="fold-onboarding-sub">
						智能转写可以理解改口、当前场景和专有名词；也可以选择完全离线的基础转写。
					</p>
					<div className="fold-onboarding-voice-difference">
						<span>免费版</span>
						<p>把声音变成文字</p>
						<span>知更智能</span>
						<p>把意思变成可以直接发送的表达</p>
					</div>
					{error ? <p className="fold-onboarding-error">{error}</p> : null}
				</>
			}
			right={
				<div className="fold-onboarding-voice-options">
					<button
						type="button"
						className={`fold-onboarding-voice-option is-smart${choice === "smart" ? " is-selected" : ""}`}
						onClick={() => smartAvailable && setChoice("smart")}
						disabled={!smartAvailable}
					>
						<div className="fold-onboarding-voice-option-head">
							<span className="fold-onboarding-voice-option-icon"><Sparkles size={17} /></span>
							<div>
								<strong>知更智能转写</strong>
								<small>{smartMeta}</small>
							</div>
							<span className="fold-onboarding-voice-recommend">推荐</span>
							<span className="fold-onboarding-voice-radio">{choice === "smart" ? <Check size={13} /> : null}</span>
						</div>
						<div className="fold-onboarding-voice-tags">
							<span>听懂改口</span>
							<span>结合当前 App</span>
							<span>记住专有名词</span>
						</div>
						<p>无需下载，语音会发送到云端处理。</p>
					</button>

					<button
						type="button"
						className={`fold-onboarding-voice-option${choice === "local" ? " is-selected" : ""}`}
						onClick={() => setChoice("local")}
					>
						<div className="fold-onboarding-voice-option-head">
							<span className="fold-onboarding-voice-option-icon is-local"><ShieldCheck size={17} /></span>
							<div>
								<strong>离线基础转写</strong>
								<small>
									免费长期使用 · 约 {localEngine === "whisper" ? 470 : 230}MB
								</small>
							</div>
							<span className="fold-onboarding-voice-radio">{choice === "local" ? <Check size={13} /> : null}</span>
						</div>
						<div className="fold-onboarding-voice-tags is-local">
							<span>基础语音转文字</span>
							<span>完全离线</span>
							<span>无需联网</span>
						</div>
						<p>不包含智能整理、场景理解和智能代回。</p>
					</button>
					{choice === "local" ? (
						<div className="fold-onboarding-voice-engines">
							<button
								type="button"
								className={`fold-onboarding-voice-engine${localEngine === "sensevoice" ? " is-selected" : ""}`}
								onClick={() => setLocalEngine("sensevoice")}
							>
								<strong>阿里 SenseVoice</strong>
								<span>中文更准 · 约 230MB</span>
							</button>
							<button
								type="button"
								className={`fold-onboarding-voice-engine${localEngine === "whisper" ? " is-selected" : ""}`}
								onClick={() => setLocalEngine("whisper")}
							>
								<strong>Whisper</strong>
								<span>多语种 · 约 470MB</span>
							</button>
						</div>
					) : null}

					<p className="fold-onboarding-voice-switch-note">
						之后可随时在「设置 → 语音输入」中切换。
					</p>
				</div>
			}
			footer={
				<OnboardingPrimaryBtn
					onClick={() =>
						void (choice === "smart" ? continueWithSmart() : downloadAndContinue())
					}
					disabled={!setup || !config || downloading || (choice === "smart" && !smartAvailable)}
				>
					{choice === "smart" ? (
						setup?.planTier === "free" ? "开始免费体验" : "使用智能转写"
					) : downloading ? (
						"正在下载…"
					) : (
						<span className="inline-flex items-center gap-1.5">
							<Download size={14} /> 下载离线包并继续
						</span>
					)}
				</OnboardingPrimaryBtn>
			}
		/>
	);
}
