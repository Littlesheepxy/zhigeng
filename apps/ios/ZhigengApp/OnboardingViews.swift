import SwiftUI
import UIKit
import ZhigengCore

struct OnboardingFlow: View {
	@Bindable var store: AppStore
	@State private var maxUnlockedRawValue = 0

	var body: some View {
		ZStack(alignment: .top) {
			Brand.cloudWhite.ignoresSafeArea()
			if store.onboardingStep == .brandWelcome || store.onboardingStep == .readyBrand {
				BrandHeroMist(ready: store.onboardingStep == .readyBrand)
				.ignoresSafeArea()
			}
			TabView(selection: stepBinding) {
				BrandWelcomeView(store: store)
					.tag(OnboardingStep.brandWelcome)
				TryLearnView(store: store)
					.tag(OnboardingStep.tryLearn)
				KeyboardSetupView(store: store)
					.tag(OnboardingStep.keyboardSetup)
				ReadyBrandView(store: store)
					.tag(OnboardingStep.readyBrand)
			}
			.tabViewStyle(.page(indexDisplayMode: .never))

			HStack(spacing: 7) {
				ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
					Capsule()
						.fill(step.rawValue <= store.onboardingStep.rawValue ? Brand.primary : .black.opacity(0.1))
						.frame(width: step == store.onboardingStep ? 26 : 8, height: 7)
						.animation(.spring(response: 0.28), value: store.onboardingStep)
				}
			}
			.padding(.top, 8)
		}
		.onAppear {
			maxUnlockedRawValue = max(maxUnlockedRawValue, store.onboardingStep.rawValue)
		}
		.onChange(of: store.onboardingStep) { _, step in
			maxUnlockedRawValue = max(maxUnlockedRawValue, step.rawValue)
		}
	}

	private var stepBinding: Binding<OnboardingStep> {
		Binding(
			get: { store.onboardingStep },
			set: { step in
				guard step.rawValue <= maxUnlockedRawValue else { return }
				store.setOnboardingStep(step)
			}
		)
	}
}

struct BrandWelcomeView: View {
	@Bindable var store: AppStore
	@State private var activeAbility = 0

	private let abilities = [
		Ability(
			title: "输入",
			icon: "waveform",
			scene: "消息 · 通用模式",
			before: "嗯，帮我跟小杨说一下，就是 ARR 的表我今晚改完……",
			after: "帮我跟小杨说一下，ARR 的表我今晚改完，明早发给他。",
			tags: ["轻声识别", "去除口头词", "按消息整理"]
		),
		Ability(
			title: "代回",
			icon: "text.bubble.fill",
			scene: "选中文字 · 知更代回",
			before: "对方问：明早能发我吗？",
			after: "可以，我今晚整理好 ARR 表，明早发给你。",
			tags: ["理解上下文", "保持你的语气"]
		),
		Ability(
			title: "执行",
			icon: "bolt.fill",
			scene: "iPhone 发起 · Mac 执行",
			before: "把刚才的内容整理成待办，明早提醒我。",
			after: "已生成待办，等待你确认后交给在线 Mac。",
			tags: ["先确认", "跨设备接续"]
		),
	]

	var body: some View {
		GeometryReader { geometry in
			ScrollView {
				VStack(spacing: 12) {
					ZStack {
						Image.robin
							.resizable()
							.scaledToFit()
							.frame(width: 168, height: 168)
					}
					.frame(height: 237)
					.clipped()

					VStack(spacing: 7) {
						Text("知你所言，更懂你意")
							.font(.title.bold())
						Text("说得更自然，写得更清楚，越用越像你。")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}

					HStack(spacing: 4) {
						ForEach(abilities.indices, id: \.self) { index in
							Button {
								withAnimation(.easeOut(duration: 0.2)) {
									activeAbility = index
								}
							} label: {
								Label("知更\(abilities[index].title)", systemImage: abilities[index].icon)
									.font(.caption.weight(.semibold))
									.foregroundStyle(activeAbility == index ? Brand.primaryDark : .secondary)
									.frame(maxWidth: .infinity, minHeight: 40)
									.background(
										activeAbility == index ? Brand.surface : .clear,
										in: RoundedRectangle(cornerRadius: 12, style: .continuous)
									)
									.shadow(
										color: activeAbility == index ? Brand.primaryDark.opacity(0.1) : .clear,
										radius: 7,
										y: 2
									)
							}
							.buttonStyle(.plain)
						}
					}
					.padding(4)
					.background(Color(red: 0.949, green: 0.953, blue: 0.973), in: RoundedRectangle(cornerRadius: 16))

					proofCard(abilities[activeAbility])
						.id(activeAbility)
						.transition(.opacity.combined(with: .move(edge: .trailing)))

					Spacer(minLength: 12)

					PrimaryButton(title: "先试一句") {
						store.setOnboardingStep(.tryLearn)
					}
					Button("稍后设置") {
						store.completeOnboarding()
					}
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.frame(minHeight: 44)
				}
				.padding(.horizontal, 20)
				.padding(.bottom, 16)
				.frame(minHeight: geometry.size.height, alignment: .top)
			}
			.scrollIndicators(.hidden)
		}
	}

