import AVFoundation
import Foundation
import Observation
import os.log
import UIKit
import ZhigengCore

enum OnboardingStep: Int, Codable, CaseIterable {
	case brandWelcome
	case tryLearn
	case keyboardSetup
	case readyBrand
}

enum AppTab: Hashable {
	case home
	case activity
	case lexicon
	case me
}

enum SessionMode: String, CaseIterable, Identifiable {
	case pip = "省电待命"
	case liveActivity = "长时间待命"

	var id: String { rawValue }

	var protocolMode: DictationSessionMode {
		switch self {
		case .pip: .pip
		case .liveActivity: .liveActivity
		}
	}
}

enum SessionDuration: Int, CaseIterable, Identifiable {
	case five = 5
	case fifteen = 15
	case sixty = 60

	var id: Int { rawValue }
	var label: String {
		switch self {
		case .five: "5 分钟"
		case .fifteen: "15 分钟"
		case .sixty: "1 小时"
		}
	}
}

@Observable
@MainActor
final class AppStore {
	private let defaults: UserDefaults
	private let bridge: AppGroupBridge
	private let historyURL: URL
	let remote: RemoteStore

	var onboardingCompleted: Bool
	var onboardingStep: OnboardingStep
	var selectedTab: AppTab = .home
	var microphoneGranted: Bool
	var heartbeat: KeyboardHeartbeat?
	var lexicon: PersonalLexicon
	var history: [DictationHistoryItem] = []
	var sessionActiveUntil: TimeInterval?
	var sessionMode: SessionMode = .pip
	var sessionDuration: SessionDuration = .fifteen
	/// User has confirmed mode/duration at least once — toggle can start without sheet.
	var sessionConfigured: Bool
	var showSessionSheet = false
	var showDictation = false
	var pendingDictationRequestId: String?
	var showAddTerm = false
	var editingHistoryItem: DictationHistoryItem?
	var pendingLearnTerm: String?
	var tryLearnDraft = ""
	var serviceError: String?
	/// Fold asr-proxy base (no path). Simulator defaults to localhost; device uses saved/LAN URL.
	var asrBaseURL: String

	@ObservationIgnored
	private var _keyboardSession: KeyboardSessionController?

	var keyboardSession: KeyboardSessionController {
		if let existing = _keyboardSession { return existing }
		let created = KeyboardSessionController(store: self)
		_keyboardSession = created
		return created
	}

