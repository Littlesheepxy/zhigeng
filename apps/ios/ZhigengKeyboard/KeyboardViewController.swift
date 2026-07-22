import SwiftUI
import UIKit
import ZhigengCore
import KeyboardHostBundleID
import os.log

final class KeyboardViewController: UIInputViewController {
	private var hostingController: UIHostingController<KeyboardRootView>?
	private let bridge = AppGroupBridge()
	private var linkStatus: KeyboardLinkStatus = .unknown
	private var dictationPhase: KeyboardDictationPhase = .idle
	private var sessionAlive = false
	private var activeRequestId: String?
	private var processingStartedAt: TimeInterval?
	private var insertion = StreamingInsertionState()
	private var lastAppliedRevision = 0
	private var pollTimer: Timer?
	private var deleteRepeatTimer: Timer?
	private var hostBundleId: String?
	private var hostResolutionGeneration = 0
	private var hostResolutionFailed = false

	// Correction learning: only active for 30s after we inserted a dictation result.
	private var correctionRequestId: String?
	private var correctionInsertedAt: TimeInterval = 0
	private var correctionBaseline = ""
	private var correctionTimer: Timer?

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = KeyboardChrome.bottomGray
		refreshLinkStatus()
		rebuildHost()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		refreshLinkStatus()
		refreshSessionAlive()
		restorePendingRequestState()
		rebuildHost()
		startPolling()
		consumeLegacyPendingResult()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		hostResolutionGeneration += 1
		hostBundleId = nil
		hostResolutionFailed = false
		rebuildHost()
		resolveHostBundleId(attempt: 0, generation: hostResolutionGeneration)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		hostResolutionGeneration += 1
		pollTimer?.invalidate()
		pollTimer = nil
		deleteRepeatTimer?.invalidate()
		deleteRepeatTimer = nil
	}

	private func rebuildHost() {
		let activationURL = prepareActivationURL()
		let root = KeyboardRootView(
			needsInputModeSwitchKey: needsInputModeSwitchKey,
			linkStatus: linkStatus,
			dictationPhase: dictationPhase,
			sessionAlive: sessionAlive,
			activationReady: hostBundleId != nil,
			hostResolutionFailed: hostResolutionFailed,
			activationURL: activationURL,
			onInsert: { [weak self] text in
				self?.textDocumentProxy.insertText(text)
			},
			onDelete: { [weak self] in
				self?.textDocumentProxy.deleteBackward()
			},
			onDeleteHoldChanged: { [weak self] holding in
				self?.setDeleteRepeating(holding)
			},
			onMoveCursor: { [weak self] offset in
				self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
			},
			onNextKeyboard: { [weak self] in
				self?.advanceToNextInputMode()
			},
			onDictate: { [weak self] in
				self?.toggleDictation()
			}
		)
		if let hostingController {
			hostingController.rootView = root
			return
		}
		let host = UIHostingController(rootView: root)
		host.view.backgroundColor = .clear
		addChild(host)
		view.addSubview(host.view)
		host.view.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			host.view.topAnchor.constraint(equalTo: view.topAnchor),
			host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			view.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
		])
		host.didMove(toParent: self)
		hostingController = host
	}

	private func resolveHostBundleId(attempt: Int, generation: Int) {
		guard generation == hostResolutionGeneration else { return }
		if let resolved = KeyboardHost.resolve(from: self) {
			hostBundleId = resolved
			UserDefaults(suiteName: AppGroupConstants.suiteName)?
				.set(resolved, forKey: "keyboard.hostBundleId")
			os_log(
				"%{public}@",
				log: OSLog(subsystem: "app.zhigeng.ios.keyboard", category: "host"),
				type: .fault,
				"[ZG] resolved keyboard host=\(resolved) attempt=\(attempt)"
			)
			rebuildHost()
			return
		}
		guard attempt < 20 else {
			os_log(
				"%{public}@",
				log: OSLog(subsystem: "app.zhigeng.ios.keyboard", category: "host"),
				type: .fault,
				"[ZG] keyboard host resolution delayed; retrying"
			)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.resolveHostBundleId(attempt: 0, generation: generation)
			}
			return
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
			self?.resolveHostBundleId(attempt: attempt + 1, generation: generation)
		}
	}

	private func prepareActivationURL() -> URL {
		guard linkStatus == .connected, !sessionAlive else {
			return URL(string: "zhigeng://activate")!
		}
		if activeRequestId == nil {
			let request = DictationRequest()
			activeRequestId = request.requestId
			insertion.reset()
			lastAppliedRevision = 0
			try? bridge.writeRequest(request)
			UserDefaults(suiteName: AppGroupConstants.suiteName)?
				.set(request.requestId, forKey: "keyboard.pendingRequestId")
		}
		var components = URLComponents(string: "zhigeng://activate")!
		components.queryItems = [
			URLQueryItem(name: "requestId", value: activeRequestId),
			URLQueryItem(name: "returnBundleID", value: hostBundleId),
		].compactMap { $0.value == nil ? nil : $0 }
		return components.url!
	}

	private func restorePendingRequestState() {
		guard activeRequestId == nil,
		      sessionAlive,
		      let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName),
		      let requestId = defaults.string(forKey: "keyboard.pendingRequestId"),
		      !requestId.isEmpty,
		      let session = try? bridge.readSession()
		else { return }
		activeRequestId = requestId
		lastAppliedRevision = 0
		os_log(
			"%{public}@",
			log: OSLog(subsystem: "app.zhigeng.ios.keyboard", category: "session"),
			type: .fault,
			"[ZG] restore request=\(requestId) state=\(session.state.rawValue)"
		)
		switch session.state {
		case .recording:
			dictationPhase = .listening
		case .processing:
			dictationPhase = .processing
			processingStartedAt = Date().timeIntervalSince1970
		case .idle:
			dictationPhase = .listening
			try? bridge.writeCommand(DictationCommand(kind: .start, requestId: requestId))
		default:
			break
		}
	}

	private func refreshLinkStatus() {
		let full = hasFullAccess
		let hb = KeyboardHeartbeat(hasFullAccess: full)
		do {
			try bridge.writeHeartbeat(hb)
			writeDefaultsHeartbeat(hb)
			linkStatus = full ? .connected : .needsFullAccess
		} catch {
			linkStatus = full ? .appGroupMissing : .needsFullAccess
		}
	}

	private func refreshSessionAlive() {
		sessionAlive = (try? bridge.readSession())?.isServiceAlive() == true
	}

	private func writeDefaultsHeartbeat(_ hb: KeyboardHeartbeat) {
		guard let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName) else { return }
		defaults.set(hb.lastSeenAt, forKey: "keyboard.lastSeenAt")
		defaults.set(hb.hasFullAccess, forKey: "keyboard.hasFullAccess")
		defaults.set(hb.extensionVersion, forKey: "keyboard.extensionVersion")
		defaults.synchronize()
	}

	private func toggleDictation() {
		refreshLinkStatus()
		refreshSessionAlive()
		guard linkStatus == .connected else {
			rebuildHost()
			return
		}

		switch dictationPhase {
		case .listening:
			stopDictation()
		case .idle, .error, .done, .aborted, .needsActivation:
			// needsActivation stays tappable: if the app-open failed, retry instead of dead-ending.
			startDictation()
		case .processing:
			break
		}
	}

	private func startDictation() {
		refreshSessionAlive()
		if !sessionAlive {
			dictationPhase = .needsActivation
			rebuildHost()
			return
		}

		let request = DictationRequest()
		activeRequestId = request.requestId
		processingStartedAt = nil
		insertion.reset()
		lastAppliedRevision = 0
		dictationPhase = .listening
		do {
			try bridge.writeRequest(request)
			try bridge.writeCommand(DictationCommand(kind: .start, requestId: request.requestId))
			UserDefaults(suiteName: AppGroupConstants.suiteName)?
				.set(request.requestId, forKey: "keyboard.pendingRequestId")
		} catch {
			linkStatus = .appGroupMissing
			dictationPhase = .error
		}
		rebuildHost()
	}

	private func stopDictation() {
		guard let requestId = activeRequestId else { return }
		dictationPhase = .processing
		processingStartedAt = Date().timeIntervalSince1970
		try? bridge.writeCommand(DictationCommand(kind: .stop, requestId: requestId))
		rebuildHost()
	}

	private func startPolling() {
		pollTimer?.invalidate()
		pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
			Task { @MainActor in self?.poll() }
		}
	}

	private func poll() {
		let wasAlive = sessionAlive
		refreshSessionAlive()
		if wasAlive != sessionAlive {
			rebuildHost()
		}
		guard let requestId = activeRequestId else {
			consumeLegacyPendingResult()
			return
		}
		if dictationPhase == .processing,
		   let processingStartedAt,
		   Date().timeIntervalSince1970 - processingStartedAt > 12
		{
			try? bridge.writeCommand(DictationCommand(kind: .cancel, requestId: requestId))
			dictationPhase = .error
			finishActiveRequest()
			rebuildHost()
			return
		}
		guard let result = try? bridge.readResultIfNewer(than: lastAppliedRevision),
		      result.requestId == requestId
		else { return }
		applyStreamingResult(result)
	}

	private func applyStreamingResult(_ result: DictationResult) {
		lastAppliedRevision = result.revision
		let before = textDocumentProxy.documentContextBeforeInput ?? ""

		switch result.status {
		case .recording:
			dictationPhase = .listening
			let action = insertion.apply(
				revision: result.revision,
				nextPartial: result.text,
				contextBefore: before
			)
			applyInsertion(action)
		case .processing:
			dictationPhase = .processing
			rebuildHost()
		case .ready:
			let action = insertion.applyFinal(
				revision: result.revision,
				text: result.text,
				contextBefore: before
			)
			applyInsertion(action)
			dictationPhase = .done
			if case .replace = action {
				beginCorrectionWindow(requestId: result.requestId)
			}
			finishActiveRequest()
			try? bridge.clearResult()
			rebuildHost()
		case .incomplete, .error:
			dictationPhase = .error
			finishActiveRequest()
			rebuildHost()
		case .idle, .requesting:
			break
		}
	}

	private func applyInsertion(_ action: StreamingInsertionAction) {
		switch action {
		case let .replace(deleteCount, insert):
			for _ in 0..<deleteCount {
				textDocumentProxy.deleteBackward()
			}
			if !insert.isEmpty {
				textDocumentProxy.insertText(insert)
			}
		case .skip:
			break
		case .abort:
			dictationPhase = .aborted
			rebuildHost()
		}
	}

	private func finishActiveRequest() {
		UserDefaults(suiteName: AppGroupConstants.suiteName)?
			.removeObject(forKey: "keyboard.pendingRequestId")
		activeRequestId = nil
		processingStartedAt = nil
		insertion.reset()
	}

	/// Fallback for old handoff that wrote final-only results after app switch.
	private func consumeLegacyPendingResult() {
		guard activeRequestId == nil,
		      let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName),
		      let requestId = defaults.string(forKey: "keyboard.pendingRequestId"),
		      !requestId.isEmpty
		else { return }
		do {
			if let result = try bridge.consumeInsertableResult(matching: requestId) {
				textDocumentProxy.insertText(result.text)
				defaults.removeObject(forKey: "keyboard.pendingRequestId")
				beginCorrectionWindow(requestId: requestId)
				dictationPhase = .done
				rebuildHost()
			}
		} catch {
			// keep pending id for next appear
		}
	}

	private func setDeleteRepeating(_ holding: Bool) {
		if holding {
			guard deleteRepeatTimer == nil else { return }
			textDocumentProxy.deleteBackward()
			deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
				Task { @MainActor in self?.textDocumentProxy.deleteBackward() }
			}
		} else {
			deleteRepeatTimer?.invalidate()
			deleteRepeatTimer = nil
		}
	}

	// MARK: - Correction learning (30s window after insert)

	override func textDidChange(_ textInput: UITextInput?) {
		super.textDidChange(textInput)
		guard correctionRequestId != nil else { return }
		guard Date().timeIntervalSince1970 - correctionInsertedAt <= PersonalLexicon.correctionWindowSeconds else {
			endCorrectionWindow()
			return
		}
		correctionTimer?.invalidate()
		correctionTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
			Task { @MainActor in self?.learnFromEdit() }
		}
	}

	private func beginCorrectionWindow(requestId: String) {
		correctionRequestId = requestId
		correctionInsertedAt = Date().timeIntervalSince1970
		correctionBaseline = currentContextSnapshot()
	}

	private func endCorrectionWindow() {
		correctionTimer?.invalidate()
		correctionTimer = nil
		correctionRequestId = nil
		correctionBaseline = ""
	}

	private func currentContextSnapshot() -> String {
		let proxy = textDocumentProxy
		return (proxy.documentContextBeforeInput ?? "")
			+ (proxy.selectedText ?? "")
			+ (proxy.documentContextAfterInput ?? "")
	}

	private func learnFromEdit() {
		guard let requestId = correctionRequestId else { return }
		let now = Date().timeIntervalSince1970
		guard now - correctionInsertedAt <= PersonalLexicon.correctionWindowSeconds else {
			endCorrectionWindow()
			return
		}
		let current = currentContextSnapshot()
		let pairs = TextEditDiff.replacements(original: correctionBaseline, edited: current)
		guard let (from, to) = pairs.first else { return }

		do {
			let lexicon: PersonalLexicon
			if let data = try bridge.readLexiconData() {
				lexicon = try PersonalLexicon.decode(from: data)
			} else {
				lexicon = PersonalLexicon()
			}
			guard lexicon.recordCorrection(
				original: from,
				replacement: to,
				requestId: requestId,
				insertedAt: correctionInsertedAt,
				at: now
			) != nil else { return }
			try bridge.writeLexicon(lexicon.encode())
			endCorrectionWindow()
		} catch {
			endCorrectionWindow()
		}
	}

}

