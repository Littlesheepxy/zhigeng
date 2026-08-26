"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { motion, useInView, useReducedMotion } from "framer-motion";
import {
	Check,
	Clock3,
	Command,
	FolderKanban,
	Lock,
	Mic,
	Sparkles,
} from "lucide-react";
import { VoicePill } from "./VoicePill";

const fadeUp = {
	hidden: { opacity: 0, y: 26 },
	visible: { opacity: 1, y: 0, transition: { duration: 0.7, ease: "easeOut" as const } },
};

/** 进入视口后按时间表推进阶段；reduce motion 时直接到终态 */
function usePhases(active: boolean, times: readonly number[], skip: boolean) {
	const [phase, setPhase] = useState(skip ? times.length : 0);
	useEffect(() => {
		if (skip) {
			setPhase(times.length);
			return;
		}
		if (!active) return;
		const timers = times.map((ms, i) => window.setTimeout(() => setPhase(i + 1), ms));
		return () => timers.forEach((t) => window.clearTimeout(t));
	}, [active, skip, times]);
	return phase;
}

/** 标题逐字浮现，进入视口播一次；reduce motion 时直接显示 */
function RevealHeading({ text }: { text: string }) {
	const reduce = Boolean(useReducedMotion());
	if (reduce) return <h2>{text}</h2>;
	return (
		<h2 aria-label={text}>
			<span aria-hidden="true">
				{Array.from(text).map((char, i) => (
					<motion.span
						key={i}
						className="zg-heading-char"
						initial={{ opacity: 0, y: 18, filter: "blur(6px)" }}
						whileInView={{ opacity: 1, y: 0, filter: "blur(0px)" }}
						viewport={{ once: true, amount: 0.6 }}
						transition={{ duration: 0.5, delay: 0.024 * i, ease: "easeOut" }}
					>
						{char}
					</motion.span>
				))}
			</span>
		</h2>
	);
}

function FeatureCopy({
	index,
	title,
	lead,
}: {
	index: string;
	title: string;
	lead: string;
}) {
	return (
		<motion.div
			className="zg-feature-copy"
			initial="hidden"
			whileInView="visible"
			viewport={{ once: true, amount: 0.4 }}
			variants={fadeUp}
		>
			<span className="zg-feature-index">{index}</span>
			<RevealHeading text={title} />
			<p>{lead}</p>
		</motion.div>
	);
}

/* ── 01 语音输入 ─────────────────────────────── */

const speakTokens = [
	{ t: "嗯，", kind: "cut" },
	{ t: "那个…", kind: "cut" },
	{ t: "帮我跟设计组说一下，", kind: "keep" },
	{ t: "呃，", kind: "cut" },
	{ t: "评审改到周三", kind: "slip" },
	{ t: "不对，", kind: "cut" },
	{ t: "是周四下午，", kind: "keep" },
	{ t: "把最新的设计稿链接带上。", kind: "keep" },
] as const;

// 1 听写打字 → 2 清理口头语 → 3 转写中(loading) → 4 完成(对勾)+插入 → 5 徽标
const speakPhaseTimes = [300, 3600, 4500, 5600, 6300] as const;

const speakFullText = speakTokens.map((token) => token.t).join("");
const speakOffsets = speakTokens.reduce<number[]>((acc, token, i) => {
	acc.push(i === 0 ? 0 : acc[i - 1]! + speakTokens[i - 1]!.t.length);
	return acc;
}, []);