	init(
		defaults: UserDefaults = .standard,
		bridge: AppGroupBridge = AppGroupBridge(),
		historyDirectory: URL? = nil
	) {
		self.defaults = defaults
		self.bridge = bridge
		self.remote = RemoteStore()
		let dir = historyDirectory
			?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
		self.historyURL = dir.appendingPathComponent("dictation_history.json")
		self.onboardingCompleted = defaults.bool(forKey: "onboardingCompleted")
		if let raw = defaults.string(forKey: "onboardingStep"),
		   let step = OnboardingStep(rawValue: Int(raw) ?? 0) {
			self.onboardingStep = step
		} else {
			self.onboardingStep = .brandWelcome
		}
		if let saved = defaults.string(forKey: "asrBaseURL"), !saved.isEmpty {
			self.asrBaseURL = saved
		} else {
			#if targetEnvironment(simulator)
			self.asrBaseURL = "ws://127.0.0.1:3003"
			#else
			self.asrBaseURL = AsrStreamClient.defaultBaseURL
			#endif
		}
		#if DEBUG
		if let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "-preview-onboarding-step"),
		   ProcessInfo.processInfo.arguments.indices.contains(flag + 1),
		   let rawValue = Int(ProcessInfo.processInfo.arguments[flag + 1]),
		   let step = OnboardingStep(rawValue: rawValue) {
			self.onboardingCompleted = false
			self.onboardingStep = step
		}
		if let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "-preview-main-tab"),
		   ProcessInfo.processInfo.arguments.indices.contains(flag + 1),
		   let rawValue = Int(ProcessInfo.processInfo.arguments[flag + 1]) {
			self.onboardingCompleted = true
			self.selectedTab = [.home, .activity, .lexicon, .me][min(max(rawValue, 0), 3)]
		}
		if let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "-asr-base-url"),
		   ProcessInfo.processInfo.arguments.indices.contains(flag + 1) {
			self.asrBaseURL = ProcessInfo.processInfo.arguments[flag + 1]
		}
		#endif
		self.microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
		self.lexicon = PersonalLexicon()
		self.sessionConfigured = defaults.bool(forKey: "sessionConfigured")
		if let modeRaw = defaults.string(forKey: "sessionMode"),
		   let mode = SessionMode(rawValue: modeRaw) {
			self.sessionMode = mode
		}
		if let durationRaw = defaults.object(forKey: "sessionDuration") as? Int,
		   let duration = SessionDuration(rawValue: durationRaw) {
			self.sessionDuration = duration
		}
		reloadSharedState()
		loadHistory()
	}

	func setAsrBaseURL(_ url: String) {
		let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
		asrBaseURL = trimmed
		defaults.set(trimmed, forKey: "asrBaseURL")
	}

	var keyboardInstalled: Bool {
		KeyboardPresence.isInstalled()
	}

	var readyKind: HomeReadyKind {
		HomeReadyState.resolve(
			microphoneGranted: microphoneGranted,
			heartbeat: heartbeat,
			sessionActiveUntil: sessionActiveUntil,
			sessionModeLabel: sessionMode.rawValue,
			serviceError: serviceError,
			keyboardInstalled: keyboardInstalled
		)
	}

	var recentHistory: [DictationHistoryItem] {
		Array(history.prefix(3))
	}

	var recentLearnedTexts: [String] {
		lexicon.allTerms
			.sorted { $0.lastUsedAt > $1.lastUsedAt }
			.prefix(3)
			.map(\.text)
	}

	func reloadSharedState() {
		heartbeat = (try? bridge.readHeartbeat()) ?? readDefaultsHeartbeat()
		if let data = try? bridge.readLexiconData(),
		   let loaded = try? PersonalLexicon.decode(from: data) {
			lexicon = loaded
		}
		if let session = try? bridge.readSession(), session.isActive {
			sessionActiveUntil = session.activeUntil
		} else {
			sessionActiveUntil = nil
		}
		microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
	}

	private func readDefaultsHeartbeat() -> KeyboardHeartbeat? {
		guard let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName),
		      defaults.object(forKey: "keyboard.lastSeenAt") != nil
		else { return nil }
		return KeyboardHeartbeat(
			lastSeenAt: defaults.double(forKey: "keyboard.lastSeenAt"),
			hasFullAccess: defaults.bool(forKey: "keyboard.hasFullAccess"),
			extensionVersion: defaults.string(forKey: "keyboard.extensionVersion") ?? "0.1.0"
		)
	}

	func completeOnboarding() {
		onboardingCompleted = true
		defaults.set(true, forKey: "onboardingCompleted")
		selectedTab = .home
	}

	func setOnboardingStep(_ step: OnboardingStep) {
		onboardingStep = step
		defaults.set(String(step.rawValue), forKey: "onboardingStep")
	}

	func requestMicrophone(completion: @escaping @MainActor (Bool) -> Void) {
		AVAudioApplication.requestRecordPermission { granted in
			Task { @MainActor in
				self.microphoneGranted = granted
				completion(granted)
			}
		}
	}

	func openSystemSettings() {
		guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
		UIApplication.shared.open(url)
	}

	/// Open the public, stable Settings page for Zhigeng.
	func openKeyboardSettings() {
		openSystemSettings()
	}

	func setSessionMode(_ mode: SessionMode) {
		sessionMode = mode
		defaults.set(mode.rawValue, forKey: "sessionMode")
	}

	func setSessionDuration(_ duration: SessionDuration) {
		sessionDuration = duration
		defaults.set(duration.rawValue, forKey: "sessionDuration")
	}

	func startSession(initialRequestId: String? = nil, returnBundleId: String? = nil) {
		showSessionSheet = false
		serviceError = nil
		defaults.set(sessionMode.rawValue, forKey: "sessionMode")
		defaults.set(sessionDuration.rawValue, forKey: "sessionDuration")
		keyboardSession.start(
			mode: sessionMode.protocolMode,
			durationMinutes: sessionDuration.rawValue,
			initialRequestId: initialRequestId,
			returnBundleId: returnBundleId
		)
		if let error = keyboardSession.lastError {
			serviceError = error
			sessionActiveUntil = nil
		} else {
			sessionActiveUntil = keyboardSession.activeUntil
			sessionConfigured = true
			defaults.set(true, forKey: "sessionConfigured")
		}
	}

	func endSession() {
		keyboardSession.end()
		sessionActiveUntil = nil
		serviceError = nil
	}

	/// Home toggle: off→on uses last prefs after first setup; on→off ends session.
	func toggleInstantDictate() {
		if keyboardSession.isRunning || sessionActiveUntil != nil {
			endSession()
			return
		}
		if sessionConfigured {
			requestMicThenStart()
		} else {
			showSessionSheet = true
		}
	}

	func openSessionSettings() {
		showSessionSheet = true
	}

	func requestMicThenStart(initialRequestId: String? = nil, returnBundleId: String? = nil) {
		if microphoneGranted {
			startSession(initialRequestId: initialRequestId, returnBundleId: returnBundleId)
		} else {
			requestMicrophone { [weak self] granted in
				if granted {
					self?.startSession(
						initialRequestId: initialRequestId,
						returnBundleId: returnBundleId
					)
				}
			}
		}
	}

	/// Keyboard asked to activate keepalive (`zhigeng://activate`).
	func activateSessionFromKeyboard(requestId: String?, returnBundleId: String?) {
		os_log(
			"%{public}@",
			log: OSLog(subsystem: "app.zhigeng.ios", category: "activation"),
			type: .fault,
			"[ZG] activate request=\(requestId ?? "nil") host=\(returnBundleId ?? "nil") running=\(keyboardSession.isRunning)"
		)
		if keyboardSession.isRunning {
			if let requestId {
				try? bridge.writeCommand(DictationCommand(kind: .start, requestId: requestId))
			}
			keyboardSession.returnToHostApp(bundleId: returnBundleId)
			return
		}
		// Keyboard activation starts PiP + recording, then returns to the host.
		setSessionMode(.pip)
		sessionConfigured = true
		defaults.set(true, forKey: "sessionConfigured")
		requestMicThenStart(
			initialRequestId: requestId,
			returnBundleId: returnBundleId
		)
	}

	@discardableResult
	func addTerm(_ text: String, kind: PersonalTermKind = .word) -> PersonalTerm? {
		guard let term = lexicon.addManual(text, kind: kind) else { return nil }
		persistLexicon()
		return term
	}

	func setTermKind(id: String, kind: PersonalTermKind) {
		lexicon.setKind(id: id, kind: kind)
		persistLexicon()
	}

	func forgetTerm(id: String) {
		lexicon.forget(id: id)
		persistLexicon()
	}

	func rememberCorrection(original: String, replacement: String, requestId: String) {
		_ = learnCorrection(original: original, replacement: replacement, requestId: requestId)
	}

	@discardableResult
	func learnCorrection(original: String, replacement: String, requestId: String) -> PersonalTerm? {
		let term = lexicon.recordCorrection(
			original: original,
			replacement: replacement,
			requestId: requestId,
			insertedAt: Date().timeIntervalSince1970
		)
		if term != nil { persistLexicon() }
		return term
	}

	func appendHistory(_ item: DictationHistoryItem) {
		history.insert(item, at: 0)
		persistHistory()
	}

	func toggleKept(id: String) {
		guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
		if history[idx].keptAt == nil {
			history[idx].keptAt = Date().timeIntervalSince1970
		} else {
			history[idx].keptAt = nil
		}
		persistHistory()
	}

	func updateHistoryText(id: String, cleanedText: String) {
		guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
		history[idx].cleanedText = cleanedText
		persistHistory()
	}

	func deleteHistory(id: String) {
		history.removeAll { $0.id == id }
		persistHistory()
	}

	/// Onboarding demo: shows structure value without claiming live ASR success.
	func finishTryLearnDemo() {
		let cleaned = "帮我跟小杨说一下，ARR 的表我今晚改完，明早发给他。"
		tryLearnDraft = cleaned
		pendingLearnTerm = "小杨"
		appendHistory(
			DictationHistoryItem(
				source: .demo,
				status: .ready,
				cleanedText: cleaned,
				directStructured: true,
				processingTags: ["示例：去除口头词", "示例：按消息整理", "示例：专名命中"]
			)
		)
	}

	func reopenOnboarding(at step: OnboardingStep = .brandWelcome) {
		onboardingCompleted = false
		defaults.set(false, forKey: "onboardingCompleted")
		setOnboardingStep(step)
	}

	func confirmPendingLearn() {
		if let term = pendingLearnTerm {
			_ = addTerm(term)
			_ = addTerm("ARR")
		}
		pendingLearnTerm = nil
	}

	func skipPendingLearn() {
		pendingLearnTerm = nil
	}

	private func persistLexicon() {
		if let data = try? lexicon.encode() {
			try? bridge.writeLexicon(data)
		}
	}

	private func loadHistory() {
		guard let data = try? Data(contentsOf: historyURL),
		      let items = try? JSONDecoder().decode([DictationHistoryItem].self, from: data)
		else { return }
		let pruned = DictationHistoryItem.prune(items)
		history = pruned
		if pruned.count != items.count {
			persistHistory()
		}
	}

	private func persistHistory() {
		guard let data = try? JSONEncoder().encode(history) else { return }
		try? data.write(to: historyURL, options: .atomic)
	}
}
