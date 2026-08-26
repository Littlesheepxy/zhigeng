"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { macDownloadUrl } from "../lib/site";

const navigation = [
	{ href: "/about", label: "关于知更" },
	{ href: "/blog", label: "博客" },
	{ href: "/pricing", label: "定价" },
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
				{navigation.map((item) => (
					<Link href={item.href} key={item.href}>
						{item.label}
					</Link>
				))}
			</nav>
			<a className="zg-nav-cta" href={macDownloadUrl}>
				下载 macOS
			</a>
		</header>
	);
}
