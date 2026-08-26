import type { ReactNode } from "react";
import { ArrowRight } from "lucide-react";
import { macDownloadUrl } from "../lib/site";

export function PageIntro({
	eyebrow,
	title,
	children,
}: {
	eyebrow: string;
	title: string;
	children: ReactNode;
}) {
	return (
		<header className="zg-page-intro">
			<span>{eyebrow}</span>
			<h1>{title}</h1>
			<div>{children}</div>
		</header>
	);
}

export function PageCta({
	title = "你说一句，它写好；说到，也能做到。",
}: {
	title?: string;
}) {
	return (
		<section className="zg-page-cta">
			<h2>{title}</h2>
			<p>下载 macOS Apple Silicon 版，装好就能用。</p>
			<a className="zg-primary" href={macDownloadUrl}>
				下载 macOS
				<ArrowRight size={18} />
			</a>
		</section>
	);
}
