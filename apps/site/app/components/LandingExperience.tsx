"use client";

import { useEffect, useState } from "react";
import { motion, useReducedMotion } from "framer-motion";
import type { Transition } from "framer-motion";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { HeroHighlight, Highlight } from "./HeroHighlight";
import { FeatureShowcase } from "./FeatureModules";
import { Differentiators } from "./Differentiators";
import { VoicePill, type VoicePillState } from "./VoicePill";
import { macDownloadFilename, macDownloadUrl } from "../lib/site";

const heroSentence = "知更，知你所言，才更懂你意。";
const heroSentenceParts = [
	{ text: "知更", className: "zg-hero-brand" },
	{ text: "，知你所言，才", className: "" },
	{ text: "更懂你意", className: "zg-hero-emphasis" },
	{ text: "。", className: "" },
];

const fadeUp = {
	hidden: { opacity: 0.001, y: 24 },
	visible: { opacity: 1, y: 0 },
};

export function LandingExperience() {
	const reduceMotion = useReducedMotion();
	const transition: Transition = reduceMotion ? { duration: 0 } : { duration: 0.7, ease: "easeOut" };

	return (
		<main className="zg-page">
			<section className="zg-hero" id="top">
				<motion.div
					className="zg-hero-copy"
					initial="hidden"
					animate="visible"
					variants={fadeUp}
					transition={{ ...transition, delay: 0.08 }}
				>
					<HeroHighlight>
						<HeroTypewriter reduceMotion={Boolean(reduceMotion)} />
						<p className="zg-hero-message">
							<strong>懂你正在做什么的语音输入。</strong>
							<span>你说一句，它写好；说到，也能做到。</span>
						</p>
						<div className="zg-actions" id="download">
							<a className="zg-primary" href={macDownloadUrl} download={macDownloadFilename}>
								下载 macOS
								<ArrowRight size={18} />
							</a>
							<a className="zg-secondary" href="#speak">
								看看它怎么做
							</a>
						</div>
					</HeroHighlight>
				</motion.div>
				<HeroProductMoment reduceMotion={Boolean(reduceMotion)} />
			</section>

			<FeatureShowcase />
			<Differentiators />

			<motion.section className="zg-final-cta" initial="hidden" whileInView="visible" viewport={{ once: true, amount: 0.4 }} variants={fadeUp}>
				<span>从一句话开始</span>
				<h2>把手从键盘上拿开，<br />让想法直接抵达结果。</h2>
				<p>下载 macOS Apple Silicon 版，装好就能用。你说一句，它写好；说到，也能做到。</p>
				<div className="zg-actions">
					<a className="zg-primary" href={macDownloadUrl} download={macDownloadFilename}>
						下载 macOS
						<ArrowRight size={18} />
					</a>
					<Link className="zg-secondary" href="/about">
						为什么做知更
					</Link>
				</div>
			</motion.section>
		</main>
	);
}

function HeroProductMoment({ reduceMotion }: { reduceMotion: boolean }) {
	const [state, setState] = useState<VoicePillState>(reduceMotion ? "done" : "listening");

	useEffect(() => {
		if (reduceMotion) return;
		const processing = window.setTimeout(() => setState("processing"), 2800);
		const done = window.setTimeout(() => setState("done"), 3900);
		return () => {
			window.clearTimeout(processing);
			window.clearTimeout(done);
		};
	}, [reduceMotion]);

	return (
		<motion.div
			className="zg-hero-product"
			initial={{ opacity: 0, y: 30 }}
			animate={{ opacity: 1, y: 0 }}
			transition={{ duration: reduceMotion ? 0 : 0.9, delay: 0.8, ease: "easeOut" }}
			aria-label="知更把自然口述整理成可直接发送的文字"
		>
			<div className="zg-hero-product-mist" aria-hidden="true" />
			<div className="zg-hero-context-hint" aria-hidden="true">
				<img src="/brand/icons/feishu.svg" alt="" width={14} height={14} />
				<span>检测到你在飞书 · 项目群</span>
			</div>
			<p className="zg-hero-utterance">“嗯……评审改到周三，不对，周四下午。把最新设计稿也带上。”</p>
			<div className="zg-hero-pill">
				<VoicePill state={state} />
			</div>
			<motion.p
				className="zg-hero-result"
				animate={{ opacity: state === "done" ? 1 : 0.24, y: state === "done" ? 0 : 8 }}
				transition={{ duration: 0.45 }}
			>
				设计评审改到周四下午，我会附上最新设计稿。
			</motion.p>
		</motion.div>
	);
}

function HeroTypewriter({ reduceMotion }: { reduceMotion: boolean }) {
	const [charCount, setCharCount] = useState(reduceMotion ? heroSentence.length : 0);

	useEffect(() => {
		if (reduceMotion) {
			setCharCount(heroSentence.length);
			return;
		}

		if (charCount >= heroSentence.length) return;

		const timeout = window.setTimeout(
			() => setCharCount((value) => value + 1),
			charCount === 0 ? 420 : 82,
		);

		return () => window.clearTimeout(timeout);
	}, [charCount, reduceMotion]);

	let remainingCharacters = charCount;
	const isComplete = charCount >= heroSentence.length;

	return (
		<h1 aria-label={heroSentence}>
			<span aria-hidden="true">
				{heroSentenceParts.map((part) => {
					const visibleText = part.text.slice(0, Math.max(0, remainingCharacters));
					remainingCharacters -= part.text.length;
					if (part.className === "zg-hero-emphasis") {
						return (
							<Highlight active={isComplete} key={part.text} reduceMotion={reduceMotion}>
								{visibleText}
							</Highlight>
						);
					}
					return (
						<span className={part.className} key={part.text}>
							{visibleText}
						</span>
					);
				})}
				<span className="zg-typewriter-cursor" aria-hidden="true" />
			</span>
		</h1>
	);
}
