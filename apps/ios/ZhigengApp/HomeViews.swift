import SwiftUI
import UIKit
import ZhigengCore

struct MainTabView: View {
	@Bindable var store: AppStore

	var body: some View {
		TabView(selection: $store.selectedTab) {
			HomeView(store: store)
				.tabItem { Label("首页", systemImage: "house.fill") }
				.tag(AppTab.home)

			ActivityView(store: store)
				.tabItem { Label("速记", systemImage: "bookmark.fill") }
				.tag(AppTab.activity)

			LexiconView(store: store)
				.tabItem { Label("懂我", systemImage: "sparkles") }
				.tag(AppTab.lexicon)

			MeView(store: store)
				.tabItem { Label("我的", systemImage: "person.crop.circle") }
				.tag(AppTab.me)
		}
		.tint(Brand.primary)
		.sheet(isPresented: $store.showSessionSheet) {
			SessionSheet(store: store)
				.presentationDetents([.height(340)])
				.presentationDragIndicator(.visible)
		}
		.fullScreenCover(isPresented: $store.showDictation) {
			DictationFullScreen(store: store)
		}
		.sheet(isPresented: $store.showAddTerm) {
			AddTermSheet(store: store)
		}
		.sheet(item: $store.editingHistoryItem) { item in
			NavigationStack {
				DictationDetailView(store: store, item: item)
			}
		}
		.onAppear { store.reloadSharedState() }
	}
}

struct HomeView: View {
	enum Mode: String {
		case input
		case execute
	}

	@Bindable var store: AppStore
	@SceneStorage("homeMode") private var homeModeRaw = Mode.input.rawValue

	private var homeMode: Mode {
		get { Mode(rawValue: homeModeRaw) ?? .input }
		nonmutating set { homeModeRaw = newValue.rawValue }
	}

	var body: some View {
		NavigationStack {
			GeometryReader { geo in
				VStack(spacing: 0) {
					HStack(alignment: .center) {
						Text(Brand.name)
							.font(.largeTitle.bold())
						Spacer()
						if homeMode == .input {
							headerSessionControl
						} else {
							macStatusPill
						}
					}
					.padding(.horizontal, 20)
					.padding(.top, 12)
					.padding(.bottom, 14)

					TabView(selection: $homeModeRaw) {
						inputStage
							.frame(maxWidth: .infinity, maxHeight: .infinity)
							.tag(Mode.input.rawValue)
						executeStage
							.frame(maxWidth: .infinity, maxHeight: .infinity)
							.tag(Mode.execute.rawValue)
					}
					.tabViewStyle(.page(indexDisplayMode: .never))
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.padding(.horizontal, 16)
					.padding(.bottom, 12)
				}
				.frame(width: geo.size.width, height: geo.size.height, alignment: .top)
			}
			.background(Brand.canvas)
			.toolbar(.hidden, for: .navigationBar)
			.task {
				if store.remote.signedIn {
					await store.remote.refreshThreads()
				}
			}
		}
	}

	/// Compact mode control for the card's top-trailing corner.
	private var cardModeSwitcher: some View {
		HStack(spacing: 2) {
			cardModeChip(.input, title: "输入")
			cardModeChip(.execute, title: "执行")
		}
		.padding(3)
		.background(Color.white.opacity(0.58), in: Capsule())
		.overlay {
			Capsule().stroke(Color.white.opacity(0.72), lineWidth: 1)
		}
	}

	private func cardModeChip(_ mode: Mode, title: String) -> some View {
		Button {
			withAnimation(.easeInOut(duration: 0.22)) {
				homeModeRaw = mode.rawValue
			}
		} label: {
			Text(title)
				.font(.caption.weight(homeMode == mode ? .semibold : .medium))
				.foregroundStyle(homeMode == mode ? Brand.primaryDark : .secondary)
				.padding(.horizontal, 11)
				.padding(.vertical, 6)
				.background {
					if homeMode == mode {
						Capsule().fill(Brand.lavender.opacity(0.85))
					}
				}
		}
		.buttonStyle(.plain)
	}

