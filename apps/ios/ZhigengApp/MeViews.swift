import SwiftUI
import UIKit
import ZhigengCore

struct MeView: View {
	@Bindable var store: AppStore

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 18) {
					Text("我的")
						.font(.largeTitle.bold())
						.frame(maxWidth: .infinity, alignment: .leading)

					accountHero

					VStack(alignment: .leading, spacing: 8) {
						sectionTitle("设备")
						HStack(spacing: 12) {
						NavigationLink {
							KeyboardSetupView(store: store)
						} label: {
								deviceTile(
								icon: "keyboard",
								title: "知更键盘",
									status: keyboardStatus,
									color: keyboardStatus == "已连接" ? Brand.success : .orange
							)
						}
						.buttonStyle(.plain)
						NavigationLink {
							RemoteHomeView(remote: store.remote)
						} label: {
								deviceTile(
								icon: "desktopcomputer",
								title: "Mac",
									status: store.remote.macOnline ? "在线" : "未连接",
									color: store.remote.macOnline ? Brand.success : .secondary
							)
						}
						.buttonStyle(.plain)
						}
					}

					VStack(alignment: .leading, spacing: 8) {
						sectionTitle("设置与支持")
						VStack(spacing: 0) {
						NavigationLink {
							PrivacyFullAccessView()
						} label: {
								supportRow(icon: "hand.raised", title: "隐私与数据")
						}
						.buttonStyle(.plain)
							Divider().padding(.leading, 50)
						Button {
							store.reopenOnboarding(at: .brandWelcome)
						} label: {
								supportRow(icon: "questionmark.circle", title: "帮助与引导")
						}
						.buttonStyle(.plain)
						}
						.background(Brand.surface)
						.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
						.overlay {
							RoundedRectangle(cornerRadius: 18, style: .continuous)
								.stroke(Brand.stroke.opacity(0.75), lineWidth: 1)
						}
					}

					#if DEBUG
						NavigationLink {
							DeveloperToolsView(store: store)
						} label: {
							HStack(spacing: 7) {
								Text("版本 0.1.0")
								Circle().frame(width: 2.5, height: 2.5)
								Text("开发验证")
								Image(systemName: "chevron.right")
									.font(.caption2.bold())
							}
							.font(.caption)
							.foregroundStyle(.tertiary)
							.frame(maxWidth: .infinity)
							.padding(.top, 2)
						}
						.buttonStyle(.plain)
					#endif
				}
				.padding(.horizontal, 20)
				.padding(.vertical, 16)
			}
			.background(Brand.canvas)
			.toolbar(.hidden, for: .navigationBar)
		}
	}

	private var keyboardStatus: String {
		guard let heartbeat = store.heartbeat, heartbeat.isFresh else { return "待验证" }
		return heartbeat.hasFullAccess ? "已连接" : "待开启"
	}

	private var accountHero: some View {
		NavigationLink {
			AccountLoginView(remote: store.remote)
		} label: {
			ZStack {
				MistBackdrop()
				.opacity(0.82)
				.clipped()
				HStack(spacing: 14) {
					ZStack {
						Circle()
							.fill(.white.opacity(0.58))
							.frame(width: 64, height: 64)
							.shadow(color: Brand.primaryDark.opacity(0.12), radius: 14, y: 6)
						Image.robin
							.resizable()
							.scaledToFit()
							.frame(width: 56, height: 56)
					}
					VStack(alignment: .leading, spacing: 4) {
						Text(store.remote.signedIn ? (store.remote.email.isEmpty ? "已登录" : store.remote.email) : "本地使用")
							.font(.headline)
							.foregroundStyle(.primary)
							.lineLimit(1)
						Text(store.remote.signedIn ? "个人词与账户同步" : "词与记录保存在这台 iPhone")
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(2)
					}
					Spacer(minLength: 4)
					Text(store.remote.signedIn ? "管理" : "登录")
						.font(.caption.weight(.semibold))
						.foregroundStyle(Brand.primaryDark)
						.padding(.horizontal, 12)
						.padding(.vertical, 8)
						.background(.white.opacity(0.72), in: Capsule())
				}
				.padding(16)
			}
			.frame(height: 112)
			.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 24, style: .continuous)
					.stroke(.white.opacity(0.65), lineWidth: 1)
			}
			.shadow(color: Brand.primaryDark.opacity(0.09), radius: 18, y: 8)
		}
		.buttonStyle(.plain)
	}

	private func sectionTitle(_ title: String) -> some View {
		Text(title)
			.font(.caption.weight(.semibold))
			.foregroundStyle(.secondary)
			.padding(.leading, 4)
	}

	private func deviceTile(icon: String, title: String, status: String, color: Color) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Image(systemName: icon)
					.font(.body.weight(.medium))
					.foregroundStyle(Brand.primaryDark)
					.frame(width: 36, height: 36)
					.background(Brand.lavender.opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
				Spacer()
				Image(systemName: "chevron.right")
					.font(.caption.bold())
					.foregroundStyle(.tertiary)
			}
			Text(title)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.primary)
			HStack(spacing: 6) {
				Circle()
					.fill(color)
					.frame(width: 6, height: 6)
				Text(status)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(14)
		.frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
		.background(Brand.surface)
		.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.stroke(Brand.stroke.opacity(0.75), lineWidth: 1)
		}
	}

	private func supportRow(icon: String, title: String) -> some View {
		HStack(spacing: 12) {
			Image(systemName: icon)
				.font(.body)
				.foregroundStyle(.secondary)
				.frame(width: 26)
			Text(title)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.primary)
			Spacer()
			Image(systemName: "chevron.right")
				.font(.caption.bold())
				.foregroundStyle(.tertiary)
		}
		.padding(.horizontal, 14)
		.frame(minHeight: 52)
	}
}