const speakTargets = [
	{
		id: "feishu",
		logo: "/brand/icons/feishu.svg",
		label: "飞书",
		scene: "项目群 · 输入框",
		smart: "设计评审改到周四下午，麻烦大家留意；最新的设计稿链接我放在下面。",
		badge: "已按飞书语气插入",
	},
	{
		id: "wechat",
		logo: "/brand/icons/wechat.svg",
		label: "微信",
		scene: "工作群 · 输入框",
		smart: "评审改到周四下午啦，最新设计稿链接我一起带上。",
		badge: "已按微信语气插入",
	},
	{
		id: "gmail",
		logo: "/brand/icons/gmail.svg",
		label: "邮件",
		scene: "Gmail · 草稿",
		smart:
			"Hi team,\n\nThe design review has been moved to Thursday afternoon. I’ll attach the latest design draft.\n\nBest regards",
		subject: "Design review → Thursday afternoon",
		to: "design-team@",
		badge: "已按邮件语气插入",
	},
] as const;

const speakMinimalResult =
	"帮我跟设计组说一下，评审改到周三，不对，是周四下午，把最新的设计稿链接带上。";

function speakTokenClass(
	kind: (typeof speakTokens)[number]["kind"],
	cleaned: boolean,
	smartMode: boolean,
) {
	if (!cleaned || kind === "keep") return "zg-token";
	// 仅去语气词：只划掉口头禅；改口（slip）留给智能整理
	if (!smartMode && kind === "slip") return "zg-token";
	if (kind === "slip") return "zg-token zg-token-cut zg-token-slip";
	return "zg-token zg-token-cut";
}

