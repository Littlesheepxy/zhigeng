import SwiftUI
import VisionKit
import ZhigengCore

/// Device / pairing management only — daily tasks enter from Home execute mode.
struct RemoteHomeView: View {
	@Bindable var remote: RemoteStore
	@State private var showScanner = false

	var body: some View {
		List {
			Section {
				HStack(spacing: 12) {
					Image(systemName: "desktopcomputer")
						.font(.title2)
						.foregroundStyle(remote.macOnline ? Brand.success : .secondary)
					VStack(alignment: .leading, spacing: 3) {
						Text(statusTitle)
							.font(.headline)
						Text(statusSubtitle)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			}

			Section {
				Button {
					showScanner = true
				} label: {
					Label(remote.signedIn ? "重新扫码配对" : "扫码连接 Mac", systemImage: "qrcode.viewfinder")
				}
			}

			if remote.signedIn {
				Section {
					NavigationLink {
						RemoteWorkspaceView(remote: remote, threadId: nil)
					} label: {
						Label("打开任务对话", systemImage: "bubble.left.and.bubble.right")
					}
					.disabled(!remote.macOnline)
				} footer: {
					Text("日常任务请从首页「执行」进入。")
				}

				Section {
					Button("退出登录", role: .destructive) {
						remote.signOutAccount()
					}
				} footer: {
					if let base = remote.accountApiBase {
						Text("账户 API：\(base.absoluteString)")
					}
				}
			}
		}
		.navigationTitle(remote.signedIn ? "Mac 设备" : "连接 Mac")
		.navigationBarTitleDisplayMode(.inline)
		.refreshable { await remote.refreshThreads() }
		.task {
			if remote.signedIn {
				await remote.refreshThreads()
			}
		}
		.sheet(isPresented: $showScanner) {
			RemoteScannerSheet { url in
				showScanner = false
				Task { @MainActor in
					try? await Task.sleep(for: .milliseconds(250))
					remote.preparePairing(url: url)
				}
			}
		}
	}

	private var statusTitle: String {
		if remote.macOnline { return "Mac 已在线" }
		if remote.signedIn { return "Mac 当前离线" }
		return "尚未连接 Mac"
	}

	private var statusSubtitle: String {
		if remote.macOnline { return "可从首页执行模式派发任务" }
		if remote.signedIn { return "打开 Mac 上的知更后即可继续" }
		return "扫码登录同一知更账户后即可连接"
	}
}

struct RemoteWorkspaceView: View {
	@Bindable var remote: RemoteStore
	let threadId: String?
	@State private var draft = ""
	@State private var showDrawer = false
	@State private var showDeviceManage = false

	var body: some View {
		ZStack(alignment: .leading) {
			VStack(spacing: 0) {
				chatScroll
				composer
			}
			.background(Brand.canvas)

			if showDrawer {
				Color.black.opacity(0.28)
					.ignoresSafeArea()
					.onTapGesture {
						withAnimation(.easeOut(duration: 0.22)) { showDrawer = false }
					}
					.transition(.opacity)

				RemoteThreadDrawer(
					remote: remote,
					onNewThread: {
						remote.newThread()
						withAnimation(.easeOut(duration: 0.22)) { showDrawer = false }
					},
					onSelect: { id in
						Task {
							await remote.selectThread(id)
							withAnimation(.easeOut(duration: 0.22)) { showDrawer = false }
						}
					},
					onManageDevice: {
						withAnimation(.easeOut(duration: 0.22)) { showDrawer = false }
						showDeviceManage = true
					},
					onClose: {
						withAnimation(.easeOut(duration: 0.22)) { showDrawer = false }
					}
				)
				.frame(maxWidth: .infinity, alignment: .leading)
				.transition(.move(edge: .leading))
			}
		}
		.animation(.easeOut(duration: 0.22), value: showDrawer)
		.navigationTitle(threadTitle)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				HStack(spacing: 14) {
					Button {
						withAnimation(.easeOut(duration: 0.22)) { showDrawer = true }
					} label: {
						Image(systemName: "line.3.horizontal")
					}
					.accessibilityLabel("历史任务")

					HStack(spacing: 6) {
						Circle()
							.fill(remote.macOnline ? Brand.success : Color(.systemGray3))
							.frame(width: 7, height: 7)
						Text(remote.macOnline ? "在线" : "离线")
							.font(.caption.weight(.semibold))
							.foregroundStyle(remote.macOnline ? Brand.success : .secondary)
					}
				}
			}
		}
		.navigationDestination(isPresented: $showDeviceManage) {
			RemoteHomeView(remote: remote)
		}
		.background(TabBarHider(hidden: true))
		.task {
			await remote.refreshThreads()
			if let threadId {
				await remote.selectThread(threadId)
			} else {
				remote.newThread()
			}
		}
		.sheet(item: $remote.approval) { approval in
			RemoteApprovalView(remote: remote, approval: approval)
				.presentationDetents([.medium])
		}
	}