#if DEBUG
struct DeveloperToolsView: View {
	@Bindable var store: AppStore

	var body: some View {
		List {
			Section {
				Button("试听写") {
					store.showDictation = true
				}
				Button("重新运行引导") {
					store.reopenOnboarding(at: .brandWelcome)
				}
				NavigationLink("诊断") {
					DiagnosticsView(store: store)
				}
			} footer: {
				Text("仅 Debug 构建可见。正式版不会出现这些入口。")
			}
		}
		.navigationTitle("开发验证")
		.navigationBarTitleDisplayMode(.inline)
	}
}
#endif

struct PrivacyFullAccessView: View {
	var body: some View {
		List {
			Section {
				Text("完全访问用于主 App 与键盘通过 App Group 交换听写结果和个人词库。")
				Text("不会上传你键入的所有内容。密码框不会使用知更键盘。")
				Text("原始音频默认不保存。")
			}
			Section {
				Text("路径：设置 → 通用 → 键盘 → 键盘 → 知更 → 允许完全访问")
					.textSelection(.enabled)
			}
		}
		.navigationTitle("隐私与数据")
	}
}

struct DiagnosticsView: View {
	@Bindable var store: AppStore
	@State private var asrDraft = ""
	@State private var asrProbe = ""

	var body: some View {
		List {
			LabeledContent("麦克风", value: store.microphoneGranted ? "已授权" : "未授权")
			LabeledContent("键盘心跳", value: heartbeatLabel)
			LabeledContent("完全访问(扩展)", value: fullAccessLabel)
			LabeledContent("词条数", value: "\(store.lexicon.allTerms.count)")
			LabeledContent("历史条数", value: "\(store.history.count)")

			Section {
				TextField("ws://127.0.0.1:3003", text: $asrDraft)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.keyboardType(.URL)
				Button("保存 ASR 地址") {
					store.setAsrBaseURL(asrDraft)
					asrProbe = "已保存"
				}
				Button("探测 /asr/health") {
					Task { await probeAsr() }
				}
				if !asrProbe.isEmpty {
					Text(asrProbe)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			} header: {
				Text("ASR")
			} footer: {
				Text("真机请填 Mac 局域网地址，如 ws://172.16.1.15:3003。公网 Fold ASR 尚未部署。")
			}

			Button("复制诊断信息") {
				UIPasteboard.general.string = diagnosticText
			}
		}
		.navigationTitle("诊断")
		.onAppear {
			store.reloadSharedState()
			asrDraft = store.asrBaseURL
		}
	}

	private var heartbeatLabel: String {
		guard let hb = store.heartbeat else { return "无" }
		let ago = Int(Date().timeIntervalSince1970 - hb.lastSeenAt)
		return hb.isFresh ? "\(ago)s 前" : "过期 · \(ago)s 前"
	}

	private var fullAccessLabel: String {
		guard let hb = store.heartbeat else { return "尚未检测" }
		if !hb.isFresh { return "结果过期，请重新验证" }
		return hb.hasFullAccess ? "开启" : "关闭"
	}

	private var diagnosticText: String {
		"""
		version=0.1.0
		mic=\(store.microphoneGranted)
		heartbeat=\(heartbeatLabel)
		fullAccess=\(fullAccessLabel)
		terms=\(store.lexicon.allTerms.count)
		history=\(store.history.count)
		asr=\(store.asrBaseURL)
		"""
	}

	private func probeAsr() async {
		let base = asrDraft.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let wsURL = URL(string: base),
		      var comps = URLComponents(url: wsURL, resolvingAgainstBaseURL: false)
		else {
			asrProbe = "地址无效"
			return
		}
		comps.scheme = (comps.scheme == "wss") ? "https" : "http"
		comps.path = "/asr/health"
		guard let healthURL = comps.url else {
			asrProbe = "地址无效"
			return
		}
		do {
			let (data, response) = try await URLSession.shared.data(from: healthURL)
			let code = (response as? HTTPURLResponse)?.statusCode ?? 0
			let body = String(data: data, encoding: .utf8) ?? ""
			asrProbe = "HTTP \(code) \(body.prefix(120))"
		} catch {
			asrProbe = "失败：\(error.localizedDescription)"
		}
	}
}