function SpeakDemo() {
	const reduce = Boolean(useReducedMotion());
	const ref = useRef<HTMLDivElement | null>(null);
	const inView = useInView(ref, { once: true, amount: 0.45 });
	const phase = usePhases(inView, speakPhaseTimes, reduce);
	const [targetId, setTargetId] = useState<(typeof speakTargets)[number]["id"]>("feishu");
	const [smartMode, setSmartMode] = useState(true);
	const target = speakTargets.find((item) => item.id === targetId) ?? speakTargets[0];
	const result = smartMode ? target.smart : speakMinimalResult;
	const badge = smartMode ? target.badge : "已插入 · 只去掉口头禅";
	const cleaned = phase >= 2;
	const pillState =
		phase === 0 ? "hidden" : phase <= 2 ? "listening" : phase === 3 ? "processing" : "done";
	const typed = useTypewriter(speakFullText, phase >= 1, reduce, 62);
	const typing = phase >= 1 && typed.length < speakFullText.length;

	return (
		<div className="zg-demo-card zg-demo-card--speak" ref={ref}>
			<div className="zg-speak-intent">
				<span className="zg-reply-shortcut">
					<Command size={13} />
					<span className="zg-speak-tap">短按</span>
				</span>
				<div>
					<small>短按右 ⌘ · 转写</small>
					<p>口述进当前输入框；整理程度可用开关切换。</p>
				</div>
			</div>
			<p className="zg-speak-raw" aria-label="原始口述逐字出现，口头语与改口被清理">
				{speakTokens.map((token, i) => {
					const visible = Math.max(
						0,
						Math.min(token.t.length, typed.length - speakOffsets[i]!),
					);
					if (visible === 0) return null;
					return (
						<span key={i} className={speakTokenClass(token.kind, cleaned, smartMode)}>
							{token.t.slice(0, visible)}
						</span>
					);
				})}
				{typing && <span className="zg-typewriter-cursor" aria-hidden="true" />}
			</p>
			<div className="zg-speak-pill-slot">
				<VoicePill state={pillState} appLogo={target.logo} />
			</div>
			<div className="zg-speak-controls">
				<div className="zg-app-tabs" role="tablist" aria-label="插入目标">
					{speakTargets.map((item) => (
						<button
							key={item.id}
							type="button"
							role="tab"
							aria-selected={targetId === item.id}
							className={targetId === item.id ? "is-active" : ""}
							onClick={() => setTargetId(item.id)}
						>
							<img src={item.logo} alt="" width={14} height={14} />
							{item.label}
						</button>
					))}
				</div>
				<div className="zg-speak-mode">
					<span className={!smartMode ? "is-on" : ""}>仅去语气词</span>
					<button
						type="button"
						role="switch"
						aria-checked={smartMode}
						aria-label="智能整理：按应用调语气"
						className={`zg-speak-switch${smartMode ? " is-on" : ""}`}
						onClick={() => setSmartMode((value) => !value)}
					>
						<span />
					</button>
					<span className={smartMode ? "is-on" : ""}>智能整理</span>
				</div>
			</div>
			<motion.div
				className={`zg-speak-compose${target.id === "gmail" && smartMode ? " zg-speak-compose--mail" : ""}`}
				initial={{ opacity: 0, y: 14 }}
				animate={phase >= 1 ? { opacity: 1, y: 0 } : {}}
				transition={{ duration: 0.45 }}
			>
				<div className="zg-speak-compose-head">
					<span className="zg-speak-compose-logo">
						<img src={target.logo} alt="" width={22} height={22} />
					</span>
					<div>
						<strong>{target.label}</strong>
						<span className="zg-speak-compose-meta">
							{smartMode ? target.scene : "仅去语气词 · 不跟应用走"}
						</span>
					</div>
				</div>
				<div className="zg-speak-compose-body">
					{target.id === "gmail" && smartMode && "to" in target ? (
						<div className="zg-mail-headers" aria-hidden="true">
							<div>
								<span>To</span>
								<em>{target.to}</em>
							</div>
							<div>
								<span>Subject</span>
								<em>{target.subject}</em>
							</div>
						</div>
					) : null}
					<motion.p
						key={`${target.id}-${smartMode ? "smart" : "minimal"}`}
						initial={{ opacity: 0 }}
						animate={phase >= 4 ? { opacity: 1 } : { opacity: 0 }}
						transition={{ duration: 0.35 }}
						className={target.id === "gmail" && smartMode ? "zg-mail-body" : undefined}
					>
						{result}
					</motion.p>
					{!(target.id === "gmail" && smartMode) ? (
						<div className="zg-speak-compose-bar" aria-hidden="true">
							<span>＋</span>
							<span>Aa</span>
							<span>☺</span>
							<button type="button" tabIndex={-1} disabled>
								发送
							</button>
						</div>
					) : (
						<div className="zg-mail-actions" aria-hidden="true">
							<button type="button" tabIndex={-1} disabled>
								Send
							</button>
						</div>
					)}
				</div>
				<motion.span
					className="zg-done-badge"
					initial={{ opacity: 0 }}
					animate={phase >= 5 ? { opacity: 1 } : {}}
					transition={{ duration: 0.3 }}
				>
					<Check size={13} />
					{badge}
				</motion.span>
			</motion.div>
			<p className="zg-demo-footnote">
				智能整理：改口会修好，并按飞书 / 微信 / 邮件调语气。仅去语气词：只去掉嗯呃，原话结构不动。
			</p>
		</div>
	);
}

/* ── 02 Context ─────────────────────────────── */

const contextChips = [
	{ logo: "/zhigeng-mark.png", label: "当前窗口 · Cursor「知更 iOS」" },
	{ logo: "/brand/icons/feishu.svg", label: "最近对话 · 飞书 · Alex" },
	{ logo: "/brand/icons/chrome.svg", label: "打开的网页 · Figma 原型" },
	{ logo: "/brand/icons/clipboard.svg", label: "剪贴板 · 版本规划" },
	{ logo: "/brand/icons/finder.png", label: "项目文件 · 知更 iOS Deck" },
	{ logo: "/zhigeng-mark.png", label: "人名 · Alex" },
	{ logo: "/zhigeng-mark.png", label: "你的表达习惯" },
] as const;

const contextResultText = "Alex，知更 iOS 方案今天定稿，晚点发你终版。";