	private var threadTitle: String {
		if let id = remote.activeThreadId,
		   let thread = remote.threads.first(where: { $0.id == id })
		{
			return thread.title
		}
		return "新任务"
	}

	private var chatScroll: some View {
		ScrollViewReader { proxy in
			ScrollView {
				LazyVStack(spacing: 14) {
					if remote.turns.isEmpty {
						emptyState
							.padding(.top, 48)
					}
					ForEach(remote.turns) { turn in
						RemoteTurnChat(turn: turn)
							.id(turn.id)
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)
			}
			.onChange(of: remote.turns.count) { _, _ in
				if let last = remote.turns.last {
					withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
				}
			}
		}
	}

	private var emptyState: some View {
		VStack(spacing: 18) {
			Image.robin
				.resizable()
				.scaledToFit()
				.frame(width: 96, height: 96)
				.shadow(color: Brand.primaryDark.opacity(0.14), radius: 16, y: 8)
			Text("让 Mac 帮你做点什么？")
				.font(.title3.bold())
			VStack(spacing: 8) {
				suggestionChip("整理桌面上的会议记录，并生成摘要")
				suggestionChip("把下载文件夹里的 PDF 按项目归类")
			}
			.padding(.horizontal, 8)
		}
		.frame(maxWidth: .infinity)
	}

	private func suggestionChip(_ text: String) -> some View {
		Button {
			draft = text
		} label: {
			Text(text)
				.font(.subheadline)
				.foregroundStyle(.primary)
				.multilineTextAlignment(.leading)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 14)
				.padding(.vertical, 12)
				.background(Brand.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
				.overlay {
					RoundedRectangle(cornerRadius: 14, style: .continuous)
						.stroke(Brand.stroke, lineWidth: 1)
				}
		}
		.buttonStyle(.plain)
		.disabled(!remote.macOnline || remote.isBusy)
	}

	private var composer: some View {
		HStack(alignment: .bottom, spacing: 10) {
			TextField("给 Mac 一个任务…", text: $draft, axis: .vertical)
				.lineLimit(1...5)
				.padding(.horizontal, 14)
				.padding(.vertical, 10)
				.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			Button {
				let text = draft
				draft = ""
				Task { await remote.send(text) }
			} label: {
				Image(systemName: "arrow.up.circle.fill")
					.font(.system(size: 34))
					.foregroundStyle(canSend ? Brand.primary : Color(.tertiaryLabel))
			}
			.disabled(!canSend)
			.accessibilityLabel("发送")
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
		.background(.regularMaterial)
	}

	private var canSend: Bool {
		!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& remote.macOnline
			&& !remote.isBusy
	}
}

private struct RemoteThreadDrawer: View {
	@Bindable var remote: RemoteStore
	let onNewThread: () -> Void
	let onSelect: (String) -> Void
	let onManageDevice: () -> Void
	let onClose: () -> Void

	var body: some View {
		GeometryReader { geo in
			VStack(alignment: .leading, spacing: 0) {
				HStack {
					Text("任务")
						.font(.headline)
					Spacer()
					Button(action: onClose) {
						Image(systemName: "xmark")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.secondary)
							.frame(width: 28, height: 28)
							.background(Color(.tertiarySystemFill), in: Circle())
					}
					.buttonStyle(.plain)
				}
				.padding(.horizontal, 16)
				.padding(.top, 16)
				.padding(.bottom, 12)

				Button(action: onNewThread) {
					Label("新任务", systemImage: "plus")
						.font(.body.weight(.semibold))
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.horizontal, 14)
						.padding(.vertical, 12)
						.background(Brand.lavender.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
				.buttonStyle(.plain)
				.padding(.horizontal, 12)
				.padding(.bottom, 8)

				ScrollView {
					LazyVStack(alignment: .leading, spacing: 16) {
						if remote.threads.isEmpty {
							Text("还没有历史任务")
								.font(.subheadline)
								.foregroundStyle(.secondary)
								.padding(.horizontal, 16)
								.padding(.top, 20)
						} else {
							threadGroup(title: "今天", threads: todayThreads)
							threadGroup(title: "更早", threads: earlierThreads)
						}
					}
					.padding(.top, 8)
					.padding(.bottom, 20)
				}

				Divider()
				VStack(alignment: .leading, spacing: 10) {
					HStack(spacing: 8) {
						Circle()
							.fill(remote.macOnline ? Brand.success : Color(.systemGray3))
							.frame(width: 7, height: 7)
						Text(remote.macOnline ? "Mac 在线" : "Mac 离线")
							.font(.caption.weight(.semibold))
							.foregroundStyle(remote.macOnline ? Brand.success : .secondary)
					}
					Button(action: onManageDevice) {
						Label("设备管理", systemImage: "desktopcomputer")
							.font(.subheadline.weight(.medium))
					}
					.buttonStyle(.plain)
				}
				.padding(16)
			}
			.frame(width: geo.size.width * 0.82)
			.frame(maxHeight: .infinity)
			.background(Brand.surface)
			.clipShape(
				UnevenRoundedRectangle(
					bottomTrailingRadius: 18,
					topTrailingRadius: 18,
					style: .continuous
				)
			)
			.shadow(color: .black.opacity(0.18), radius: 24, x: 6, y: 0)
		}
	}

	private var todayThreads: [RemoteThreadSummary] {
		remote.threads.filter { Self.isToday($0.updatedAt) }
	}

	private var earlierThreads: [RemoteThreadSummary] {
		remote.threads.filter { !Self.isToday($0.updatedAt) }
	}

	@ViewBuilder
	private func threadGroup(title: String, threads: [RemoteThreadSummary]) -> some View {
		if !threads.isEmpty {
			VStack(alignment: .leading, spacing: 6) {
				Text(title)
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 16)
				ForEach(threads) { thread in
					Button {
						onSelect(thread.id)
					} label: {
						VStack(alignment: .leading, spacing: 3) {
							Text(thread.title)
								.font(.subheadline.weight(remote.activeThreadId == thread.id ? .semibold : .regular))
								.foregroundStyle(.primary)
								.lineLimit(2)
								.multilineTextAlignment(.leading)
							Text(thread.status == "active" ? "可继续" : thread.status)
								.font(.caption2)
								.foregroundStyle(.secondary)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.horizontal, 14)
						.padding(.vertical, 10)
						.background {
							if remote.activeThreadId == thread.id {
								RoundedRectangle(cornerRadius: 12, style: .continuous)
									.fill(Brand.lavender.opacity(0.4))
							}
						}
					}
					.buttonStyle(.plain)
					.padding(.horizontal, 8)
				}
			}
		}
	}

	private static let isoParser: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()

	private static let isoParserBasic: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime]
		return f
	}()

	private static func isToday(_ iso: String) -> Bool {
		let date = isoParser.date(from: iso) ?? isoParserBasic.date(from: iso)
		guard let date else { return false }
		return Calendar.current.isDateInToday(date)
	}
}