	private var macStatusPill: some View {
		HStack(spacing: 7) {
			Circle()
				.fill(store.remote.macOnline ? Brand.success : Color(.systemGray3))
				.frame(width: 7, height: 7)
			Text(store.remote.macOnline ? "Mac 在线" : (store.remote.signedIn ? "Mac 离线" : "未连接"))
				.font(.caption.weight(.semibold))
				.foregroundStyle(store.remote.macOnline ? Brand.success : .secondary)
		}
		.padding(.horizontal, 12)
		.frame(height: 38)
		.background(Brand.surface, in: Capsule())
		.overlay {
			Capsule().stroke(Brand.stroke, lineWidth: 1)
		}
	}

	private var inputStage: some View {
		stageShell(active: isSessionActive) {
			stageTopBar { stageHeader }
			Spacer(minLength: 8)
			robinHero
			inputCopy
				.padding(.top, 18)
				.padding(.horizontal, 26)
			Spacer(minLength: 16)
			inputFooter
				.padding(.horizontal, 18)
				.padding(.bottom, 18)
		}
	}

	private var executeStage: some View {
		stageShell(active: store.remote.macOnline) {
			stageTopBar { executeHeader }
			Spacer(minLength: 8)
			executeHero
			executeCopy
				.padding(.top, 18)
				.padding(.horizontal, 26)
			Spacer(minLength: 16)
			executeFooter
				.padding(.horizontal, 18)
				.padding(.bottom, 18)
		}
	}

	private func stageTopBar<Status: View>(@ViewBuilder status: () -> Status) -> some View {
		HStack(alignment: .center, spacing: 10) {
			status()
			Spacer(minLength: 8)
			cardModeSwitcher
		}
		.padding(.top, 18)
		.padding(.horizontal, 18)
	}

