import { useCallback, useEffect, useRef, useState } from "react";
import type { CapabilityItem, ExecutionMode, FoldConfig, HomeSnapshot } from "../types.js";
import { ConnectFlowModal, type ConnectFlowTarget } from "../components/ConnectFlowModal.js";
import { CapabilityGroup, ChannelChipGrid } from "../components/ChannelChipGrid.js";
import { ConnectionIcon, CONNECTION_CHIP_ICON_SIZE } from "../components/ConnectionIcon.js";
import { CodexRemoteControlPanel } from "../components/CodexRemoteControlPanel.js";
import { ZhigengRemotePanel } from "../components/ZhigengRemotePanel.js";
import { IosSwitch, StatusDot } from "../components/FormFields.js";

/** iOS Codex 客户端就绪后改为 true */
const CODEX_REMOTE_CONTROL_UI_ENABLED = false;

const MODE_OPTIONS: Array<{
	id: ExecutionMode;
	label: string;
	description: string;
	recommended?: boolean;
}> = [
	{
		id: "auto",
		label: "自动",
		description: "快的 知更 处理，难的交给你的 Agent",
		recommended: true,
	},
	{
		id: "local_agent",
		label: "自己的 Agent",
		description: "复杂任务由 Codex / Claude 等执行",
	},
	{
		id: "fold_only",
		label: "仅用 知更",
		description: "不调用本地 Agent，全部由 知更 完成",
	},
];

function browserRowItems(caps: CapabilityItem[]) {
	return caps.filter((c) => c.group === "browser");
}

function communicateItems(caps: CapabilityItem[]) {
	return caps.filter((c) => c.group === "communicate" && c.layer === 0);
}

function hubItems(caps: CapabilityItem[]) {
	return caps.filter((c) => c.group === "hub");
}