/** 触发后逐字打出文本，reduce motion 时直接显示全文 */
function useTypewriter(text: string, active: boolean, skip: boolean, speed = 42) {
	const [count, setCount] = useState(skip ? text.length : 0);
	useEffect(() => {
		if (skip) {
			setCount(text.length);
			return;
		}
		if (!active || count >= text.length) return;
		const timeout = window.setTimeout(() => setCount((c) => c + 1), speed);
		return () => window.clearTimeout(timeout);
	}, [active, count, skip, speed, text.length]);
	return text.slice(0, count);
}

const contextPhaseTimes = [800, 1600] as const;

function ContextDemo() {
	const reduce = Boolean(useReducedMotion());
	const ref = useRef<HTMLDivElement | null>(null);
	const inView = useInView(ref, { once: true, amount: 0.4 });
	const phase = usePhases(inView, contextPhaseTimes, reduce);
	const [cardOpen, setCardOpen] = useState(false);

	return (
		<div className="zg-demo-card" ref={ref}>
			<div className="zg-context-chips" aria-label="知更读取的 Context 来源">
				{contextChips.map((chip, i) => (
					<motion.span
						key={chip.label}
						initial={{ opacity: 0, y: 12 }}
						animate={inView || reduce ? { opacity: 1, y: 0 } : {}}
						transition={{ delay: 0.1 * i, duration: 0.4 }}
					>
						<img src={chip.logo} alt="" width={16} height={16} />
						{chip.label}
					</motion.span>
				))}
			</div>
			{(phase >= 1 || reduce) && (
				<motion.div
					className="zg-context-guess"
					initial={{ opacity: 0, y: 8 }}
					animate={{ opacity: 1, y: 0 }}
					transition={{ duration: 0.35 }}
				>
					<span className="zg-context-guess-label">
						<Sparkles size={13} />
						猜你在做
					</span>
					<p>
						你在 Cursor 里推进<strong>知更 iOS</strong>方案，准备跟 Alex 同步定稿。
					</p>
				</motion.div>
			)}
			{(phase >= 2 || reduce) && (
				<>
					<motion.button
						type="button"
						className="zg-aha-notification"
						initial={{ opacity: 0, y: 10 }}
						animate={{ opacity: 1, y: 0 }}
						transition={{ duration: 0.4 }}
						onClick={() => setCardOpen(true)}
						aria-expanded={cardOpen}
						aria-controls="zg-aha-popup"
					>
						<div className="zg-aha-notification-head">
							<img src="/zhigeng-mark.png" alt="" width={18} height={18} />
							<strong>知更 猜你想做</strong>
							<span className="zg-aha-notification-time">现在</span>
						</div>
						<p>
							给 Alex 同步定稿 · 点
							<span className="zg-aha-look">「看看」</span>
							展开
						</p>
					</motion.button>
					{cardOpen && (
						<motion.div
							id="zg-aha-popup"
							className="zg-aha-popup"
							role="dialog"
							aria-label="主动建议"
							initial={reduce ? false : { opacity: 0, y: 12, scale: 0.98 }}
							animate={{ opacity: 1, y: 0, scale: 1 }}
							transition={{ duration: 0.3 }}
						>
							<header>
								<span>
									<Sparkles size={14} />
									主动建议
								</span>
								<button type="button" onClick={() => setCardOpen(false)} aria-label="关闭">
									关闭
								</button>
							</header>
							<strong>给 Alex 同步定稿</strong>
							<p>{contextResultText}</p>
							<small>只建议，不擅自发送 · 演示</small>
						</motion.div>
					)}
				</>
			)}
			{(phase >= 2 || reduce) && (
				<motion.p
					className="zg-context-foot"
					initial={{ opacity: 0 }}
					animate={{ opacity: 1 }}
					transition={{ delay: 0.15, duration: 0.35 }}
				>
					你开口时，会写成「{contextResultText}」——一条可用文字，不是多选。
					{" "}
					<Link href="/privacy" className="zg-privacy-link">
						<Lock size={12} />
						本地优先
					</Link>
				</motion.p>
			)}
		</div>
	);
}