	private func stageShell<Content: View>(active: Bool, @ViewBuilder content: () -> Content) -> some View {
		ZStack(alignment: .bottom) {
			MistBackdrop(active: active)
				.clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

			LinearGradient(
				colors: [.clear, Brand.cloudWhite.opacity(0.72), Brand.cloudWhite.opacity(0.92)],
				startPoint: .top,
				endPoint: .bottom
			)
			.frame(height: 210)
			.clipShape(
				UnevenRoundedRectangle(
					bottomLeadingRadius: 32,
					bottomTrailingRadius: 32,
					style: .continuous
				)
			)
			.frame(maxHeight: .infinity, alignment: .bottom)
			.allowsHitTesting(false)

			VStack(spacing: 0, content: content)
		}
		.clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 32, style: .continuous)
				.stroke(Color.white.opacity(0.55), lineWidth: 1)
		}
		.shadow(color: Brand.primaryDark.opacity(0.12), radius: 28, y: 14)
	}

	private var robinHero: some View {
		TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
			let t = timeline.date.timeIntervalSinceReferenceDate
			let breath = 0.5 + 0.5 * sin(t * 2 * .pi / 5.5)
			ZStack {
				RadialGradient(
					colors: [
						Brand.primary.opacity(0.22 + 0.08 * breath),
						Brand.iceBlue.opacity(0.14),
						.clear,
					],
					center: .center,
					startRadius: 8,
					endRadius: 130
				)
				.frame(width: 260, height: 260)
				.scaleEffect(1 + 0.05 * breath)
				Image.robin
					.resizable()
					.scaledToFit()
					.frame(width: 158, height: 158)
					.shadow(color: Brand.primaryDark.opacity(0.2), radius: 26, y: 14)
					.offset(y: -4 * breath)
			}
			.frame(height: 220)
		}
		.allowsHitTesting(false)
	}

	private var executeHero: some View {
		TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
			let t = timeline.date.timeIntervalSinceReferenceDate
			let breath = 0.5 + 0.5 * sin(t * 2 * .pi / 5.5)
			ZStack {
				RadialGradient(
					colors: [
						Brand.primary.opacity(0.18 + 0.07 * breath),
						Brand.iceBlue.opacity(0.16),
						.clear,
					],
					center: .center,
					startRadius: 10,
					endRadius: 140
				)
				.frame(width: 280, height: 280)
				.scaleEffect(1 + 0.04 * breath)

				HStack(spacing: 18) {
					Image.robin
						.resizable()
						.scaledToFit()
						.frame(width: 112, height: 112)
						.shadow(color: Brand.primaryDark.opacity(0.18), radius: 18, y: 10)
					Capsule()
						.fill(
							LinearGradient(
								colors: [
									Brand.primary.opacity(0.15),
									Brand.primary.opacity(0.55 + 0.2 * breath),
									Brand.primary.opacity(0.15),
								],
								startPoint: .leading,
								endPoint: .trailing
							)
						)
						.frame(width: 42, height: 3)
					RoundedRectangle(cornerRadius: 14, style: .continuous)
						.fill(.white.opacity(0.72))
						.frame(width: 78, height: 58)
						.overlay {
							RoundedRectangle(cornerRadius: 14, style: .continuous)
								.stroke(Brand.stroke, lineWidth: 1)
						}
						.overlay {
							Image(systemName: "desktopcomputer")
								.font(.title3.weight(.semibold))
								.foregroundStyle(store.remote.macOnline ? Brand.success : Brand.primaryDark)
						}
						.shadow(color: Brand.primaryDark.opacity(0.1), radius: 12, y: 6)
				}
			}
			.frame(height: 180)
		}
		.allowsHitTesting(false)
	}

	@ViewBuilder
	private var stageHeader: some View {
		switch store.readyKind {
		case .setupIncomplete:
			StatusPill(text: "还差几步就能用", color: .orange)
		case .ready:
			StatusPill(text: "随时可以开始")
		case .sessionActive:
			StatusPill(text: "会话进行中", color: Brand.success)
		case .error:
			StatusPill(text: "需要处理", color: .orange)
		}
	}

	@ViewBuilder
	private var executeHeader: some View {
		if store.remote.macOnline {
			StatusPill(text: "Mac 已在线", color: Brand.success)
		} else if store.remote.signedIn {
			StatusPill(text: "Mac 当前离线", color: .orange)
		} else {
			StatusPill(text: "尚未连接 Mac", color: .orange)
		}
	}

	@ViewBuilder
	private var inputCopy: some View {
		VStack(spacing: 9) {
			switch store.readyKind {
			case let .setupIncomplete(missing):
				Text(setupTitle(missing))
					.font(.system(size: 26, weight: .bold))
					.tracking(-0.4)
				Text(setupSubtitle(missing))
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.frame(maxWidth: 260)
			case .ready:
				Text("说完，就是能直接用的文字")
					.font(.system(size: 24, weight: .bold))
					.tracking(-0.4)
				Text("去口头词、认专名，并按当前场景整理。")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.frame(maxWidth: 260)
			case let .sessionActive(remaining, mode):
				Text("键盘点麦克风，直接说")
					.font(.system(size: 26, weight: .bold))
					.tracking(-0.4)
				Text(
					mode == SessionMode.pip.rawValue
						? "\(mode) · 剩余 \(formatRemaining(remaining))。小窗可拖到屏幕边缘，回到刚才的 App 继续说。"
						: "\(mode) · 剩余 \(formatRemaining(remaining))，无需反复切换 App。"
				)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.frame(maxWidth: 260)
			case let .error(message, _):
				Text(message)
					.font(.title3.bold())
					.frame(maxWidth: 260)
			}
		}
		.multilineTextAlignment(.center)
		.fixedSize(horizontal: false, vertical: true)
		.frame(maxWidth: .infinity)
	}

	private var executeCopy: some View {
		VStack(spacing: 9) {
			if store.remote.macOnline {
				Text("在手机上说，Mac 来执行")
					.font(.system(size: 24, weight: .bold))
					.tracking(-0.4)
				Text("任务会在你的 Mac 上持续进行，合盖接电也可继续。")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.frame(maxWidth: 270)
			} else if store.remote.signedIn {
				Text("Mac 当前离线")
					.font(.system(size: 24, weight: .bold))
					.tracking(-0.4)
				Text("打开 Mac 上的知更后，就能继续从手机派发任务。")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.frame(maxWidth: 270)
			} else {
				Text("连接你的 Mac")
					.font(.system(size: 24, weight: .bold))
					.tracking(-0.4)
				Text("扫码后，就能从手机交代任务。")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.frame(maxWidth: 270)
			}
		}
		.multilineTextAlignment(.center)
		.fixedSize(horizontal: false, vertical: true)
		.frame(maxWidth: .infinity)
	}

	@ViewBuilder
	private var inputFooter: some View {
		VStack(spacing: 12) {
			switch store.readyKind {
			case .setupIncomplete:
				setupProgressRail
				PrimaryButton(title: setupActionTitle) {
					if !store.microphoneGranted {
						store.requestMicrophone { _ in }
					} else {
						store.reopenOnboarding(at: .keyboardSetup)
					}
				}
			case .ready, .sessionActive:
				usageStrip
			case let .error(_, actionTitle):
				PrimaryButton(title: actionTitle) {
					store.selectedTab = .me
				}
			}
		}
		.padding(14)
		.background(footerPanelBackground)
	}

	@ViewBuilder
	private var executeFooter: some View {
		VStack(spacing: 12) {
			if store.remote.macOnline {
				NavigationLink {
					RemoteWorkspaceView(remote: store.remote, threadId: nil)
				} label: {
					Text("开始新任务")
						.font(.body.weight(.semibold))
						.frame(maxWidth: .infinity, minHeight: 50)
						.foregroundStyle(.white)
						.background(Brand.primary, in: Capsule())
				}
				.buttonStyle(.plain)
			} else {
				NavigationLink {
					RemoteHomeView(remote: store.remote)
				} label: {
					Text(store.remote.signedIn ? "查看连接" : "连接 Mac")
						.font(.body.weight(.semibold))
						.frame(maxWidth: .infinity, minHeight: 50)
						.foregroundStyle(.white)
						.background(Brand.primary, in: Capsule())
				}
				.buttonStyle(.plain)
			}
		}
		.padding(14)
		.background(footerPanelBackground)
	}

	private var footerPanelBackground: some View {
		RoundedRectangle(cornerRadius: 22, style: .continuous)
			.fill(Brand.cloudWhite.opacity(0.86))
			.overlay {
				RoundedRectangle(cornerRadius: 22, style: .continuous)
					.stroke(Color.white.opacity(0.7), lineWidth: 1)
			}
			.shadow(color: Brand.primaryDark.opacity(0.06), radius: 12, y: 4)
	}

	private var setupProgressRail: some View {
		HStack(spacing: 0) {
			ForEach(Array(HomeSetupItem.allCases.enumerated()), id: \.element) { index, item in
				setupStep(item)
				if index != HomeSetupItem.allCases.count - 1 {
					Capsule()
						.fill(stepStatus(item) == .done ? Brand.success.opacity(0.35) : Brand.stroke)
						.frame(height: 2)
						.padding(.horizontal, 4)
						.padding(.bottom, 18)
				}
			}
		}
	}

	private func setupStep(_ item: HomeSetupItem) -> some View {
		let status = stepStatus(item)
		return VStack(spacing: 8) {
			ZStack {
				Circle()
					.fill(stepFill(status))
					.frame(width: 34, height: 34)
				if status == .done {
					Image(systemName: "checkmark")
						.font(.caption.weight(.bold))
						.foregroundStyle(Brand.success)
				} else {
					Text("\(stepNumber(item))")
						.font(.caption.weight(.bold))
						.foregroundStyle(status == .current ? .white : .secondary)
				}
			}
			Text(setupStepTitle(item))
				.font(.caption2.weight(status == .current ? .semibold : .medium))
				.foregroundStyle(status == .pending ? .tertiary : .primary)
				.lineLimit(1)
		}
		.frame(maxWidth: .infinity)
	}

	private var usageStrip: some View {
		HStack(spacing: 12) {
			Image(systemName: "keyboard")
				.font(.body.weight(.semibold))
				.foregroundStyle(Brand.primaryDark)
				.frame(width: 36, height: 36)
				.background(Brand.lavender.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
			VStack(alignment: .leading, spacing: 2) {
				Text(isSessionActive ? "即听即写已开启" : "从键盘开始")
					.font(.subheadline.weight(.semibold))
				Text(isSessionActive ? "任意 App 切到知更键盘，点麦克风即可。" : "打开微信，切换到知更键盘即可听写。")
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: 0)
		}
	}

	private var headerSessionControl: some View {
		HStack(spacing: 6) {
			Button {
				store.toggleInstantDictate()
			} label: {
				HStack(spacing: 7) {
					Text("即听即写")
						.font(.caption.weight(.semibold))
						.foregroundStyle(isSessionActive ? Brand.success : .secondary)
					ZStack(alignment: isSessionActive ? .trailing : .leading) {
						Capsule()
							.fill(isSessionActive ? Brand.success : Color(.systemGray4))
							.frame(width: 34, height: 22)
						Circle()
							.fill(.white)
							.frame(width: 16, height: 16)
							.padding(3)
							.shadow(color: .black.opacity(0.16), radius: 2, y: 1)
					}
					.animation(.snappy(duration: 0.22), value: isSessionActive)
				}
				.padding(.leading, 11)
				.padding(.trailing, 7)
				.frame(height: 38)
				.background(Brand.surface, in: Capsule())
				.overlay {
					Capsule().stroke(Brand.stroke, lineWidth: 1)
				}
			}
			.buttonStyle(.plain)
			.accessibilityLabel("即听即写")
			.accessibilityValue(isSessionActive ? "已开启" : "已关闭")

			Button {
				store.openSessionSettings()
			} label: {
				Image(systemName: "gearshape")
					.font(.system(size: 14, weight: .semibold))
					.foregroundStyle(.secondary)
					.frame(width: 38, height: 38)
					.background(Brand.surface, in: Circle())
					.overlay {
						Circle().stroke(Brand.stroke, lineWidth: 1)
					}
			}
			.buttonStyle(.plain)
			.accessibilityLabel("即听即写设置")
		}
	}

	private var isSessionActive: Bool {
		if case .sessionActive = store.readyKind { return true }
		return false
	}

	private var setupActionTitle: String {
		if !store.microphoneGranted { return "允许麦克风" }
		if !store.keyboardInstalled && store.heartbeat?.isFresh != true { return "去添加键盘" }
		if store.heartbeat?.hasFullAccess != true { return "去开启完全访问" }
		return "去设置"
	}

	private enum StepStatus { case done, current, pending }

	private func stepStatus(_ item: HomeSetupItem) -> StepStatus {
		let micDone = store.microphoneGranted
		let keyboardDone = store.keyboardInstalled || store.heartbeat?.isFresh == true
		let fullAccessDone = store.heartbeat?.isFresh == true && store.heartbeat?.hasFullAccess == true
		switch item {
		case .microphone:
			if micDone { return .done }
			return .current
		case .keyboard:
			if !micDone { return .pending }
			if keyboardDone { return .done }
			return .current
		case .fullAccess:
			if !keyboardDone { return .pending }
			if fullAccessDone { return .done }
			return .current
		}
	}

	private func stepFill(_ status: StepStatus) -> Color {
		switch status {
		case .done: Brand.success.opacity(0.16)
		case .current: Brand.primary
		case .pending: Color(.tertiarySystemFill)
		}
	}

	private func stepNumber(_ item: HomeSetupItem) -> Int {
		switch item {
		case .microphone: 1
		case .keyboard: 2
		case .fullAccess: 3
		}
	}

	private func setupTitle(_ missing: [HomeSetupItem]) -> String {
		if missing.contains(.microphone) { return "先允许麦克风" }
		if missing.contains(.keyboard) { return "添加知更键盘" }
		if missing.contains(.fullAccess) { return "开启完全访问" }
		return "完成键盘设置"
	}

	private func setupSubtitle(_ missing: [HomeSetupItem]) -> String {
		if missing.contains(.microphone) {
			return "听写需要麦克风。待机不会录音，只有点麦才开始。"
		}
		if missing.contains(.keyboard) {
			return "在系统键盘列表里加上知更，就能在微信等 App 里听写。"
		}
		if missing.contains(.fullAccess) {
			return "在设置里开启后，再切到知更键盘一次，App 才能确认完全访问。"
		}
		return "完成后就能在其他 App 里听写。"
	}

	private func setupStepTitle(_ item: HomeSetupItem) -> String {
		switch item {
		case .microphone: "麦克风"
		case .keyboard: "键盘"
		case .fullAccess: "完全访问"
		}
	}

	private func formatRemaining(_ seconds: Int) -> String {
		let m = seconds / 60
		let s = seconds % 60
		return String(format: "%d:%02d", m, s)
	}
}