	private func proofCard(_ ability: Ability) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 7) {
				Circle()
					.fill(Color(red: 1, green: 0.494, blue: 0.306))
					.frame(width: 7, height: 7)
				Text(ability.scene)
					.font(.caption.weight(.semibold))
					.foregroundStyle(Brand.primaryDark)
			}
			Text(ability.before)
				.font(.subheadline)
				.foregroundStyle(.secondary)
			HStack(spacing: 6) {
				Text("知更理解后")
				.font(.caption.weight(.semibold))
				.foregroundStyle(Brand.primary)
				Image(systemName: "arrow.right")
					.font(.caption.bold())
					.foregroundStyle(Brand.primary)
			}
			Text(ability.after)
				.font(.body.weight(.medium))
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 7) {
					ForEach(ability.tags, id: \.self) { tag in
						Label(tag, systemImage: "checkmark.circle.fill")
							.font(.caption2.weight(.semibold))
							.foregroundStyle(Brand.primaryDark)
							.padding(.horizontal, 7)
							.padding(.vertical, 4)
							.background(Brand.primary.opacity(0.065), in: Capsule())
					}
				}
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 14)
		.background {
			ZStack(alignment: .topTrailing) {
				LinearGradient(
					colors: [Brand.surface, Color(red: 0.973, green: 0.973, blue: 1)],
					startPoint: .topLeading,
					endPoint: .bottomTrailing
				)
				Circle()
					.fill(Color(red: 0.875, green: 0.969, blue: 0.949).opacity(0.38))
					.frame(width: 150, height: 150)
					.blur(radius: 36)
					.offset(x: 55, y: -60)
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.stroke(Brand.primary.opacity(0.09), lineWidth: 1)
		}
		.shadow(color: Brand.primaryDark.opacity(0.045), radius: 16, y: 7)
	}

	private struct Ability {
		let title: String
		let icon: String
		let scene: String
		let before: String
		let after: String
		let tags: [String]
	}
}

struct TryLearnView: View {
	@Bindable var store: AppStore
	@State private var phase: Phase = .idle
	@State private var elapsed = 0
	@State private var timer: Timer?
	@State private var showLearnSheet = false
	@StateObject private var audioMeter = AudioCaptureEngine()

	private enum Phase {
		case idle, needPermission, audioUnavailable, listening, processing, done
	}

	private let sampleClean = "帮我跟小杨说一下，ARR 的表我今晚改完，明早发给他。"