/* ── 03 情境代回 ─────────────────────────────── */

const replyApps = [
	{
		id: "feishu",
		logo: "/brand/icons/feishu.svg",
		label: "飞书",
		scene: "工作 IM · 知更 iOS 群",
		drafts: [
			{ id: "a", tone: "直接", text: "知更 iOS 方案今天定稿，最终 Deck 周三前发大家。" },
			{ id: "b", tone: "带结论", text: "方案已定稿。Deck 周三前同步，今天的决策我也整理好了。" },
			{ id: "c", tone: "轻松", text: "iOS 方案定了，Deck 周三前发，今日结论一并附上。" },
		],
	},
	{
		id: "wechat",
		logo: "/brand/icons/wechat.svg",
		label: "微信",
		scene: "熟人沟通 · 王姐",
		drafts: [
			{ id: "a", tone: "口语", text: "王姐，知更 iOS 定稿啦，Deck 周三前发你。" },
			{ id: "b", tone: "完整", text: "王姐，知更 iOS 方案定稿了，最终版周三前发，今天聊的重点我也整理好了。" },
			{ id: "c", tone: "简短", text: "王姐，定稿了，Deck 周三前发你～" },
		],
	},
	{
		id: "gmail",
		logo: "/brand/icons/gmail.svg",
		label: "邮件",
		scene: "正式邮件 · Sarah",
		drafts: [
			{
				id: "a",
				tone: "正式",
				subject: "Zhigeng iOS plan finalized",
				text: "Hi Sarah,\n\nThe Zhigeng iOS plan is now finalized. I’ll send the final deck by Wednesday.\n\nBest regards",
			},
			{
				id: "b",
				tone: "简洁",
				subject: "iOS plan — deck by Wed",
				text: "Hi Sarah,\n\niOS plan is set. Deck by Wednesday.\n\nThanks",
			},
			{
				id: "c",
				tone: "带上下文",
				subject: "Zhigeng iOS — final deck + today’s decisions",
				text: "Hi Sarah,\n\nThe Zhigeng iOS plan is finalized. I’ll send the final deck by Wednesday, with a short summary of today’s decisions.\n\nBest regards",
			},
		],
	},
] as const;

const replyPhaseTimes = [600, 1500, 2400, 3200] as const;

const replyStep = (delay: number) => ({
	hidden: { opacity: 0, y: 12 },
	visible: { opacity: 1, y: 0, transition: { delay, duration: 0.4 } },
});