struct SessionSheet: View {
	@Bindable var store: AppStore
	@Environment(\.dismiss) private var dismiss

	private var isRestarting: Bool {
		store.keyboardSession.isRunning || store.sessionActiveUntil != nil
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack {
				Text("即听即写")
					.font(.headline)
				Spacer()
				Button("关闭") { dismiss() }
					.font(.subheadline)
			}

			Text("开启后，在任意 App 点键盘声波即可听写，不用跳回知更。")
				.font(.footnote)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)

			VStack(alignment: .leading, spacing: 8) {
				Text("模式")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
				Picker("模式", selection: Binding(
					get: { store.sessionMode },
					set: { store.setSessionMode($0) }
				)) {
					ForEach(SessionMode.allCases) { mode in
						Text(mode.rawValue).tag(mode)
					}
				}
				.pickerStyle(.segmented)
				Text(modeHint)
					.font(.caption2)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			VStack(alignment: .leading, spacing: 8) {
				Text("时长")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
				Picker("时长", selection: Binding(
					get: { store.sessionDuration },
					set: { store.setSessionDuration($0) }
				)) {
					ForEach(SessionDuration.allCases) { d in
						Text(d.label).tag(d)
					}
				}
				.pickerStyle(.segmented)
			}

			Button {
				store.requestMicThenStart()
			} label: {
				Text(isRestarting ? "应用并重启" : "开启")
					.font(.body.weight(.semibold))
					.frame(maxWidth: .infinity)
					.padding(.vertical, 12)
			}
			.buttonStyle(.borderedProminent)
			.tint(Brand.primary)
		}
		.padding(20)
	}

	private var modeHint: String {
		switch store.sessionMode {
		case .pip:
			return "推荐。画中画保活，空闲关麦，小窗可拖到边缘隐藏。"
		case .liveActivity:
			return "后台音频保活，空闲仍占麦（橙点），耗电更高。"
		}
	}
}