export function ConnectionsSection({
	snapshot,
	onRefresh,
	onOpenSettings,
	onSaveConfig,
}: {
	snapshot: HomeSnapshot;
	onRefresh: () => Promise<void>;
	onOpenSettings: () => void;
	onSaveConfig: (config: FoldConfig) => Promise<void>;
}) {
	const [busy, setBusy] = useState(false);
	const [connectTarget, setConnectTarget] = useState<ConnectFlowTarget | null>(null);
	const [showHub, setShowHub] = useState(false);
	const pollTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

	const capSnap = snapshot.capabilitySnapshot;
	const mode = capSnap?.executionMode ?? "auto";
	const capabilities = capSnap?.capabilities ?? [];
	const executors = capSnap?.executors ?? [];
	const summary = capSnap?.summary ?? { ready: 0, total: 0, modeLabel: "自动" };

	const stopRefreshPoll = useCallback(() => {
		if (pollTimerRef.current) {
			clearInterval(pollTimerRef.current);
			pollTimerRef.current = null;
		}
	}, []);

	const refresh = useCallback(async () => {
		setBusy(true);
		try {
			await onRefresh();
		} finally {
			setBusy(false);
		}
	}, [onRefresh]);

	const startRefreshPoll = useCallback(() => {
		stopRefreshPoll();
		void refresh();
		let ticks = 0;
		pollTimerRef.current = setInterval(() => {
			ticks += 1;
			void refresh();
			if (ticks >= 8) stopRefreshPoll();
		}, 2000);
	}, [refresh, stopRefreshPoll]);

	useEffect(() => () => stopRefreshPoll(), [stopRefreshPoll]);

	const persistConfig = async (patch: Partial<FoldConfig>) => {
		const config = await window.fold.getConfig();
		const next = { ...config, ...patch };
		await onSaveConfig(next);
		await refresh();
	};

	const setMode = async (executionMode: ExecutionMode) => {
		setBusy(true);
		try {
			await persistConfig({ executionMode });
		} finally {
			setBusy(false);
		}
	};

	const toggleCapability = async (cap: CapabilityItem, enabled: boolean) => {
		const config = await window.fold.getConfig();
		const current = new Set(config.enabledCapabilities ?? capabilities.filter((c) => c.enabled).map((c) => c.id));
		if (enabled) current.add(cap.id);
		else current.delete(cap.id);
		setBusy(true);
		try {
			await persistConfig({ enabledCapabilities: [...current] });
		} finally {
			setBusy(false);
		}
	};

	const openConnect = (cap: CapabilityItem) => {
		if (!cap.connectTarget) return;
		if (cap.connectTarget === "cdp") {
			void (async () => {
				setBusy(true);
				try {
					await window.fold.runConnectionAction("cdp:install-bridge");
					startRefreshPoll();
				} finally {
					setBusy(false);
				}
			})();
			return;
		}
		if (cap.connectTarget === "screen") {
			void (async () => {
				setBusy(true);
				try {
					await window.fold.runConnectionAction("screen:open-settings");
					await window.fold.runConnectionAction("accessibility:open-settings");
					startRefreshPoll();
				} finally {
					setBusy(false);
				}
			})();
			return;
		}
		setConnectTarget({
			connectionId: cap.connectTarget!,
			label: cap.label,
			kind: cap.connectKind ?? "login",
		});
	};

	const openExecutorConnect = (ex: { connectTarget?: string; label: string }) => {
		if (!ex.connectTarget) return;
		setConnectTarget({
			connectionId: ex.connectTarget,
			label: ex.label,
			kind: "login",
		});
	};

	const selectExecutor = async (id: string) => {
		setBusy(true);
		try {
			await persistConfig({
				preferredExecutor: id as FoldConfig["preferredExecutor"],
			});
		} finally {
			setBusy(false);
		}
	};

	const handleConnectSuccess = async () => {
		if (connectTarget?.connectionId === "workbuddy") {
			const config = await window.fold.getConfig();
			const caps = new Set(config.enabledCapabilities ?? capabilities.filter((c) => c.enabled).map((c) => c.id));
			caps.add("workflow.workbuddy");
			await onSaveConfig({ ...config, enabledCapabilities: [...caps] });
		}
		await refresh();
		startRefreshPoll();
	};

	const commItems = communicateItems(capabilities);
	const browserItems = browserRowItems(capabilities);
	const hubCaps = hubItems(capabilities);
	const commGroup = capSnap?.groups.find((g) => g.id === "communicate");
	const browserGroup = capSnap?.groups.find((g) => g.id === "browser");

	return (
		<div className="space-y-4">
			<div>
				<h1 className="fold-home-page-title">连接</h1>
				<p className="fold-home-page-subtitle">
					{summary.modeLabel} · 日常 {summary.ready}/{summary.total} 已就绪
					{summary.executorLabel ? ` · ${summary.executorLabel}` : ""}
				</p>
			</div>

			{CODEX_REMOTE_CONTROL_UI_ENABLED ? <CodexRemoteControlPanel /> : null}
			<ZhigengRemotePanel />

			<section className="fold-execution-mode-grid" aria-label="执行模式">
				{MODE_OPTIONS.map((opt) => (
					<button
						key={opt.id}
						type="button"
						disabled={busy}
						className={`fold-execution-mode-card${mode === opt.id ? " is-active" : ""}`}
						onClick={() => void setMode(opt.id)}
					>
						<span className="fold-execution-mode-label">
							{opt.label}
							{opt.recommended ? <em>推荐</em> : null}
						</span>
						<span className="fold-execution-mode-desc">{opt.description}</span>
					</button>
				))}
			</section>

			{mode !== "fold_only" ? (
				<section className="fold-capability-group" aria-label="执行伙伴">
					<div className="fold-capability-group-head is-static">
						<span className="fold-capability-group-title">执行伙伴</span>
						<span className="fold-capability-group-meta">可选</span>
					</div>
					<div className="fold-capability-group-body">
						<div className="fold-connection-chip-grid">
							{executors.map((ex) => (
								<button
									key={ex.id}
									type="button"
									disabled={busy}
									className={`fold-connection-chip fold-connection-chip--solo${ex.isDefault ? " is-default" : ""}${ex.available ? " is-enabled" : ex.connectTarget ? " is-connectable" : ""}`}
									title={
										ex.available
											? `${ex.label} 已连接`
											: ex.error
												? `${ex.error}，点击连接`
												: ex.connectTarget
													? `点击连接 ${ex.label}`
													: undefined
									}
									onClick={() => {
										if (ex.available) void selectExecutor(ex.id);
										else if (ex.connectTarget) openExecutorConnect(ex);
									}}
								>
									<span className="fold-connection-chip-main">
										<span className="fold-connection-chip-icon" aria-hidden="true">
											<ConnectionIcon id={ex.id} size={CONNECTION_CHIP_ICON_SIZE} />
										</span>
										<span className="fold-connection-chip-text">
											<span className="fold-connection-chip-label">{ex.label}</span>
											<span className="fold-connection-chip-detail">
												{ex.available ? ex.detail ?? "已连接" : ex.error ?? "尚未连接"}
											</span>
										</span>
										<StatusDot status={ex.available ? "ok" : "off"} />
									</span>
								</button>
							))}
						</div>
						{mode === "auto" ? (
							<p className="fold-capability-hint">
								没有本地 Agent？仍可先用 知更 处理日常任务。
								<button type="button" className="fold-home-inline-btn" onClick={() => setShowHub(true)}>
									使用 知更 托管
								</button>
							</p>
						) : null}
					</div>
				</section>
			) : (
				<section className="fold-capability-inline-row">
					<StatusDot status={snapshot.configSummary.hasPlannerKey ? "ok" : "off"} />
					<span>知更 执行</span>
					<span className="fold-capability-inline-detail">
						{snapshot.configSummary.hasPlannerKey ? "Planner 已配置" : "建议配置 API Key"}
					</span>
					<button type="button" className="fold-home-inline-btn" onClick={onOpenSettings}>
						设置
					</button>
				</section>
			)}

			{commGroup ? (
				<CapabilityGroup
					id="communicate"
					label={commGroup.label}
					ready={commGroup.ready}
					total={commGroup.total}
					busy={busy}
					onRefresh={() => void refresh()}
				>
					<ChannelChipGrid
						items={commItems}
						busy={busy}
						onChipClick={openConnect}
						onToggle={(cap, enabled) => void toggleCapability(cap, enabled)}
					/>
				</CapabilityGroup>
			) : null}

			{browserGroup ? (
				<CapabilityGroup
					id="browser"
					label={browserGroup.label}
					ready={browserGroup.ready}
					total={browserGroup.total}
					defaultOpen
					busy={busy}
					onRefresh={() => void refresh()}
				>
					{browserItems.map((cap) => {
						const connected = cap.status === "ready";
						return (
							<div key={cap.id} className="fold-capability-browser-row fold-connection-list-row">
								<div className="fold-capability-browser-copy">
									<span className="fold-connection-chip-icon" aria-hidden="true">
										<ConnectionIcon
											id={cap.connectTarget ?? "cdp"}
											size={CONNECTION_CHIP_ICON_SIZE}
										/>
									</span>
									<div className="fold-capability-browser-text">
										<span className="fold-capability-browser-label-row">
											<span className="fold-capability-browser-label">{cap.label}</span>
											<StatusDot status={connected ? "ok" : "off"} />
										</span>
										{cap.detail ? (
											<span className="fold-capability-browser-detail">{cap.detail}</span>
										) : null}
									</div>
								</div>
								<div className="fold-capability-browser-action">
									{connected ? (
										<IosSwitch
											checked={cap.enabled}
											disabled={busy}
											ariaLabel={`启用 ${cap.label}`}
											onChange={(enabled) => void toggleCapability(cap, enabled)}
										/>
									) : (
										<button
											type="button"
											className="fold-capability-connect-btn"
											disabled={busy}
											onClick={() => openConnect(cap)}
										>
											连接
										</button>
									)}
								</div>
							</div>
						);
					})}
				</CapabilityGroup>
			) : null}

			{(mode === "fold_only" || showHub) && hubCaps.length > 0 ? (
				<CapabilityGroup
					id="hub"
					label="更多应用"
					ready={hubCaps.filter((c) => c.status === "ready").length}
					total={hubCaps.length}
					defaultOpen={mode === "fold_only"}
					busy={busy}
					onRefresh={() => void refresh()}
				>
					<ChannelChipGrid items={hubCaps} busy={busy} onChipClick={openConnect} />
				</CapabilityGroup>
			) : null}

			<p className="fold-home-footnote">
				高级连接项（CDP URL、UI-TARS 等）在
				<button type="button" className="fold-home-inline-btn" onClick={onOpenSettings}>
					设置 → 高级
				</button>
			</p>

			<ConnectFlowModal
				target={connectTarget}
				onClose={() => setConnectTarget(null)}
				onSuccess={() => void handleConnectSuccess()}
			/>
		</div>
	);
}
