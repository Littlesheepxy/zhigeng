"use client";

import { motion, useReducedMotion } from "framer-motion";

const items = [
	{
		title: "三种快捷键",
		body: "右 ⌘ 短按整理输入，长按情境代回。⌥ Space 把复杂事交给本机 Agent。",
	},
	{
		title: "不抢焦点",
		body: "Menu Bar 常驻 + 轻量 Overlay。不用再开一个聊天窗口解释上下文。",
	},
	{
		title: "多草案代回",
		body: "读懂当前对话后给出几条可选回复，你点一条再插入真实输入框。",
	},
	{
		title: "先确认再执行",
		body: "授权与对外发送前会停一下。取消即停，不为「自动化」牺牲可控。",
	},
] as const;

const fadeUp = {
	hidden: { opacity: 0, y: 20 },
	visible: { opacity: 1, y: 0, transition: { duration: 0.65, ease: "easeOut" as const } },
};

/** 首页已有五大模块未写透的差异点：快捷键心智、形态、代回、HITL */
export function Differentiators() {
	const reduce = Boolean(useReducedMotion());

	return (
		<motion.section
			className="zg-diff"
			aria-label="上手方式与差异"
			initial={reduce ? false : "hidden"}
			whileInView="visible"
			viewport={{ once: true, amount: 0.35 }}
			variants={fadeUp}
		>
			<p className="zg-diff-eyebrow">上手之后你会感到的不同</p>
			<ul className="zg-diff-list">
				{items.map((item) => (
					<li key={item.title}>
						<strong>{item.title}</strong>
						<span>{item.body}</span>
					</li>
				))}
			</ul>
		</motion.section>
	);
}