function ReplyDemo() {
	const reduce = Boolean(useReducedMotion());
	const ref = useRef<HTMLDivElement | null>(null);
	const inView = useInView(ref, { once: true, amount: 0.35 });
	const [appId, setAppId] = useState<(typeof replyApps)[number]["id"]>("feishu");
	const [selected, setSelected] = useState<string | null>(reduce ? "a" : null);
	const phase = usePhases(inView, replyPhaseTimes, reduce);
	const app = replyApps.find((item) => item.id === appId) ?? replyApps[0];

	useEffect(() => {
		setSelected(null);
	}, [appId]);

	useEffect(() => {
		if (phase >= 3 && !selected) setSelected("a");
	}, [phase, selected]);

	return (
		<div className="zg-demo-card zg-reply-demo" ref={ref}>
			<motion.div
				className="zg-reply-intent"
				initial={reduce ? false : "hidden"}
				animate={inView || reduce ? "visible" : "hidden"}
				variants={replyStep(0)}
			>
				<span className="zg-reply-shortcut">
					<Command size={13} />
					<span className="zg-speak-tap">长按</span>
				</span>
				<div>
					<small>长按右 ⌘ · 代回</small>
					<p>“跟对方说知更 iOS 方案定稿了，Deck 周三前发。”</p>
				</div>
			</motion.div>

			{phase >= 1 && (
				<div className="zg-reply-targets">
					<div className="zg-app-tabs" role="tablist" aria-label="代回所在应用">
						{replyApps.map((item) => (
							<button
								key={item.id}
								type="button"
								role="tab"
								aria-selected={appId === item.id}
								className={appId === item.id ? "is-active" : ""}
								onClick={() => setAppId(item.id)}
							>
								<img src={item.logo} alt="" width={14} height={14} />
								{item.label}
							</button>
						))}
					</div>
					<p className="zg-reply-scene">
						<img src={app.logo} alt="" width={16} height={16} />
						<span>{app.scene}</span>
					</p>
				</div>
			)}

			<motion.div
				className="zg-reply-drafts"
				key={app.id}
				initial={reduce ? false : "hidden"}
				animate={inView || reduce ? "visible" : "hidden"}
			>
				{app.drafts.map((draft, i) => (
					<motion.button
						key={`${app.id}-${draft.id}`}
						type="button"
						className={`zg-reply-draft${selected === draft.id ? " is-selected" : ""}`}
						variants={replyStep(0.15 + i * 0.12)}
						onClick={() => setSelected(draft.id)}
						disabled={phase < 2}
					>
						<span className="zg-reply-draft-tone">{draft.tone}</span>
						{"subject" in draft ? (
							<span className="zg-reply-draft-subject">Subject · {draft.subject}</span>
						) : null}
						<p className={"subject" in draft ? "zg-mail-body" : undefined}>{draft.text}</p>
						{selected === draft.id && (
							<motion.span
								className="zg-reply-draft-check"
								initial={{ scale: 0 }}
								animate={{ scale: 1 }}
								transition={{ duration: 0.2 }}
							>
								<Check size={14} />
							</motion.span>
						)}
					</motion.button>
				))}
			</motion.div>

			{phase >= 3 && selected && (
				<motion.div
					className="zg-reply-inserted"
					initial={{ opacity: 0, y: 10 }}
					animate={{ opacity: 1, y: 0 }}
					transition={{ duration: 0.4 }}
				>
					<Check size={15} />
					已插入 {app.label} 输入框，可继续编辑或发送
				</motion.div>
			)}

			<p className="zg-demo-footnote">
				代回：读当前对话，给出多条草案；换到飞书 / 微信 / 邮件，语气跟着变。写是一条整理好的文字，不是多选。
			</p>
		</div>
	);
}

/* ── 04 Agent 执行 ─────────────────────────────── */

const agentRoutes = [
	{ logo: "/zhigeng-mark.png", label: "知更快捷执行", meta: "消息 · 文件 · 授权后执行", direct: true },
	{ logo: "/brand/icons/codex.svg", label: "Codex", meta: "本地已连接" },
	{ logo: "/brand/icons/claude.svg", label: "Claude Code", meta: "本地已连接" },
	{ logo: "/brand/icons/workbuddy.png", label: "WorkBuddy", meta: "本地已连接" },
];

const agentPhaseTimes = [600, 1500, 2600, 3600] as const;