	var body: some View {
		GeometryReader { geometry in
			ScrollView {
				VStack(spacing: 16) {
					Image.robin
						.resizable()
						.scaledToFit()
						.frame(width: 46, height: 46)
						.padding(.top, 28)
					VStack(spacing: 6) {
						Text("轻声也能听清")
							.font(.title.bold())
						statusBlock
					}

					ZStack {
						VoiceMistBackdrop()
						VStack(spacing: 28) {
							HStack(spacing: 7) {
								if phase == .listening {
									VoiceLevelWave(level: audioMeter.level, active: true, color: .orange)
								} else {
									Image(systemName: "mic.fill")
								}
								Text(phase == .listening ? "保持这个音量就好" : "像在安静办公室里一样说")
							}
							.font(.caption.weight(.semibold))
							.foregroundStyle(phase == .listening ? .orange : Brand.primaryDark)
							.padding(.horizontal, 10)
							.padding(.vertical, 7)
							.background(.white.opacity(0.78), in: Capsule())
							.overlay {
								Capsule()
									.stroke(
										(phase == .listening ? Color.orange : Brand.primary).opacity(0.14),
										lineWidth: 1
									)
							}
							Button(action: toggle) {
								Image(systemName: phase == .listening ? "stop.fill" : "mic.fill")
									.font(.system(size: 31, weight: .bold))
									.foregroundStyle(.white)
									.frame(width: 92, height: 92)
									.background(phase == .listening ? Color.orange : Brand.primary)
									.clipShape(Circle())
									.shadow(
										color: (phase == .listening ? Color.orange : Brand.primary).opacity(0.28),
										radius: 22 + audioMeter.level * 10,
										y: 10
									)
							}
							.scaleEffect(phase == .listening ? 1 + audioMeter.level * 0.035 : 1)
							.disabled(phase == .processing || phase == .done)
						}
					}
					.frame(width: 300, height: 260)
					.clipped()
					.padding(.top, 20)
					.accessibilityLabel(phase == .listening ? "结束听写" : "开始听写")

					if phase == .idle {
						Label("轻声试试：“嗯，帮我跟小杨说，ARR 的表今晚改完”", systemImage: "bubble.left")
							.font(.caption)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
					}

					if phase == .done {
						ZhigengCard {
							Text("消息 · 通用模式")
								.font(.caption.weight(.semibold))
								.foregroundStyle(Brand.primary)
							TextEditor(text: $store.tryLearnDraft)
								.frame(minHeight: 100)
								.scrollContentBackground(.hidden)
							ScrollView(.horizontal, showsIndicators: false) {
								HStack {
									ForEach(["演示：轻声识别", "演示：去除口头词", "演示：按消息整理"], id: \.self) { tag in
										CapabilityChip(text: tag)
									}
								}
							}
							if store.recentLearnedTexts.contains("小杨") {
								Text("已记住「小杨」，语音和拼音都会优先使用")
									.font(.caption)
									.foregroundStyle(Brand.success)
							}
							}
					}

					Spacer(minLength: 18)

					if phase == .done {
						PrimaryButton(title: "在其他 App 里使用") {
							store.setOnboardingStep(.keyboardSetup)
						}
						Button("再试一次") {
							phase = .idle
							store.tryLearnDraft = ""
							store.pendingLearnTerm = nil
						}
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.frame(minHeight: 44)
					} else {
						PrimaryButton(
							title: phase == .listening
								? "点一下结束"
								: phase == .processing ? "正在整理…" : "点一下开始",
							enabled: phase != .processing
						) {
							toggle()
						}
					}
				}
				.padding(.horizontal, 20)
				.padding(.bottom, 18)
				.frame(minHeight: geometry.size.height, alignment: .top)
			}
			.scrollIndicators(.hidden)
		}
		.onDisappear {
			timer?.invalidate()
			audioMeter.stop()
		}
		.sheet(isPresented: $showLearnSheet) {
			if let term = store.pendingLearnTerm {
				ScrollView {
					VStack(spacing: 16) {
						Capsule()
							.fill(.secondary.opacity(0.3))
							.frame(width: 38, height: 5)
						Text("要记住「\(term)」吗？")
							.font(.title2.bold())
						Text("语音和拼音都会优先使用。可随时在「懂我」里撤销。")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
						PrimaryButton(title: "记住") {
							store.confirmPendingLearn()
							showLearnSheet = false
						}
						Button("仅改这次") {
							store.skipPendingLearn()
							showLearnSheet = false
						}
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.frame(minHeight: 44)
					}
					.padding(24)
				}
				.presentationDetents([.medium, .large])
			}
		}
	}

	@ViewBuilder
	private var statusBlock: some View {
		switch phase {
		case .idle:
			Text("不用提高音量，轻轻说就好 · 交互演示")
				.foregroundStyle(.secondary)
		case .needPermission:
			VStack(alignment: .leading, spacing: 8) {
				Text("需要麦克风才能试说")
				PrimaryButton(title: "允许麦克风") {
					store.requestMicrophone { granted in
						phase = granted ? .idle : .needPermission
					}
				}
				SecondaryButton(title: "打开知更设置") {
					store.openSystemSettings()
				}
			}
		case .audioUnavailable:
			Text("麦克风暂时不可用，点一下重试")
				.foregroundStyle(.orange)
		case .listening:
			Text("演示录音中 · \(elapsed)s")
				.foregroundStyle(.orange)
		case .processing:
			Text("正在理解并整理")
				.foregroundStyle(Brand.primary)
		case .done:
			Text("演示完成：轻声整理效果")
				.foregroundStyle(Brand.success)
		}
	}

