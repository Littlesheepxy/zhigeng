import QRCode from "qrcode";
import { useCallback, useEffect, useRef, useState } from "react";
import { IosSwitch, StatusDot } from "./FormFields.js";

type RemoteDevice = {
	id: string;
	kind: "mac" | "ios";
	name: string;
	lastSeenAt: string | null;
	revokedAt: string | null;
};

function formatWhen(value: string | null): string {
	if (!value) return "尚未在线";
	return new Date(value).toLocaleString("zh-CN", {
		month: "numeric",
		day: "numeric",
		hour: "2-digit",
		minute: "2-digit",
	});
}

export function ZhigengRemotePanel() {
	const [configured, setConfigured] = useState(false);
	const [deviceId, setDeviceId] = useState<string | null>(null);
	const [state, setState] = useState<"disabled" | "connecting" | "connected" | "error">(
		"disabled",
	);
	const [devices, setDevices] = useState<RemoteDevice[]>([]);
	const [busy, setBusy] = useState(false);
	const [error, setError] = useState<string | null>(null);
	const [showDialog, setShowDialog] = useState(false);
	const [pairingCode, setPairingCode] = useState<string | null>(null);
	const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);
	const [expiresAt, setExpiresAt] = useState<string | null>(null);
	const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

	const stopPoll = useCallback(() => {
		if (pollRef.current) clearInterval(pollRef.current);
		pollRef.current = null;
	}, []);

	const refresh = useCallback(async () => {
		const status = await window.fold.zhigengRemoteStatus();
		setConfigured(status.configured);
		setDeviceId(status.deviceId);
		setState(status.state);
		setError(status.error);
		try {
			const listed = await window.fold.zhigengRemoteDevices();
			setDevices(listed.devices.filter((device) => !device.revokedAt));
		} catch {
			setDevices([]);
		}
	}, []);

	useEffect(() => {
		void refresh();
		return stopPoll;
	}, [refresh, stopPoll]);

	const startPairing = async () => {
		setBusy(true);
		setError(null);
		setShowDialog(true);
		try {
			const pair = await window.fold.zhigengRemotePairStart();
			setPairingCode(pair.code);
			setExpiresAt(pair.expiresAt);
			setQrDataUrl(
				await QRCode.toDataURL(pair.qrPayload, {
					width: 196,
					margin: 1,
					color: { dark: "#111111", light: "#ffffff" },
				}),
			);
			stopPoll();
			pollRef.current = setInterval(() => {
				void (async () => {
					const result = await window.fold.zhigengRemotePairPoll(pair.pairingId);
					if (result.status === "claimed") {
						stopPoll();
						setPairingCode(null);
						setQrDataUrl(null);
						await refresh();
						setTimeout(() => setShowDialog(false), 700);
					} else if (result.status !== "pending") {
						stopPoll();
						setError("配对码已失效，请重新生成");
					}
				})().catch((cause) => {
					stopPoll();
					setError(cause instanceof Error ? cause.message : String(cause));
				});
			}, 2_000);
		} catch (cause) {
			setError(cause instanceof Error ? cause.message : String(cause));
		} finally {
			setBusy(false);
		}
	};

	const toggle = async (next: boolean) => {
		if (next) {
			await startPairing();
			return;
		}
		if (!deviceId || !window.confirm("关闭后，iPhone 将不能再向这台 Mac 发起任务。确定？")) return;
		setBusy(true);
		try {
			await window.fold.zhigengRemoteRevoke(deviceId);
			setShowDialog(false);
			await refresh();
		} catch (cause) {
			setError(cause instanceof Error ? cause.message : String(cause));
		} finally {
			setBusy(false);
		}
	};

	const revoke = async (device: RemoteDevice) => {
		if (!window.confirm(`撤销“${device.name}”后，需要重新扫码才能连接。确定？`)) return;
		setBusy(true);
		try {
			await window.fold.zhigengRemoteRevoke(device.id);
			await refresh();
		} catch (cause) {
			setError(cause instanceof Error ? cause.message : String(cause));
		} finally {
			setBusy(false);
		}
	};

	const statusText =
		state === "connected"
			? "已连接"
			: state === "connecting"
				? "正在连接"
				: configured
					? "等待 Mac 上线"
					: "未开启";

	return (
		<>
			<section className="fold-remote-compact">
				<button type="button" onClick={() => configured && setShowDialog(true)}>
					<span>
						<strong>iPhone 远程</strong>
						<small>从手机继续这台 Mac 的任务</small>
					</span>
				</button>
				<div className="fold-remote-compact-control">
					<StatusDot
						status={state === "connected" ? "ok" : state === "connecting" ? "warn" : "off"}
					/>
					<span>{statusText}</span>
					<IosSwitch
						checked={configured}
						disabled={busy}
						ariaLabel="开启 iPhone 远程"
						onChange={(next) => void toggle(next)}
					/>
				</div>
			</section>

			{error && <p className="fold-codex-remote-error">{error}</p>}

			{showDialog && (
				<div
					className="fold-remote-dialog-backdrop"
					role="presentation"
					onMouseDown={(event) => {
						if (event.currentTarget === event.target) setShowDialog(false);
					}}
				>
					<section className="fold-remote-dialog" role="dialog" aria-modal="true" aria-label="iPhone 远程">
						<header>
							<div>
								<h2>{pairingCode ? "连接 iPhone" : "iPhone 远程"}</h2>
								<p>任务在本机执行；发送、删除等操作仍会在手机上请求确认。</p>
							</div>
							<button type="button" aria-label="关闭" onClick={() => setShowDialog(false)}>
								×
							</button>
						</header>

						{pairingCode ? (
							<div className="fold-codex-remote-pair">
								{qrDataUrl && (
									<img src={qrDataUrl} alt="知更 iPhone 配对二维码" width={196} height={196} />
								)}
								<strong>打开 iPhone 知更扫码</strong>
								<span className="fold-codex-remote-code">{pairingCode}</span>
								<small>
									也可使用系统相机
									{expiresAt ? ` · ${new Date(expiresAt).toLocaleTimeString("zh-CN")} 前有效` : ""}
								</small>
							</div>
						) : (
							<>
								<div className="fold-codex-remote-actions">
									<button
										type="button"
										className="fold-profile-action-btn"
										disabled={busy}
										onClick={() => void startPairing()}
									>
										连接另一台 iPhone
									</button>
									<button
										type="button"
										className="fold-home-inline-btn"
										disabled={busy}
										onClick={() => void refresh()}
									>
										刷新
									</button>
								</div>
								<div className="fold-codex-remote-clients">
									<h3>已连接设备</h3>
									<ul>
										{devices.map((device) => (
											<li key={device.id}>
												<div>
													<strong>{device.name}</strong>
													<small>
														{device.kind === "mac" ? "这台 Mac" : "iPhone"} ·{" "}
														{formatWhen(device.lastSeenAt)}
													</small>
												</div>
												<button
													type="button"
													className="fold-home-inline-btn"
													disabled={busy}
													onClick={() => void revoke(device)}
												>
													撤销
												</button>
											</li>
										))}
									</ul>
								</div>
							</>
						)}

						<p className="fold-codex-remote-meta">
							合盖遵循 macOS：接电并连接外接显示器时可继续运行；普通合盖会暂停。
						</p>
					</section>
				</div>
			)}
		</>
	);
}