function AgentSection() {
	const reduce = Boolean(useReducedMotion());
	const ref = useRef<HTMLDivElement | null>(null);
	const inView = useInView(ref, { once: true, amount: 0.35 });
	const phase = usePhases(inView, agentPhaseTimes, reduce);

	return (
		<motion.section
			className="zg-agent"
			id="agent"
			aria-label="连接与执行"
			initial={reduce ? false : "hidden"}
			whileInView="visible"
			viewport={{ once: true, amount: 0.2 }}
			variants={fadeUp}
		>
			<div className="zg-agent-head">
				<span className="zg-feature-index">04 · 连接与执行</span>
				<RevealHeading text="接上你已经在用的 Agent" />
				<p>消息、整理文件等简单事项，知更在授权后直接完成；代码与复杂工作，交给本地 Codex、Claude Code 或 WorkBuddy，完成后通知你。</p>
			</div>
			<div ref={ref}>
				<div className="zg-agent-command">
					<Mic size={18} />
					<p>“让 Codex 把这个登录报错修好，跑完测试再告诉我。”</p>
				</div>
				<motion.div
					className="zg-agent-decision"
					initial={{ opacity: 0, y: 8 }}
					animate={phase >= 1 ? { opacity: 1, y: 0 } : {}}
				>
					<span>知更判断</span>
					<strong>代码任务 · 交给本地 Codex</strong>
				</motion.div>
				<ol className="zg-agent-routes">
					{agentRoutes.map((route, i) => {
						const selected = phase >= 2 && i === 1;
						return (
							<li key={route.label} className={selected ? "is-selected" : ""}>
								<span className={`zg-agent-mark${route.direct ? " is-zhigeng" : ""}`}>
									<img src={route.logo} alt="" width={20} height={20} />
								</span>
								<div>
									<strong>{route.label}</strong>
									<small>{route.meta}</small>
								</div>
								{selected && <Check size={15} aria-hidden="true" />}
							</li>
						);
					})}
				</ol>
				<motion.p
					className="zg-agent-done"
					initial={{ opacity: 0, y: 10 }}
					animate={phase >= agentPhaseTimes.length ? { opacity: 1, y: 0 } : {}}
					transition={{ duration: 0.4 }}
				>
					<Check size={15} />
					已交给本地 Codex · 完成后知更会通知你
				</motion.p>
			</div>
		</motion.section>
	);
}

/* ── 05 记忆与主动协助 ─────────────────────────────── */

const followUps = [
	{ person: "Sarah", task: "发送知更 iOS 最终 Deck", time: "周三前", status: "待发送" },
	{ person: "王姐", task: "确认采购报价", time: "今天 17:00", status: "待回复" },
	{ person: "知更 iOS", task: "完成方案定稿", time: "今天", status: "进行中" },
] as const;

const memoryItem = (delay: number) => ({
	hidden: { opacity: 0, y: 14 },
	visible: { opacity: 1, y: 0, transition: { delay, duration: 0.45 } },
});

