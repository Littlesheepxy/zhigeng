import SwiftUI
import UIKit
import ZhigengCore
import KeyboardHostBundleID
import os.log

final class KeyboardViewController: UIInputViewController {
	private var hostingController: UIHostingController<KeyboardRootView>?
	private var keyboardHeightConstraint: NSLayoutConstraint?
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
	private var supplementaryLexicon: [SpeechLexiconTerm] = []
	private var speechCorrection: SpeechCorrectionState?
	private var selectedCorrectionSpanID: Int?
	private var correctionDocumentIdentifier: UUID?
	private var correctionAnchor: SpeechCorrectionAnchor?
	private var correctionNotice: String?
	private var redictationTarget: SpeechCorrectionState?
	private var redictationPreview = ""
	private lazy var cursorFeedbackGenerator = UISelectionFeedbackGenerator()

	override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
		hasDictationKey = true
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		hasDictationKey = true
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = KeyboardChrome.bottomGray
		refreshLinkStatus()
		loadSupplementaryLexicon()
		rebuildHost()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		hasDictationKey = true
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
			returnKeyLabel: returnKeyLabel,
			chineseKeyboardLayout: chineseKeyboardLayout,
			speechCorrection: speechCorrection,
			selectedCorrectionSpanID: selectedCorrectionSpanID,
			correctionNotice: correctionNotice,
			redictationPreview: redictationPreview,
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
				self?.moveCursorHorizontally(offset)
			},
			onMoveCursorVertically: { [weak self] direction in
				self?.moveCursorVertically(direction)
			},
			onNextKeyboard: { [weak self] in
				self?.advanceToNextInputMode()
			},
			onDictate: { [weak self] in
				self?.toggleDictation()
			},
			onSelectCorrectionSpan: { [weak self] spanID in
				self?.selectedCorrectionSpanID = spanID
				self?.correctionNotice = nil
				self?.rebuildHost()
			},
			onChooseCorrection: { [weak self] spanID, candidate in
				self?.applyCorrection(spanID: spanID, candidate: candidate)
			},
			onEditCorrection: { [weak self] in
				self?.editCorrectionWithTypingKeyboard()
			},
			onRedictate: { [weak self] in
				self?.startRedictation()
			}
		)
		if let hostingController {
			hostingController.rootView = root
			keyboardHeightConstraint?.constant = 252
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
		])
		let height = view.heightAnchor.constraint(equalToConstant: 252)
		height.priority = .required
		height.isActive = true
		keyboardHeightConstraint = height
		host.didMove(toParent: self)
		hostingController = host
	}

	private var returnKeyLabel: String {
		switch textDocumentProxy.returnKeyType {
		case .send: return "发送"
		case .search: return "搜索"
		case .go: return "前往"
		case .done: return "完成"
		case .next: return "下一项"
		case .continue: return "继续"
		case .join: return "加入"
		case .route: return "路线"
		default: return "换行"
		}
	}

	private var chineseKeyboardLayout: ChineseKeyboardLayout {
		guard let raw = UserDefaults(suiteName: AppGroupConstants.suiteName)?
			.string(forKey: AppGroupConstants.chineseKeyboardLayoutKey)
		else { return .fullKeyboard }
		return ChineseKeyboardLayout(rawValue: raw) ?? .fullKeyboard
	}

	private func loadSupplementaryLexicon() {
		// ObjC delivers on com.apple.TextInput.lexicon-request. A MainActor-inherited
		// Swift closure traps at entry (SIGTRAP) before any Task hop can run.
		requestSupplementaryLexicon { @Sendable [weak self] lexicon in
			let terms = lexicon.entries.flatMap { entry in
				[entry.documentText, entry.userInput].map { SpeechLexiconTerm(text: $0, weight: 1) }
			}
			DispatchQueue.main.async {
				self?.applySupplementaryLexicon(terms)
			}
		}
	}

	private func applySupplementaryLexicon(_ terms: [SpeechLexiconTerm]) {
		supplementaryLexicon = terms
		guard let correction = speechCorrection else { return }
		speechCorrection = SpeechCorrectionState.build(
			requestId: correction.requestId,
			text: correction.text,
			lexicon: correctionLexicon()
		)
		rebuildHost()
	}

	private func correctionLexicon() -> [SpeechLexiconTerm] {
		var terms = supplementaryLexicon
		if let data = try? bridge.readLexiconData(),
		   let lexicon = try? PersonalLexicon.decode(from: data)
		{
			terms += lexicon.allTerms.map {
				SpeechLexiconTerm(text: $0.text, weight: $0.weight + 10)
			}
		}
		return terms
	}

	private func cursorFeedback() {
		cursorFeedbackGenerator.selectionChanged()
	}

	private func moveCursorVertically(_ direction: CursorVerticalDirection) {
		let offset = CursorNavigation.verticalOffset(
			direction: direction,
			contextBefore: textDocumentProxy.documentContextBeforeInput ?? "",
			contextAfter: textDocumentProxy.documentContextAfterInput ?? "",
			approximateLineLength: 12
		)
		guard offset != 0 else { return }
		textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
		cursorFeedback()
	}

	private func moveCursorHorizontally(_ steps: Int) {
		let offset = CursorNavigation.horizontalOffset(
			steps: steps,
			contextBefore: textDocumentProxy.documentContextBeforeInput ?? "",
			contextAfter: textDocumentProxy.documentContextAfterInput ?? ""
		)
		guard offset != 0 else { return }
		textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
		cursorFeedback()
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
			let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
			if let pending = defaults?.string(forKey: "keyboard.pendingRequestId"), !pending.isEmpty {
				activeRequestId = pending
			} else {
				let request = DictationRequest()
				activeRequestId = request.requestId
				insertion.reset()
				lastAppliedRevision = 0
				try? bridge.writeRequest(request)
				defaults?.set(request.requestId, forKey: "keyboard.pendingRequestId")
			}
		}
		var components = URLComponents(string: "zhigeng://activate")!
		components.queryItems = [
			URLQueryItem(name: "requestId", value: activeRequestId),
			URLQueryItem(name: "returnBundleID", value: hostBundleId),
		].compactMap { $0.value == nil ? nil : $0 }
		return components.url!
	}

	private func restorePendingRequestState() {
		guard sessionAlive,
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

		if redictationTarget == nil {
			speechCorrection = nil
			selectedCorrectionSpanID = nil
			correctionNotice = nil
			correctionDocumentIdentifier = nil
			correctionAnchor = nil
		}
		redictationPreview = ""
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
			if redictationTarget != nil {
				restoreCorrectionAfterRedictationFailure("无法开始重说，已保留原句")
			} else {
				dictationPhase = .error
			}
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
			if redictationTarget != nil {
				restoreCorrectionAfterRedictationFailure("重说超时，已保留原句")
			} else {
				dictationPhase = .error
			}
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
			if redictationTarget != nil {
				redictationPreview = result.text
				rebuildHost()
				return
			}
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
			if let target = redictationTarget {
				_ = applyRedictationFinal(result, replacing: target, contextBefore: before)
				dictationPhase = .done
				finishActiveRequest()
				try? bridge.clearResult()
				rebuildHost()
				return
			}
			let action = insertion.applyFinal(
				revision: result.revision,
				text: result.text,
				contextBefore: before
			)
			applyInsertion(action)
			dictationPhase = .done
			if case .replace = action {
				beginCorrectionWindow(requestId: result.requestId)
				beginSpeechCorrection(requestId: result.requestId, text: result.text)
			}
			finishActiveRequest()
			try? bridge.clearResult()
			rebuildHost()
		case .incomplete, .error:
			if redictationTarget != nil {
				restoreCorrectionAfterRedictationFailure("重说失败，已保留原句")
			} else {
				dictationPhase = .error
			}
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
				beginSpeechCorrection(requestId: requestId, text: result.text)
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

	private func beginSpeechCorrection(requestId: String, text: String) {
		speechCorrection = SpeechCorrectionState.build(
			requestId: requestId,
			text: text,
			lexicon: correctionLexicon()
		)
		selectedCorrectionSpanID = speechCorrection?.spans.first?.id
		correctionDocumentIdentifier = textDocumentProxy.documentIdentifier
		correctionAnchor = SpeechCorrectionAnchor.capture(
			insertedText: text,
			contextBefore: textDocumentProxy.documentContextBeforeInput ?? "",
			contextAfter: textDocumentProxy.documentContextAfterInput ?? ""
		)
		correctionNotice = nil
	}

	private func correctionContextMatches(_ state: SpeechCorrectionState) -> Bool {
		correctionDocumentIdentifier == textDocumentProxy.documentIdentifier
			&& correctionAnchor?.matches(
				insertedText: state.text,
				contextBefore: textDocumentProxy.documentContextBeforeInput ?? "",
				contextAfter: textDocumentProxy.documentContextAfterInput ?? ""
			) == true
	}

	private func applyCorrection(spanID: Int, candidate: String) {
		guard let state = speechCorrection,
		      correctionContextMatches(state),
		      let replacement = state.replacement(
			      spanID: spanID,
			      with: candidate,
			      contextBefore: textDocumentProxy.documentContextBeforeInput ?? ""
		      )
		else {
			correctionNotice = "文本已变化，请手动定位修改"
			rebuildHost()
			return
		}

		for _ in 0..<replacement.deleteCount {
			textDocumentProxy.deleteBackward()
		}
		textDocumentProxy.insertText(replacement.insert)
		recordExplicitCorrection(
			requestId: state.requestId,
			original: replacement.original,
			replacement: replacement.replacement
		)
		beginCorrectionWindow(requestId: state.requestId)
		beginSpeechCorrection(requestId: state.requestId, text: replacement.insert)
		correctionNotice = "已替换"
		rebuildHost()
	}

	private func editCorrectionWithTypingKeyboard() {
		if let state = speechCorrection,
		   correctionContextMatches(state),
		   let spanID = selectedCorrectionSpanID,
		   let offset = state.cursorOffsetAfterSpan(
				spanID,
				contextBefore: textDocumentProxy.documentContextBeforeInput ?? ""
		   )
		{
			textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
		}
		advanceToNextInputMode()
	}

	private func startRedictation() {
		guard let state = speechCorrection,
		      correctionContextMatches(state)
		else {
			correctionNotice = "文本已变化，不能安全重说"
			rebuildHost()
			return
		}
		redictationTarget = state
		selectedCorrectionSpanID = nil
		correctionNotice = nil
		startDictation()
	}

	private func applyRedictationFinal(
		_ result: DictationResult,
		replacing target: SpeechCorrectionState,
		contextBefore: String
	) -> Bool {
		defer {
			redictationTarget = nil
			redictationPreview = ""
		}
		guard correctionContextMatches(target),
		      contextBefore.hasSuffix(target.text),
		      !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		else {
			correctionNotice = "文本已变化，已保留原句"
			return false
		}
		for _ in 0..<target.text.count {
			textDocumentProxy.deleteBackward()
		}
		textDocumentProxy.insertText(result.text)
		beginCorrectionWindow(requestId: result.requestId)
		beginSpeechCorrection(requestId: result.requestId, text: result.text)
		return true
	}

	private func restoreCorrectionAfterRedictationFailure(_ message: String) {
		redictationTarget = nil
		redictationPreview = ""
		dictationPhase = .done
		correctionNotice = message
	}

	private func recordExplicitCorrection(requestId: String, original: String, replacement: String) {
		do {
			let lexicon: PersonalLexicon
			if let data = try bridge.readLexiconData() {
				lexicon = try PersonalLexicon.decode(from: data)
			} else {
				lexicon = PersonalLexicon()
			}
			let now = Date().timeIntervalSince1970
			guard lexicon.recordCorrection(
				original: original,
				replacement: replacement,
				requestId: requestId,
				insertedAt: now,
				at: now
			) != nil else { return }
			try bridge.writeLexicon(lexicon.encode())
		} catch {
			// The replacement already succeeded; learning is best-effort.
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
	var returnKeyLabel: String
	var chineseKeyboardLayout: ChineseKeyboardLayout
	var speechCorrection: SpeechCorrectionState?
	var selectedCorrectionSpanID: Int?
	var correctionNotice: String?
	var redictationPreview: String
	var onInsert: (String) -> Void
	var onDelete: () -> Void
	var onDeleteHoldChanged: (Bool) -> Void
	var onMoveCursor: (Int) -> Void
	var onMoveCursorVertically: (CursorVerticalDirection) -> Void
	var onNextKeyboard: () -> Void
	var onDictate: () -> Void
	var onSelectCorrectionSpan: (Int) -> Void
	var onChooseCorrection: (Int, String) -> Void
	var onEditCorrection: () -> Void
	var onRedictate: () -> Void

	@State private var mode: KeyboardMode = .voice
	@State private var shifted = false
	@State private var englishSymbols = false
	@State private var trackpadDragAccum = CGSize.zero
	@State private var correctionDragAccum = CGSize.zero

	var body: some View {
		VStack(spacing: 6) {
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
		.padding(.horizontal, 12)
		.padding(.top, 6)
		.padding(.bottom, 2)
		.background(KeyboardChrome.background)
		.ignoresSafeArea(.container, edges: .bottom)
		.gesture(
			DragGesture(minimumDistance: 40)
				.onEnded { value in
					guard speechCorrection == nil else { return }
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
		ZStack {
			if dictationPhase == .done, let speechCorrection {
				correctionPanel(speechCorrection)
					.padding(.trailing, 52)
					.padding(.bottom, 52)
			} else {
				VStack(spacing: 8) {
					Text(redictationPreview.isEmpty ? voiceStatusText : redictationPreview)
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
						.lineLimit(2)
					Spacer(minLength: 0)
					voiceMicControl
					Spacer(minLength: 52)
				}
			}

			if needsInputModeSwitchKey {
				VStack {
					Spacer()
					actionKey(systemImage: "globe", action: onNextKeyboard)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			}

			VStack {
				Spacer()
				circularTextKey(returnKeyLabel, action: { onInsert("\n") })
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

			if chineseKeyboardLayout.voiceDeletePlacement == .topTrailing {
				holdDeleteKey
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
			} else {
				VStack {
					Spacer()
					holdDeleteKey
						.padding(.bottom, 52)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
			}
		}
	}

	@ViewBuilder
	private var voiceMicControl: some View {
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
	}

	private func correctionPanel(_ state: SpeechCorrectionState) -> some View {
		VStack(spacing: 8) {
			if let selected = selectedCorrectionSpan(in: state) {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 6) {
						ForEach(Array(selected.candidates.enumerated()), id: \.offset) { _, candidate in
							Button(candidate.text) {
								onChooseCorrection(selected.id, candidate.text)
							}
							.font(.subheadline.weight(.medium))
							.buttonStyle(.bordered)
							.controlSize(.small)
						}
					}
				}
				.frame(height: 32)
			}

			CorrectionFlowLayout(spacing: 1) {
				ForEach(correctionRuns(state)) { run in
					if let spanID = run.spanID {
						Button {
							onSelectCorrectionSpan(spanID)
						} label: {
							Text(run.text)
								.font(.body)
								.foregroundStyle(.blue)
								.underline(true, color: .blue)
								.padding(.horizontal, 2)
								.padding(.vertical, 2)
								.background(
									selectedCorrectionSpanID == spanID
										? Color.blue.opacity(0.12)
										: .clear,
									in: RoundedRectangle(cornerRadius: 4)
								)
						}
						.buttonStyle(.plain)
					} else {
						Text(run.text)
							.font(.body)
							.padding(.vertical, 2)
					}
				}
			}
			.frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
			.padding(.horizontal, 8)
			.padding(.vertical, 6)
			.background(Color(uiColor: .systemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
			.simultaneousGesture(correctionTrackpadGesture)
			.accessibilityHint("拖动可移动光标")

			if let correctionNotice {
				Text(correctionNotice)
					.font(.caption2)
					.foregroundStyle(.secondary)
			}

			HStack(spacing: 8) {
				Button("打字修改", action: onEditCorrection)
					.buttonStyle(.bordered)
				Button("整句重说", action: onRedictate)
					.buttonStyle(.borderedProminent)
			}
			.controlSize(.small)
		}
	}

	private func selectedCorrectionSpan(in state: SpeechCorrectionState) -> SpeechCorrectionSpan? {
		guard let selectedCorrectionSpanID else { return nil }
		return state.spans.first { $0.id == selectedCorrectionSpanID }
	}

	private func correctionRuns(_ state: SpeechCorrectionState) -> [CorrectionDisplayRun] {
		let characters = Array(state.text)
		var spansByStart: [Int: SpeechCorrectionSpan] = [:]
		for span in state.spans {
			if spansByStart[span.start] == nil {
				spansByStart[span.start] = span
			}
		}
		var runs: [CorrectionDisplayRun] = []
		var index = 0
		while index < characters.count {
			if let span = spansByStart[index],
			   span.length > 0,
			   index + span.length <= characters.count
			{
				runs.append(
					CorrectionDisplayRun(
						id: index,
						text: String(characters[index..<(index + span.length)]),
						spanID: span.id
					)
				)
				index += span.length
			} else {
				runs.append(CorrectionDisplayRun(id: index, text: String(characters[index]), spanID: nil))
				index += 1
			}
		}
		return runs
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
		.frame(width: 152, height: 52)
		.background(
			dictationPhase == .listening
				? Color.black.opacity(0.78)
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
		VStack(spacing: 6) {
			if englishSymbols {
				keyRow(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
				keyRow(["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""])
				HStack(spacing: 6) {
					compactTextKey("ABC") { englishSymbols = false }
					keyRowContent([".", ",", "?", "!", "'"])
					holdDeleteKey
				}
			} else {
				keyRow(["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"])
				keyRow(["A", "S", "D", "F", "G", "H", "J", "K", "L"])
				HStack(spacing: 6) {
					shiftKey
					keyRowContent(["Z", "X", "C", "V", "B", "N", "M"])
					holdDeleteKey
				}
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

	/// Number/symbol entry + punctuation + trackpad space + send.
	private var editToolbar: some View {
		HStack(spacing: 6) {
			compactTextKey(englishSymbols ? "ABC" : "123") {
				englishSymbols.toggle()
			}
			compactTextKey(",") { onInsert(",") }
			trackpadSpace
			compactTextKey(".") { onInsert(".") }
			textActionKey(returnKeyLabel, action: { onInsert("\n") })
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
						let horizontalDelta = value.translation.width - trackpadDragAccum.width
						let verticalDelta = value.translation.height - trackpadDragAccum.height
						let horizontalStep: CGFloat = 14
						let verticalStep: CGFloat = 24
						if abs(verticalDelta) / verticalStep > abs(horizontalDelta) / horizontalStep,
						   abs(verticalDelta) >= verticalStep
						{
							let steps = Int(verticalDelta / verticalStep)
							for _ in 0..<abs(steps) {
								onMoveCursorVertically(steps < 0 ? .up : .down)
							}
							trackpadDragAccum.height += CGFloat(steps) * verticalStep
						} else if abs(horizontalDelta) >= horizontalStep {
							let steps = Int(horizontalDelta / horizontalStep)
							onMoveCursor(steps)
							trackpadDragAccum.width += CGFloat(steps) * horizontalStep
						}
					}
					.onEnded { value in
						defer { trackpadDragAccum = .zero }
						if hypot(value.translation.width, value.translation.height) < 8 {
							onInsert(" ")
						}
					}
			)
			.accessibilityLabel("空格，拖动移动光标")
	}

	private var correctionTrackpadGesture: some Gesture {
		DragGesture(minimumDistance: 10)
			.onChanged { value in
				let horizontalDelta = value.translation.width - correctionDragAccum.width
				let verticalDelta = value.translation.height - correctionDragAccum.height
				let horizontalStep: CGFloat = 14
				let verticalStep: CGFloat = 24
				if abs(verticalDelta) / verticalStep > abs(horizontalDelta) / horizontalStep,
				   abs(verticalDelta) >= verticalStep
				{
					let steps = Int(verticalDelta / verticalStep)
					for _ in 0..<abs(steps) {
						onMoveCursorVertically(steps < 0 ? .up : .down)
					}
					correctionDragAccum.height += CGFloat(steps) * verticalStep
				} else if abs(horizontalDelta) >= horizontalStep {
					let steps = Int(horizontalDelta / horizontalStep)
					onMoveCursor(steps)
					correctionDragAccum.width += CGFloat(steps) * horizontalStep
				}
			}
			.onEnded { _ in
				correctionDragAccum = .zero
			}
	}

	private var holdDeleteKey: some View {
		Image(systemName: "delete.left")
			.font(.body.weight(.semibold))
			.frame(width: 44, height: 44)
			.background(Color(uiColor: .systemGray3).opacity(0.55), in: Circle())
			.contentShape(Circle())
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

	private func compactTextKey(_ title: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(.subheadline.weight(.medium))
				.frame(width: 42, height: 42)
				.background(Color(uiColor: .systemGray3).opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
		}
		.buttonStyle(.plain)
	}

	private func textActionKey(_ title: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(.subheadline.weight(.medium))
				.frame(minWidth: 64, minHeight: 42)
				.background(Color(uiColor: .systemGray3).opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
		}
		.buttonStyle(.plain)
	}

	/// Voice dock send/return — circle like Typeless side actions.
	private func circularTextKey(_ title: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(.system(size: title.count > 2 ? 11 : 13, weight: .medium))
				.minimumScaleFactor(0.7)
				.lineLimit(1)
				.frame(width: 44, height: 44)
				.background(Color(uiColor: .systemGray3).opacity(0.55), in: Circle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(title)
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

private struct CorrectionDisplayRun: Identifiable {
	let id: Int
	let text: String
	let spanID: Int?
}

private struct CorrectionFlowLayout: Layout {
	let spacing: CGFloat

	func sizeThatFits(
		proposal: ProposedViewSize,
		subviews: Subviews,
		cache: inout ()
	) -> CGSize {
		let width = proposal.width ?? 320
		var x: CGFloat = 0
		var y: CGFloat = 0
		var rowHeight: CGFloat = 0
		for subview in subviews {
			let size = subview.sizeThatFits(.unspecified)
			if x > 0, x + size.width > width {
				x = 0
				y += rowHeight + spacing
				rowHeight = 0
			}
			x += size.width + spacing
			rowHeight = max(rowHeight, size.height)
		}
		return CGSize(width: width, height: y + rowHeight)
	}

	func placeSubviews(
		in bounds: CGRect,
		proposal: ProposedViewSize,
		subviews: Subviews,
		cache: inout ()
	) {
		var x = bounds.minX
		var y = bounds.minY
		var rowHeight: CGFloat = 0
		for subview in subviews {
			let size = subview.sizeThatFits(.unspecified)
			if x > bounds.minX, x + size.width > bounds.maxX {
				x = bounds.minX
				y += rowHeight + spacing
				rowHeight = 0
			}
			subview.place(
				at: CGPoint(x: x, y: y),
				anchor: .topLeading,
				proposal: ProposedViewSize(size)
			)
			x += size.width + spacing
			rowHeight = max(rowHeight, size.height)
		}
	}
}

/// Same nine-bar, symmetric real-level waveform used by the main app.
private struct ListeningWaveform: View {
	@State private var level = 0.0
	@State private var speaking = false
	@State private var aboveCount = 0
	@State private var belowCount = 0
	@State private var lastTick = Date().timeIntervalSinceReferenceDate
	private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

	var body: some View {
		TimelineView(.animation(minimumInterval: 0.05)) { timeline in
			let heights = VoiceWaveformMath.barHeights(
				level: level,
				time: timeline.date.timeIntervalSinceReferenceDate
			)
			let opacity = level <= 0.008 ? 0.48 : 0.62 + pow(level, 0.72) * 0.38
			HStack(spacing: 2) {
				ForEach(heights.indices, id: \.self) { index in
					Capsule()
						.fill(.white.opacity(opacity))
						.frame(width: 3, height: heights[index])
				}
			}
			.frame(height: 24)
		}
		.onReceive(timer) { _ in
			let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
			defaults?.synchronize()
			let raw = min(1, (defaults?.double(forKey: "dictation.level") ?? 0) * 3.2)
			if raw > 0.18 {
				aboveCount += 1
				belowCount = 0
				if aboveCount >= 2 { speaking = true }
			} else if raw < 0.10 {
				belowCount += 1
				aboveCount = 0
				if belowCount >= 6 { speaking = false }
			}

			let normalized = max(0, (raw - 0.10) / 0.90)
			let target = speaking ? pow(normalized, 0.45) : 0
			let now = Date().timeIntervalSinceReferenceDate
			let elapsedMs = min(48, max(0, (now - lastTick) * 1_000))
			lastTick = now
			let timeConstant = target > level ? 55.0 : 120.0
			let alpha = 1 - exp(-elapsedMs / timeConstant)
			let next = level + (target - level) * alpha
			level = target <= 0.008 && next < 0.008 ? 0 : next
		}
	}
}