enum KeyboardDictationPhase: Equatable {
	case idle
	case needsActivation
	case listening
	case processing
	case done
	case aborted
	case error

	var statusLine: String {
		switch self {
		case .idle: return "点击说话"
		case .needsActivation: return "请先开启即听即写"
		case .listening: return "正在听 · 再点结束"
		case .processing: return "正在整理…"
		case .done: return "已插入"
		case .aborted: return "内容已变化，完成后请手动插入"
		case .error: return "识别失败，再试一次"
		}
	}
}

enum KeyboardLinkStatus: Equatable {
	case unknown
	case connected
	case needsFullAccess
	case appGroupMissing

	var banner: String {
		switch self {
		case .unknown:
			return "正在连接知更…"
		case .connected:
			return "已连接主 App"
		case .needsFullAccess:
			return "请开启「允许完全访问」"
		case .appGroupMissing:
			return "无法写入 App Group"
		}
	}
}

enum KeyboardMode: String, CaseIterable, Identifiable {
	case voice
	case english
	case pinyin

	var id: String { rawValue }

	var enabled: Bool {
		self != .pinyin
	}
}

enum KeyboardChrome {
	/// Matches the system keyboard dock (globe / dictation bar) ≈ #d1d3da.
	static let bottomGray = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor(white: 0.17, alpha: 1)
			: UIColor(red: 0xD1 / 255, green: 0xD3 / 255, blue: 0xDA / 255, alpha: 1)
	}

	static let topGray = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor(white: 0.28, alpha: 1)
			: UIColor(red: 0xEE / 255, green: 0xEF / 255, blue: 0xF2 / 255, alpha: 1)
	}

	static var background: LinearGradient {
		LinearGradient(
			colors: [
				Color(uiColor: topGray),
				Color(uiColor: bottomGray),
			],
			startPoint: .top,
			endPoint: .bottom
		)
	}
}