function MemorySection() {
	const reduce = Boolean(useReducedMotion());

	return (
		<section className="zg-feature zg-feature-panel zg-feature--warm" id="memory" aria-label="记忆">
			<FeatureCopy
				index="05 · 记忆"
				title="越用，越懂你的工作方式"
				lead="不只记住你说过什么，也记得你在意谁、正在做什么、答应了什么。可从常用 AI 助手导入画像；使用中沉淀习惯。记忆留在本地，始终属于你。"
			/>
			<motion.div
				className="zg-memory-grid"
				initial={reduce ? false : "hidden"}
				whileInView="visible"
				viewport={{ once: true, amount: 0.3 }}
			>
				<motion.article
					className="zg-memory-entity zg-memory-entity--people"
					variants={memoryItem(0.15)}
				>
					<header className="zg-memory-heading">
						<small>人</small>
						<strong>重要的人与承诺</strong>
					</header>
					<ul className="zg-memory-people">
						<li>
							<img src="/brand/avatars/alex.jpg" alt="Alex" width={38} height={38} />
							<span>
								<strong>Alex</strong>
								<small>视觉设计 · 知更 iOS</small>
								<em>最近承诺 · 周三前给终版</em>
							</span>
						</li>
						<li>
							<img src="/brand/avatars/wang.jpg" alt="王姐" width={38} height={38} />
							<span>
								<strong>王姐</strong>
								<small>采购负责人 · 长期合作</small>
								<em>最近承诺 · 定稿后确认报价</em>
							</span>
						</li>
					</ul>
				</motion.article>
				<motion.article
					className="zg-memory-entity zg-memory-entity--things"
					variants={memoryItem(0.31)}
				>
					<header className="zg-memory-card-head">
						<span className="zg-memory-visual" aria-hidden="true">
							<FolderKanban size={22} />
						</span>
						<span className="zg-memory-heading">
							<small>事</small>
							<strong>知更 iOS · 定稿</strong>
						</span>
					</header>
					<dl className="zg-memory-facts">
						<div>
							<dt>状态</dt>
							<dd><span className="zg-memory-status" />方案已定稿</dd>
						</div>
						<div>
							<dt>截止</dt>
							<dd>周三下班前</dd>
						</div>
						<div>
							<dt>下一步</dt>
							<dd>整理决策并发送最终 Deck</dd>
						</div>
					</dl>
				</motion.article>
				<motion.article
					className="zg-memory-entity zg-memory-entity--self"
					variants={memoryItem(0.47)}
				>
					<header className="zg-memory-self-head">
						<img src="/brand/avatars/user.jpg" alt="你的头像" width={44} height={44} />
						<span className="zg-memory-heading">
							<small>我</small>
							<strong>你的表达习惯</strong>
						</span>
					</header>
					<p className="zg-memory-habits">短句 · 先结论 · 不用感叹号</p>
					<p className="zg-memory-import">
						<Sparkles size={14} aria-hidden="true" />
						已从 AI 助手导入 · 本地记忆
					</p>
				</motion.article>
			</motion.div>
			<motion.div
				className="zg-memory-followups"
				initial={reduce ? false : { opacity: 0, y: 14 }}
				whileInView={{ opacity: 1, y: 0 }}
				viewport={{ once: true, amount: 0.45 }}
				transition={{ delay: reduce ? 0 : 0.45, duration: 0.45 }}
			>
				<header>
					<div>
						<span className="zg-memory-followup-icon">
							<Clock3 size={15} />
						</span>
						<strong>最近需要跟进</strong>
					</div>
					<small>来自本地记忆</small>
				</header>
				<ul>
					{followUps.map((item) => (
						<li key={`${item.person}-${item.task}`}>
							<span>
								<b>{item.person}</b>
								{item.task}
							</span>
							<time>{item.time}</time>
							<em>{item.status}</em>
						</li>
					))}
				</ul>
			</motion.div>
		</section>
	);
}

/* ── 组合 ─────────────────────────────── */

export function FeatureShowcase() {
	return (
		<>
			<section className="zg-feature" id="speak" aria-label="语音输入">
				<FeatureCopy
					index="01 · 语音输入"
					title="一开口，就是可用的文字"
					lead="短按右 ⌘。不是逐字记录，而是写下你想说的话；可用开关在「智能整理」与「仅去语气词」之间切换。"
				/>
				<div className="zg-feature-demo">
					<SpeakDemo />
				</div>
			</section>

			<section className="zg-feature zg-feature-panel zg-feature--soft zg-feature--flip" id="context" aria-label="理解当前工作">
				<FeatureCopy
					index="02 · 理解当下"
					title="它知道你正在做什么"
					lead="先猜你在推进哪件事。高信心时用系统通知主动建议——只提醒，不执行。线索默认留在本地。"
				/>
				<div className="zg-feature-demo">
					<ContextDemo />
				</div>
			</section>

			<section className="zg-feature" id="reply" aria-label="情境代回">
				<FeatureCopy
					index="03 · 代回"
					title="读懂对话，给你几条可选回复"
					lead="长按右 ⌘。知更读当前对话，给出多条草案；飞书、微信、邮件语气不同，你选一条插入真实输入框。"
				/>
				<div className="zg-feature-demo">
					<ReplyDemo />
				</div>
			</section>

			<AgentSection />

			<MemorySection />

			<motion.section
				className="zg-recap"
				aria-label="知更能力总结"
				initial="hidden"
				whileInView="visible"
				viewport={{ once: true, amount: 0.5 }}
				variants={fadeUp}
			>
				<p>
					<span className="zg-line">听懂你说的，看懂你在做的，</span>
					<span className="zg-line">替你回、替你办，越用越懂你。</span>
				</p>
			</motion.section>
		</>
	);
}
