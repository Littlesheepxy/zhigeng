import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import createMDX from "@next/mdx";
import type { NextConfig } from "next";

const siteDir = dirname(fileURLToPath(import.meta.url));
const workspaceRoot = resolve(siteDir, "../..");
const inMonorepo = existsSync(resolve(workspaceRoot, "pnpm-workspace.yaml"));

const macDmgOrigin =
	"https://sbbsyirthbay1jzq.public.blob.vercel-storage.com/Zhigeng-mac-arm64.dmg";

const nextConfig: NextConfig = {
	reactStrictMode: true,
	pageExtensions: ["js", "jsx", "md", "mdx", "ts", "tsx"],
	async redirects() {
		return [
			{
				source: "/Zhigeng-mac-arm64.dmg",
				destination: macDmgOrigin,
				permanent: false,
			},
		];
	},
	...(inMonorepo ? { turbopack: { root: workspaceRoot } } : {}),
};

const withMDX = createMDX();

export default withMDX(nextConfig);