struct KeyboardRootView: View {
	var needsInputModeSwitchKey: Bool
	var linkStatus: KeyboardLinkStatus
	var dictationPhase: KeyboardDictationPhase
	var sessionAlive: Bool
	var activationReady: Bool
	var hostResolutionFailed: Bool
	var activationURL: URL
	var onInsert: (String) -> Void
	var onDelete: () -> Void
	var onDeleteHoldChanged: (Bool) -> Void
	var onMoveCursor: (Int) -> Void
	var onNextKeyboard: () -> Void
	var onDictate: () -> Void

	@State private var mode: KeyboardMode = .voice
	@State private var shifted = false
	@State private var trackpadDragAccum: CGFloat = 0

	var body: some View {
		VStack(spacing: 10) {
			topBar
			if linkStatus != .connected {
				Text(linkStatus.banner)
					.font(.caption2)
					.foregroundStyle(.orange)
					.frame(maxWidth: .infinity)
			} else if !sessionAlive && mode == .voice {
				Text(
					hostResolutionFailed
						? "暂时无法识别当前应用，请切换键盘重试"
						: activationReady
							? "未开启即听即写 · 点麦克风打开知更"
							: "正在连接当前应用…"
				)
					.font(.caption2)
					.foregroundStyle(hostResolutionFailed ? .orange : .secondary)
					.frame(maxWidth: .infinity)
			}

			Group {
				switch mode {
				case .voice:
					voicePlane
				case .english:
					englishPlane
				case .pinyin:
					pinyinPlaceholder
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.padding(.horizontal, 8)
		.padding(.top, 8)
		.padding(.bottom, 6)
		.background(KeyboardChrome.background)
		.gesture(
			DragGesture(minimumDistance: 40)
				.onEnded { value in
					guard abs(value.translation.width) > abs(value.translation.height) else { return }
					cycleMode(forward: value.translation.width < 0)
				}
		)
	}

	private var topBar: some View {
		HStack(spacing: 10) {
			logoMark
			Spacer(minLength: 8)
			modeSwitcher
		}
	}

	private var logoMark: some View {
		Group {
			if let uiImage = UIImage(named: "robin") {
				Image(uiImage: uiImage)
					.resizable()
					.scaledToFit()
			} else {
				Image(systemName: "bird.fill")
					.font(.system(size: 16, weight: .semibold))
					.foregroundStyle(Color(red: 0.404, green: 0.361, blue: 0.945))
			}
		}
		.frame(width: 34, height: 34)
		.clipShape(Circle())
		.accessibilityLabel("知更")
	}

	private var modeSwitcher: some View {
		HStack(spacing: 2) {
			ForEach(KeyboardMode.allCases) { item in
				Button {
					guard item.enabled else { return }
					withAnimation(.easeOut(duration: 0.15)) { mode = item }
				} label: {
					Group {
						if item == .voice {
							Image(systemName: "mic.fill")
								.font(.system(size: 13, weight: .semibold))
						} else if item == .english {
							Text("EN")
								.font(.caption.weight(mode == item ? .semibold : .medium))
						} else {
							Text("拼")
								.font(.caption.weight(mode == item ? .semibold : .medium))
						}
					}
					.foregroundStyle(
						item.enabled
							? (mode == item ? Color.primary : Color.secondary)
							: Color.secondary.opacity(0.4)
					)
					.frame(width: 34, height: 28)
					.background(
						mode == item ? Color(uiColor: .systemBackground).opacity(0.92) : .clear,
						in: Capsule()
					)
				}
				.buttonStyle(.plain)
				.disabled(!item.enabled)
				.accessibilityLabel(item == .voice ? "语音" : item == .english ? "英文" : "拼音")
			}
		}
		.padding(3)
		.background(Color.black.opacity(0.08), in: Capsule())
	}

	private var voicePlane: some View {
		VStack(spacing: 14) {
			Spacer(minLength: 4)
			Text(voiceStatusText)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
			if linkStatus == .connected && !sessionAlive {
				if activationReady {
					Link(destination: activationURL) {
						dictationButtonLabel
					}
					.buttonStyle(.plain)
					.accessibilityLabel("打开知更并开启即听即写")
				} else {
					dictationButtonLabel
						.opacity(0.45)
				}
			} else {
				Button(action: onDictate) {
					dictationButtonLabel
				}
				.buttonStyle(.plain)
				.disabled(linkStatus != .connected || dictationPhase == .processing)
				.opacity(linkStatus == .connected ? 1 : 0.45)
				.accessibilityLabel(dictationPhase == .listening ? "结束说话" : "点击说话")
			}
			Spacer(minLength: 4)
			editToolbar
		}
	}

	private var dictationButtonLabel: some View {
		Group {
			if dictationPhase == .listening {
				ListeningWaveform()
			} else {
				Image(systemName: "mic.fill")
					.font(.system(size: 28, weight: .semibold))
			}
		}
			.foregroundStyle(.white)
			.frame(width: 136, height: 72)
			.background(
				dictationPhase == .listening
					? Color(red: 0.75, green: 0.22, blue: 0.2)
					: Color.black.opacity(0.88),
				in: Capsule()
			)
	}

	private var voiceStatusText: String {
		if linkStatus != .connected { return "先开启完全访问" }
		if !sessionAlive && !activationReady {
			return hostResolutionFailed ? "当前应用暂不支持自动返回" : "正在准备语音输入…"
		}
		return dictationPhase.statusLine
	}

	private var englishPlane: some View {
		VStack(spacing: 7) {
			keyRow(["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"])
			keyRow(["A", "S", "D", "F", "G", "H", "J", "K", "L"])
			HStack(spacing: 6) {
				shiftKey
				keyRowContent(["Z", "X", "C", "V", "B", "N", "M"])
				holdDeleteKey
			}
			editToolbar
		}
	}

	private var pinyinPlaceholder: some View {
		VStack {
			Spacer()
			Text("拼音键盘即将接入")
				.font(.subheadline)
				.foregroundStyle(.secondary)
			Spacer()
			editToolbar
		}
	}

	/// Globe (when needed) + delete + trackpad space + send.
	private var editToolbar: some View {
		HStack(spacing: 6) {
			if needsInputModeSwitchKey {
				actionKey(systemImage: "globe", action: onNextKeyboard)
			}
			holdDeleteKey
			trackpadSpace
			actionKey(systemImage: "return", action: { onInsert("\n") })
		}
	}

	private var trackpadSpace: some View {
		Text("空格")
			.font(.subheadline.weight(.medium))
			.frame(maxWidth: .infinity, minHeight: 42)
			.background(
				LinearGradient(
					colors: [
						Color(uiColor: .systemBackground).opacity(0.98),
						Color(uiColor: .systemGray5).opacity(0.9),
					],
					startPoint: .top,
					endPoint: .bottom
				),
				in: RoundedRectangle(cornerRadius: 8)
			)
			.contentShape(RoundedRectangle(cornerRadius: 8))
			.gesture(
				DragGesture(minimumDistance: 0)
					.onChanged { value in
						let delta = value.translation.width - trackpadDragAccum
						let step: CGFloat = 14
						if abs(delta) >= step {
							let steps = Int(delta / step)
							onMoveCursor(steps)
							trackpadDragAccum += CGFloat(steps) * step
						}
					}
					.onEnded { value in
						defer { trackpadDragAccum = 0 }
						if hypot(value.translation.width, value.translation.height) < 8 {
							onInsert(" ")
						}
					}
			)
			.accessibilityLabel("空格，左右拖动移动光标")
	}

	private var holdDeleteKey: some View {
		Image(systemName: "delete.left")
			.font(.body.weight(.semibold))
			.frame(width: 42, height: 42)
			.background(Color(uiColor: .systemGray3).opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
			.contentShape(Rectangle())
			.gesture(
				DragGesture(minimumDistance: 0)
					.onChanged { _ in onDeleteHoldChanged(true) }
					.onEnded { _ in onDeleteHoldChanged(false) }
			)
			.accessibilityLabel("删除")
	}

	private var shiftKey: some View {
		Button {
			shifted.toggle()
		} label: {
			Image(systemName: shifted ? "shift.fill" : "shift")
				.font(.body.weight(.semibold))
				.frame(width: 42, height: 42)
				.background(Color(uiColor: .systemGray3).opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
		}
		.buttonStyle(.plain)
	}

	private func keyRow(_ keys: [String]) -> some View {
		HStack(spacing: 6) {
			keyRowContent(keys)
		}
	}

	private func keyRowContent(_ keys: [String]) -> some View {
		HStack(spacing: 6) {
			ForEach(keys, id: \.self) { key in
				let display = shifted ? key : key.lowercased()
				Button {
					onInsert(display)
					if shifted { shifted = false }
				} label: {
					Text(display)
						.font(.body.weight(.medium))
						.frame(maxWidth: .infinity, minHeight: 42)
						.background(Color(uiColor: .systemBackground).opacity(0.94), in: RoundedRectangle(cornerRadius: 8))
				}
				.buttonStyle(.plain)
			}
		}
	}

	private func actionKey(systemImage: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: systemImage)
				.font(.body.weight(.semibold))
				.frame(width: 42, height: 42)
				.background(Color(uiColor: .systemGray3).opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
		}
		.buttonStyle(.plain)
	}

	private func cycleMode(forward: Bool) {
		let enabled = KeyboardMode.allCases.filter(\.enabled)
		guard let idx = enabled.firstIndex(of: mode) else { return }
		let next = forward
			? enabled[(idx + 1) % enabled.count]
			: enabled[(idx - 1 + enabled.count) % enabled.count]
		withAnimation(.easeOut(duration: 0.15)) { mode = next }
	}
}

/// Same nine-bar, symmetric real-level waveform used by the main app.
private struct ListeningWaveform: View {
	@State private var level = 0.0
	private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

	var body: some View {
		TimelineView(.animation(minimumInterval: 0.05)) { timeline in
			let heights = VoiceWaveformMath.barHeights(
				level: level,
				time: timeline.date.timeIntervalSinceReferenceDate
			)
			HStack(spacing: 2) {
				ForEach(heights.indices, id: \.self) { index in
					Capsule()
						.frame(width: 3, height: heights[index])
				}
			}
			.frame(height: 24)
		}
		.onReceive(timer) { _ in
			let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
			defaults?.synchronize()
			level = defaults?.double(forKey: "dictation.level") ?? 0
		}
	}
}
