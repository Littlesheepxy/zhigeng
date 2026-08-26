import Image from "next/image";
import Link from "next/link";
import { sourceUrl } from "../lib/site";

const footerLinks = [
	{ href: "/about", label: "关于知更" },
	{ href: "/blog", label: "博客" },
	{ href: "/pricing", label: "定价" },
	{ href: "/#download", label: "下载 macOS" },
	{ href: sourceUrl, label: "源码", external: true },
	{ href: "/privacy", label: "隐私政策" },
	{ href: "/terms", label: "用户协议" },
];

export function SiteFooter() {
	return (
		<footer className="zg-footer">
			<div className="zg-footer-brand">
				<Link href="/" aria-label="知更首页">
					<Image src="/zhigeng-mark.png" alt="" width={38} height={38} />
					<strong>知更</strong>
				</Link>
				<p>知你所言，才更懂你意。</p>
			</div>
			<nav aria-label="页脚导航">
				{footerLinks.map((item) =>
					"external" in item && item.external ? (
						<a href={item.href} key={item.href} target="_blank" rel="noreferrer">
							{item.label}
						</a>
					) : (
						<Link href={item.href} key={item.href}>
							{item.label}
						</Link>
					),
				)}
			</nav>
			<p className="zg-footer-meta">
				© {new Date().getFullYear()} 知更 · 源码公开，
				<a href={sourceUrl} target="_blank" rel="noreferrer">
					PolyForm 非商用
				</a>
				{" · "}
				<a href="mailto:hello@zhigeng.app">hello@zhigeng.app</a>
			</p>
		</footer>
	);
}