struct DictationFullScreen: View {
	@Bindable var store: AppStore
	@Environment(\.dismiss) private var dismiss
	@State private var session: DictationSessionController?

	var body: some View {
		NavigationStack {
			Group {
				if let session {
					dictationBody(session)
				} else {
					ProgressView()
				}
			}
			.padding()
			.navigationTitle("听写")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("关闭") {
						session?.teardown()
						dismiss()
					}
				}
				ToolbarItem(placement: .topBarTrailing) {
					if session?.phase == .listening {
						Text("\(session?.elapsed ?? 0)s")
							.monospacedDigit()
					}
				}
			}
		}
		.onAppear {
			if session == nil {
				session = DictationSessionController(store: store)
			}
		}
		.onDisappear {
			session?.teardown()
		}
	}

	@ViewBuilder
	private func dictationBody(_ session: DictationSessionController) -> some View {
		VStack(spacing: 20) {
			Text(session.statusMessage)
				.font(.headline)
				.foregroundStyle(session.phase == .failed ? .orange : .primary)
				.multilineTextAlignment(.center)

			if session.phase == .listening {
				VoiceLevelWave(level: session.level, active: true, color: .orange)
			}

			TextEditor(text: Bindable(session).draft)
				.font(.title3)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
				.padding(8)
				.background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
				.overlay {
					RoundedRectangle(cornerRadius: 14).stroke(Brand.stroke, lineWidth: 1)
				}
				.disabled(session.phase == .listening || session.phase == .processing)

			Button {
				session.toggle()
			} label: {
				Image(systemName: session.phase == .listening ? "stop.fill" : "mic.fill")
					.font(.title)
					.foregroundStyle(.white)
					.frame(width: 80, height: 80)
					.background(session.phase == .listening ? Color.orange : Brand.primary)
					.clipShape(Circle())
					.scaleEffect(session.phase == .listening ? 1 + session.level * 0.04 : 1)
			}
			.disabled(session.phase == .processing)

			if session.phase == .done || session.phase == .incomplete {
				HStack(spacing: 16) {
					Button("复制") { UIPasteboard.general.string = session.draft }
					Button("再说一次") { session.reset() }
				}
			}
		}
	}
}

private struct VoiceLevelWave: View {
	let level: Double
	let active: Bool
	let color: Color

	var body: some View {
		TimelineView(.animation(minimumInterval: 0.05, paused: !active)) { timeline in
			let heights = VoiceWaveformMath.barHeights(
				level: active ? level : 0,
				time: timeline.date.timeIntervalSinceReferenceDate
			)
			HStack(spacing: 2) {
				ForEach(heights.indices, id: \.self) { index in
					Capsule()
						.fill(color.opacity(active ? 0.95 : 0.62))
						.frame(width: 3, height: heights[index])
				}
			}
			.frame(height: 24)
		}
	}
}