private struct RemoteTurnChat: View {
	let turn: RemoteTurnState

	var body: some View {
		VStack(spacing: 10) {
			if !turn.content.isEmpty {
				HStack {
					Spacer(minLength: 56)
					Text(turn.content)
						.font(.body)
						.foregroundStyle(.white)
						.padding(.horizontal, 14)
						.padding(.vertical, 11)
						.background(Brand.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
				}
			}

			HStack {
				VStack(alignment: .leading, spacing: 8) {
					HStack(spacing: 7) {
						if turn.status == .running || turn.status == .dispatched || turn.status == .queued {
							ProgressView()
								.controlSize(.small)
							BreathingDot()
						} else {
							Image(systemName: statusIcon)
								.foregroundStyle(statusColor)
						}
						Text(turn.headline)
							.font(.subheadline.weight(.medium))
							.foregroundStyle(.secondary)
					}
					if turn.status == .failed || turn.status == .completed {
						Text(statusCaption)
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
				}
				.padding(14)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(Brand.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
				.overlay {
					RoundedRectangle(cornerRadius: 16, style: .continuous)
						.stroke(Brand.stroke.opacity(0.8), lineWidth: 1)
				}
				Spacer(minLength: 40)
			}
		}
	}

	private var statusIcon: String {
		switch turn.status {
		case .completed: "checkmark.circle.fill"
		case .failed: "exclamationmark.circle.fill"
		case .awaitingApproval: "hand.raised.circle.fill"
		case .canceled: "xmark.circle.fill"
		default: "clock"
		}
	}

	private var statusColor: Color {
		switch turn.status {
		case .completed: Brand.success
		case .failed: .red
		case .awaitingApproval: .orange
		default: .secondary
		}
	}

	private var statusCaption: String {
		switch turn.status {
		case .completed: "Mac 已完成"
		case .failed: "执行失败"
		default: ""
		}
	}
}

private struct BreathingDot: View {
	var body: some View {
		TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
			let t = timeline.date.timeIntervalSinceReferenceDate
			let breath = 0.5 + 0.5 * sin(t * 2 * .pi / 1.6)
			Circle()
				.fill(Brand.primary.opacity(0.35 + 0.45 * breath))
				.frame(width: 7, height: 7)
				.scaleEffect(0.85 + 0.25 * breath)
		}
	}
}

/// iOS 17-compatible tab bar hide while this page is visible.
private struct TabBarHider: UIViewControllerRepresentable {
	var hidden: Bool

	func makeUIViewController(context: Context) -> Controller {
		Controller(hidden: hidden)
	}

	func updateUIViewController(_ controller: Controller, context: Context) {
		controller.hidden = hidden
		controller.apply()
	}

	final class Controller: UIViewController {
		var hidden: Bool

		init(hidden: Bool) {
			self.hidden = hidden
			super.init(nibName: nil, bundle: nil)
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) { fatalError() }

		override func viewWillAppear(_ animated: Bool) {
			super.viewWillAppear(animated)
			apply()
		}

		override func viewWillDisappear(_ animated: Bool) {
			super.viewWillDisappear(animated)
			tabBarController?.tabBar.isHidden = false
		}

		func apply() {
			tabBarController?.tabBar.isHidden = hidden
		}
	}
}

private struct RemoteApprovalView: View {
	@Bindable var remote: RemoteStore
	let approval: RemoteApproval

	var body: some View {
		NavigationStack {
			VStack(alignment: .leading, spacing: 18) {
				Image(systemName: approval.risk == "destructive" ? "exclamationmark.triangle.fill" : "hand.raised.fill")
					.font(.largeTitle)
					.foregroundStyle(approval.risk == "destructive" ? .red : .orange)
				Text(approval.title)
					.font(.title2.bold())
				Text(approval.message)
					.foregroundStyle(.secondary)
				Spacer()
				ForEach(approval.options) { option in
					if option.tone == "danger" {
						Button(option.label, role: .destructive) {
							Task { await remote.respond(to: approval, option: option) }
						}
						.buttonStyle(.bordered)
						.frame(maxWidth: .infinity)
					} else {
						Button {
							Task { await remote.respond(to: approval, option: option) }
						} label: {
							Text(option.label)
								.frame(maxWidth: .infinity)
						}
						.buttonStyle(.borderedProminent)
						.tint(Brand.primary)
					}
				}
			}
			.padding(24)
			.navigationTitle("Mac 请求确认")
			.navigationBarTitleDisplayMode(.inline)
		}
		.interactiveDismissDisabled()
	}
}

/// Email login for ASR / account without requiring Mac QR pairing.
struct AccountLoginView: View {
	@Bindable var remote: RemoteStore
	@State private var apiBaseText = RemoteStore.defaultAccountApiBase.absoluteString
	@State private var codeRequested = false
	@State private var localEmail = ""
	@State private var localCode = ""

	var body: some View {
		Form {
			if remote.signedIn {
				Section {
					Label("已登录", systemImage: "checkmark.circle.fill")
						.foregroundStyle(Brand.success)
					Text(remote.email.isEmpty ? "账户可用" : remote.email)
					if let base = remote.accountApiBase {
						Text(base.absoluteString)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				Section {
					NavigationLink {
						RemoteHomeView(remote: remote)
					} label: {
						Label("连接 Mac（可选）", systemImage: "desktopcomputer")
					}
					Button("退出登录", role: .destructive) {
						remote.signOutAccount()
						codeRequested = false
						localCode = ""
					}
				} footer: {
					Text("听写只需要账户登录；连 Mac 是远程执行用的。")
				}
			} else {
				Section {
					Text("登录后才能使用豆包听写。开发模式验证码是 888888。")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}

				Section("账户 API") {
					TextField("http://172.16.1.15:3010", text: $apiBaseText)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
						.keyboardType(.URL)
				}

				Section("知更账户") {
					TextField("邮箱", text: $localEmail)
						.textInputAutocapitalization(.never)
						.keyboardType(.emailAddress)
						.autocorrectionDisabled()
					if codeRequested {
						TextField("6 位验证码", text: $localCode)
							.keyboardType(.numberPad)
					}
					Button(codeRequested ? "登录" : "发送验证码") {
						Task { await submit() }
					}
					.disabled(remote.isBusy || localEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}

				Section {
					NavigationLink {
						RemoteHomeView(remote: remote)
					} label: {
						Label("改用扫码连接 Mac", systemImage: "qrcode.viewfinder")
					}
				}
			}

			if let error = remote.error {
				Section {
					Text(error).foregroundStyle(.red)
				}
			}
		}
		.navigationTitle(remote.signedIn ? "账户" : "登录账户")
		.navigationBarTitleDisplayMode(.inline)
		.onAppear {
			if !remote.email.isEmpty { localEmail = remote.email }
			apiBaseText = RemoteStore.defaultAccountApiBase.absoluteString
		}
	}

	private func submit() async {
		guard let apiBase = URL(string: apiBaseText.trimmingCharacters(in: .whitespacesAndNewlines)),
		      apiBase.host != nil
		else {
			remote.error = "请填写有效的账户 API 地址"
			return
		}
		if codeRequested {
			_ = await remote.signInStandalone(apiBase: apiBase, email: localEmail, code: localCode)
		} else {
			await remote.requestStandaloneCode(apiBase: apiBase, email: localEmail)
			if remote.error == nil { codeRequested = true }
		}
	}
}

struct RemotePairingView: View {
	@Bindable var remote: RemoteStore
	@Environment(\.dismiss) private var dismiss
	@State private var codeRequested = false

	var body: some View {
		NavigationStack {
			Form {
				Section {
					Label("正在连接你的 Mac", systemImage: "desktopcomputer")
						.font(.headline)
					Text("登录同一知更账户后，这台 iPhone 才能向 Mac 派发任务。")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}

				if remote.signedIn {
					Section {
						Button("确认连接") {
							Task {
								if await remote.claimWithExistingSession() { dismiss() }
							}
						}
						.disabled(remote.isBusy)
					}
				} else {
					Section("知更账户") {
						TextField("邮箱", text: $remote.email)
							.textInputAutocapitalization(.never)
							.keyboardType(.emailAddress)
						if codeRequested {
							TextField("6 位验证码", text: $remote.code)
								.keyboardType(.numberPad)
						}
						Button(codeRequested ? "登录并连接" : "发送验证码") {
							Task {
								if codeRequested {
									if await remote.verifyAndClaim() { dismiss() }
								} else {
									await remote.requestCode()
									if remote.error == nil { codeRequested = true }
								}
							}
						}
						.disabled(remote.isBusy)
					}
				}

				if let error = remote.error {
					Section {
						Text(error)
							.foregroundStyle(.red)
					}
				}
			}
			.navigationTitle("连接 Mac")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("取消") {
						remote.pairing = nil
						dismiss()
					}
				}
			}
		}
	}
}

private struct RemoteScannerSheet: View {
	let onScan: (URL) -> Void
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			Group {
				if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
					RemoteScannerView(onScan: onScan)
						.ignoresSafeArea()
						.overlay(alignment: .bottom) {
							Text("对准 Mac 上的知更二维码")
								.font(.headline)
								.padding(.horizontal, 18)
								.padding(.vertical, 12)
								.background(.regularMaterial, in: Capsule())
								.padding(.bottom, 28)
						}
				} else {
					ContentUnavailableView(
						"此设备不支持 App 内扫码",
						systemImage: "qrcode.viewfinder",
						description: Text("可使用系统相机扫描 Mac 上的二维码")
					)
				}
			}
			.navigationTitle("扫描 Mac")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("取消") { dismiss() }
				}
			}
		}
	}
}

