import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import createMDX from "@next/mdx";
import type { NextConfig } from "next";

const siteDir = dirname(fileURLToPath(import.meta.url));
const workspaceRoot = resolve(siteDir, "../..");
const inMonorepo = existsSync(resolve(workspaceRoot, "pnpm-workspace.yaml"));

const nextConfig: NextConfig = {
	reactStrictMode: true,
	pageExtensions: ["js", "jsx", "md", "mdx", "ts", "tsx"],
	...(inMonorepo ? { turbopack: { root: workspaceRoot } } : {}),
};

const withMDX = createMDX();

export default withMDX(nextConfig);
