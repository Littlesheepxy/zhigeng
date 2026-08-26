"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { Github } from "lucide-react";
import { macDownloadFilename, macDownloadUrl, sourceUrl } from "../lib/site";

const navigation = [
	{ href: "/about", label: "关于知更" },
	{ href: "/blog", label: "博客" },
	{ href: "/pricing", label: "定价" },
	{ href: sourceUrl, label: "源码", external: true },
];

export function SiteHeader() {
	const [isScrolled, setIsScrolled] = useState(false);

	useEffect(() => {
		const updateHeader = () => setIsScrolled(window.scrollY > 40);
		updateHeader();
		window.addEventListener("scroll", updateHeader, { passive: true });
		return () => window.removeEventListener("scroll", updateHeader);
	}, []);

	return (
		<header className={`zg-nav${isScrolled ? " zg-nav-scrolled" : ""}`} aria-label="主导航">
			<Link className="zg-brand" href="/" aria-label="知更首页">
				<Image src="/zhigeng-mark.png" alt="" width={44} height={44} priority />
				<span>知更</span>
			</Link>
			<nav className="zg-nav-links" aria-label="页面导航">
				{navigation.map((item) =>
					"external" in item && item.external ? (
						<a href={item.href} key={item.href} target="_blank" rel="noreferrer" className="zg-nav-source">
							<Github size={16} aria-hidden="true" />
							{item.label}
						</a>
					) : (
						<Link href={item.href} key={item.href}>
							{item.label}
						</Link>
					),
				)}
			</nav>
			<a className="zg-nav-cta" href={macDownloadUrl} download={macDownloadFilename}>
				下载 macOS
			</a>
		</header>
	);
}