private struct RemoteScannerView: UIViewControllerRepresentable {
	let onScan: (URL) -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator(onScan: onScan)
	}

	func makeUIViewController(context: Context) -> DataScannerViewController {
		let scanner = DataScannerViewController(
			recognizedDataTypes: [.barcode(symbologies: [.qr])],
			qualityLevel: .balanced,
			recognizesMultipleItems: false,
			isHighFrameRateTrackingEnabled: false,
			isHighlightingEnabled: true
		)
		scanner.delegate = context.coordinator
		DispatchQueue.main.async {
			try? scanner.startScanning()
		}
		return scanner
	}

	func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

	final class Coordinator: NSObject, DataScannerViewControllerDelegate {
		let onScan: (URL) -> Void
		private var handled = false

		init(onScan: @escaping (URL) -> Void) {
			self.onScan = onScan
		}

		func dataScanner(
			_ dataScanner: DataScannerViewController,
			didAdd addedItems: [RecognizedItem],
			allItems: [RecognizedItem]
		) {
			guard !handled else { return }
			for item in addedItems {
				guard case .barcode(let barcode) = item,
				      let value = barcode.payloadStringValue,
				      let url = URL(string: value),
				      url.scheme == "zhigeng",
				      url.host == "pair"
				else { continue }
				handled = true
				dataScanner.stopScanning()
				onScan(url)
				return
			}
		}
	}
}
