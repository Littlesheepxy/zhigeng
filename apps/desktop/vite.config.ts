import { chmodSync, copyFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import electron from "vite-plugin-electron/simple";

const rootDir = dirname(fileURLToPath(import.meta.url));
const foldSrc = (name: string) => resolve(rootDir, `../../packages/${name}/src/index.ts`);
const calendarHelper = resolve(rootDir, "resources/fold-calendar/fold-calendar");
const calendarInfoPlist = resolve(rootDir, "resources/fold-calendar/Info.plist");
const calendarBuildDir = resolve(rootDir, "dist-electron/fold-calendar");

function stageCalendarHelper() {
	return {
		name: "fold-stage-calendar-helper",
		writeBundle() {
			if (!existsSync(calendarHelper)) {
				throw new Error("日历 helper 未准备；先运行 pnpm run prepare:calendar");
			}
			mkdirSync(calendarBuildDir, { recursive: true });
			const output = resolve(calendarBuildDir, "fold-calendar");
			copyFileSync(calendarHelper, output);
			chmodSync(output, 0o755);
			if (existsSync(calendarInfoPlist)) {
				copyFileSync(calendarInfoPlist, resolve(calendarBuildDir, "Info.plist"));
			}
		},
	};
}

const foldAliases = {
	"@fold/ai": foldSrc("ai"),
	"@fold/connectors": foldSrc("connectors"),
	"@fold/context": foldSrc("context"),
	"@fold/memory": foldSrc("memory"),
	"@fold/runtime": foldSrc("runtime"),
	"@fold/skills": foldSrc("skills"),
};

const electronExternals = (id: string) =>
	id === "electron" ||
	id === "@fold/macos-input" ||
	id === "better-sqlite3" ||
	id === "uiohook-napi" ||
	id === "@kutalia/whisper-node-addon" ||
	id === "sherpa-onnx-node" ||
	id.startsWith("sherpa-onnx-") ||
	id === "fsevents" ||
	id === "uuid" ||
	id.startsWith("playwright") ||
	id === "@playwright/mcp" ||
	id.startsWith("@modelcontextprotocol/") ||
	id.startsWith("@computer-use/") ||
	id.startsWith("@ui-tars/");

export default defineConfig({
	// react-draggable 在 handleDragStart 里访问 process.env.DRAGGABLE_DEBUG，
	// 渲染进程没有 process 全局 → ReferenceError → 拖拽静默失败
	define: {
		"process.env.DRAGGABLE_DEBUG": "false",
	},
	optimizeDeps: {
		esbuildOptions: {
			define: {
				"process.env.DRAGGABLE_DEBUG": "false",
			},
		},
	},
		build: {
		rollupOptions: {
			input: {
				main: "index.html",
				settings: "settings.html",
				onboarding: "onboarding.html",
			},
		},
	},
	plugins: [
		react(),
		tailwindcss(),
		electron({
			main: {
				entry: "electron/main.ts",
				onstart({ startup }) {
					// Main 重建时重启 Electron，否则 preload 已暴露新 IPC 但主进程仍是旧代码。
					void startup();
				},
				vite: {
					resolve: { alias: foldAliases },
					plugins: [stageCalendarHelper()],
					build: {
						outDir: "dist-electron",
						rollupOptions: {
							external: electronExternals,
						},
					},
				},
			},
			preload: {
				input: "electron/preload.ts",
				vite: {
					build: { outDir: "dist-electron" },
				},
			},
		}),
	],
	server: {
		port: 5173,
	},
	publicDir: "public",
});