	private func toggle() {
		switch phase {
		case .idle:
			if !store.microphoneGranted {
				phase = .needPermission
				store.requestMicrophone { granted in
					if granted { startListening() }
				}
				return
			}
			startListening()
		case .listening:
			finishListening()
		case .audioUnavailable:
			startListening()
		default:
			break
		}
	}

	private func startListening() {
		guard audioMeter.start(onPCM: { _ in }) else {
			phase = .audioUnavailable
			return
		}
		phase = .listening
		elapsed = 0
		timer?.invalidate()
		timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
			Task { @MainActor in elapsed += 1 }
		}
	}

	private func finishListening() {
		timer?.invalidate()
		audioMeter.stop()
		phase = .processing
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
			// ponytail: ASR not wired yet — demo path is labeled as example, not claimed live ASR.
			store.finishTryLearnDemo()
			store.tryLearnDraft = sampleClean
			phase = .done
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
				showLearnSheet = store.pendingLearnTerm != nil
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

struct KeyboardSetupView: View {
	@Bindable var store: AppStore
	@State private var practiceText = ""
	@State private var pollTask: Task<Void, Never>?
	@FocusState private var practiceFocused: Bool
	@Environment(\.scenePhase) private var scenePhase

	var body: some View {
		GeometryReader { geometry in
			ScrollView {
				VStack(spacing: 16) {
				Image.robin
					.resizable()
					.scaledToFit()
					.frame(width: 46, height: 46)
					.padding(.top, 28)
				VStack(spacing: 6) {
					Text("设置知更键盘")
						.font(.title.bold())
					Text("按顺序完成三步，才能在其他 App 里用知更")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}

				VStack(alignment: .leading, spacing: 8) {
					Text("你习惯哪种中文键盘？")
						.font(.subheadline.weight(.semibold))
					Picker(
						"中文键盘布局",
						selection: Binding(
							get: { store.chineseKeyboardLayout },
							set: { store.setChineseKeyboardLayout($0) }
						)
					) {
						Text("九键").tag(ChineseKeyboardLayout.nineKey)
						Text("全键盘").tag(ChineseKeyboardLayout.fullKeyboard)
					}
					.pickerStyle(.segmented)
					Text("知更会按这个习惯安排语音页的删除键。")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.padding(12)
				.background(Brand.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

				VStack(spacing: 10) {
					timelineRow(
						number: 1,
						title: "添加键盘",
						detail: "设置 → 通用 → 键盘 → 添加新键盘 → 知更",
						done: keyboardDetected,
						active: !keyboardDetected
					) {
						store.openKeyboardSettings()
					}
					timelineRow(
						number: 2,
						title: "允许完全访问",
						detail: "设置里开启后，还需在下方切到知更一次，App 才能确认",
						done: fullAccessEnabled,
						active: keyboardDetected && !fullAccessEnabled
					) {
						if keyboardDetected {
							practiceFocused = true
						} else {
							store.openKeyboardSettings()
						}
					}
					timelineRow(
						number: 3,
						title: "切换到知更",
						detail: "点下方输入框，长按地球键选择知更",
						done: canContinue,
						active: fullAccessEnabled && !canContinue
					) {
						practiceFocused = true
					}
				}

				VStack(alignment: .leading, spacing: 8) {
					Text(fullAccessEnabled ? "在这里试打几个字验证" : "开启完全访问后，在这里切到知更确认")
						.font(.subheadline)
					TextEditor(text: $practiceText)
						.focused($practiceFocused)
						.frame(height: 56)
						.scrollContentBackground(.hidden)
						.padding(10)
						.background(Brand.surface)
						.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
						.overlay(
							RoundedRectangle(cornerRadius: 14)
								.stroke(practiceFocused ? Brand.primary : Brand.stroke, lineWidth: practiceFocused ? 2 : 1)
						)
					Text(
						fullAccessEnabled
							? "长按地球键 → 选择知更。完全访问只用于主 App 与键盘交换听写结果。"
							: "系统不会主动通知 App。你切到知更键盘时，它才会把「完全访问」状态写回来。"
					)
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				Spacer(minLength: 18)

				if canContinue {
					PrimaryButton(title: "继续") {
						store.setOnboardingStep(.readyBrand)
					}
				} else {
					PrimaryButton(title: currentActionTitle) {
						if !keyboardDetected {
							store.openKeyboardSettings()
						} else if !fullAccessEnabled {
							store.openKeyboardSettings()
							// After returning, user still must switch keyboard once — focus the field.
							DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
								practiceFocused = true
							}
						} else {
							practiceFocused = true
						}
					}
					Button("暂时跳过，稍后再验证") {
						store.setOnboardingStep(.readyBrand)
					}
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.frame(minHeight: 44)
				}
				}
				.padding(.horizontal, 20)
				.padding(.bottom, 16)
				.frame(minHeight: geometry.size.height, alignment: .top)
			}
			.scrollIndicators(.hidden)
		}
		.onAppear {
			store.reloadSharedState()
			startPolling()
		}
		.onDisappear {
			pollTask?.cancel()
			pollTask = nil
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .active {
				store.reloadSharedState()
				startPolling()
				if keyboardDetected && !fullAccessEnabled {
					practiceFocused = true
				}
			}
		}
	}

	private var canContinue: Bool {
		fullAccessEnabled
	}

	private var keyboardDetected: Bool {
		store.keyboardInstalled || store.heartbeat?.isFresh == true
	}

	private var fullAccessEnabled: Bool {
		guard let heartbeat = store.heartbeat, heartbeat.isFresh else { return false }
		return heartbeat.hasFullAccess
	}

	private var currentActionTitle: String {
		if !keyboardDetected { return "去系统设置添加" }
		if !fullAccessEnabled { return "去开启完全访问" }
		return "去验证输入"
	}

	private func startPolling() {
		pollTask?.cancel()
		pollTask = Task { @MainActor in
			while !Task.isCancelled {
				store.reloadSharedState()
				try? await Task.sleep(nanoseconds: 1_000_000_000)
			}
		}
	}

	private func timelineRow(
		number: Int,
		title: String,
		detail: String,
		done: Bool,
		active: Bool,
		action: @escaping () -> Void
	) -> some View {
		Button(action: action) {
			HStack(spacing: 12) {
				Group {
					if done {
						Image(systemName: "checkmark.circle.fill")
							.foregroundStyle(Brand.success)
					} else {
						Text("\(number)")
							.foregroundStyle(active ? .white : .secondary)
							.background {
								Circle()
									.fill(active ? Brand.primary : .black.opacity(0.07))
									.frame(width: 28, height: 28)
							}
					}
				}
				.font(.subheadline.bold())
				.frame(width: 30, height: 30)
				VStack(alignment: .leading, spacing: 3) {
					Text(title)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.primary)
					Text(detail)
						.font(.caption2)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.leading)
				}
				Spacer()
				Text(done ? "已完成" : active ? "去完成" : "等待中")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(done ? Brand.success : active ? Brand.primary : .secondary)
			}
			.padding(12)
			.background(active ? Brand.primary.opacity(0.06) : Brand.surface.opacity(done ? 1 : 0.62))
			.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.stroke(active ? Brand.primaryDark : Brand.stroke.opacity(done ? 1 : 0.45), lineWidth: active ? 1.5 : 1)
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.disabled(!active && !done)
	}
}

struct ReadyBrandView: View {
	@Bindable var store: AppStore

	var body: some View {
		GeometryReader { geometry in
			ScrollView {
				VStack(spacing: 22) {
					ZStack {
						Image.robin
							.resizable()
							.scaledToFit()
							.frame(width: 172, height: 172)
					}
					.frame(height: 300)

					VStack(spacing: 7) {
						Text("准备就绪")
							.font(.caption.weight(.bold))
							.foregroundStyle(Brand.primary)
							.textCase(.uppercase)
						Text("你的知更准备好了")
							.font(.title.bold())
						Text("从这次开始，它会越来越懂你的词和表达。")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
					}

					HStack(spacing: 8) {
						if !store.recentLearnedTexts.isEmpty {
							CapabilityChip(text: "已记住「\(store.recentLearnedTexts[0])」")
						}
						if store.heartbeat?.isFresh == true {
							CapabilityChip(text: "键盘已连接")
						}
						if store.recentLearnedTexts.isEmpty && store.heartbeat?.isFresh != true {
							CapabilityChip(text: "可以随时回来设置")
						}
					}

					Spacer(minLength: 18)

					PrimaryButton(title: "开始使用") {
						store.completeOnboarding()
					}
				}
				.padding(.horizontal, 20)
				.padding(.bottom, 28)
				.frame(minHeight: geometry.size.height, alignment: .top)
			}
			.scrollIndicators(.hidden)
		}
	}
}
