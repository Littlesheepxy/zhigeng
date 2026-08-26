import type { Metadata } from "next";
import { Check } from "lucide-react";
import { PageIntro } from "../components/PageSections";
import { macDownloadFilename, macDownloadUrl } from "../lib/site";

export const metadata: Metadata = {
	title: "定价",
	description: "知更 macOS 个人版：先下载用起来，再谈更多。",
	alternates: { canonical: "/pricing" },
};

const benefits = [
	"懂得改口、口头语与表达意图的语音输入",
	"根据当前应用整理格式与语气",
	"简单事项直接执行，并连接本地 Codex、Claude Code、WorkBuddy",
	"本地保存的个人习惯、人物与项目",
	"可查看、可关闭、可删除的本地信息来源",
];

const faqs = [
	{
		question: "现在怎么安装？",
		answer: "打开 zhigeng.app 下载 macOS Apple Silicon 安装包。已签名公证，下载后直接打开。",
	},
	{
		question: "是否需要一直联网？",
		answer: "部分语音识别与生成能力需要联网；你的本地工作信息与个人画像不会因此成为公开数据。",
	},
	{
		question: "Windows 和移动端什么时候支持？",
		answer: "当前先把 macOS 体验做好。其他平台有明确计划后，会在博客公布。",
	},
];

export default function PricingPage() {
	const faqJsonLd = {
		"@context": "https://schema.org",
		"@type": "FAQPage",
		mainEntity: faqs.map((faq) => ({
			"@type": "Question",
			name: faq.question,
			acceptedAnswer: {
				"@type": "Answer",
				text: faq.answer,
			},
		})),
	};

	return (
		<main className="zg-subpage">
			<script
				type="application/ld+json"
				dangerouslySetInnerHTML={{ __html: JSON.stringify(faqJsonLd).replace(/</g, "\\u003c") }}
			/>
			<PageIntro eyebrow="定价" title="先真正帮你省下时间，再谈更多。">
				<p>macOS 个人版可直接下载。先把输入、代回、执行和本地记忆用起来。</p>
			</PageIntro>

			<section className="zg-price-card">
				<div>
					<span>个人版 · macOS</span>
					<h2>现在可下载</h2>
					<p>面向每天需要写消息、邮件、文档，也希望少做重复操作的人。</p>
				</div>
				<ul>
					{benefits.map((benefit) => (
						<li key={benefit}>
							<Check size={16} />
							{benefit}
						</li>
					))}
				</ul>
				<a className="zg-primary" href={macDownloadUrl} download={macDownloadFilename}>
					下载 macOS
				</a>
			</section>

			<section className="zg-faq">
				<span>常见问题</span>
				<h2>开始之前，你可能想知道</h2>
				<div>
					{faqs.map((faq) => (
						<details key={faq.question}>
							<summary>{faq.question}</summary>
							<p>{faq.answer}</p>
						</details>
					))}
				</div>
			</section>
		</main>
	);
}
