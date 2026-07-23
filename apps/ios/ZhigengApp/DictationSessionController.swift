import Foundation
import Observation
import ZhigengCore

@MainActor
@Observable
final class DictationSessionController {
	enum Phase: Equatable {
		case idle, listening, processing, done, incomplete, failed
	}

	var phase: Phase = .idle
	var draft = ""
	var originalDraft = ""
	var elapsed = 0
	var statusMessage = "可以开始"
	var requestId = UUID().uuidString
	var level = 0.0

	private let store: AppStore
	private let capture = AudioCaptureEngine()
	private var client: VolcAsrClient?
	private var timer: Timer?

	init(store: AppStore) {
		self.store = store
	}

	func toggle() {
		switch phase {
		case .idle, .failed, .done, .incomplete:
			guard store.microphoneGranted else {
				store.requestMicrophone { [weak self] ok in
					if ok { self?.start() }
				}
				return
			}
			start()
		case .listening:
			finish()
		default:
			break
		}
	}

	func start() {
		teardown()
		requestId = store.pendingDictationRequestId ?? UUID().uuidString
		draft = ""
		originalDraft = ""
		elapsed = 0
		statusMessage = "正在连接识别…"
		phase = .listening

		guard let authToken = store.remote.asrAuthToken,
		      let apiBase = store.remote.accountApiBase
		else {
			phase = .failed
			statusMessage = VolcAsrClientError.notSignedIn.errorDescription ?? "请先登录"
			return
		}

		let asr = VolcAsrClient(
			config: VolcAsrClient.Config(
				apiBase: apiBase,
				authToken: authToken,
				hotWords: store.lexicon.asrHotWords()
			)
		) { [weak self] event in
			Task { @MainActor in
				self?.handle(event)
			}
		}
		client = asr
		asr.start()

		guard capture.start(onPCM: { [weak asr] data in
			asr?.sendPCM(data)
		}, onLevel: { [weak self] value in
			Task { @MainActor in self?.level = value }
		}) else {
			phase = .failed
			statusMessage = "麦克风暂时不可用"
			asr.close()
			client = nil
			return
		}

		timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
			Task { @MainActor in self?.elapsed += 1 }
		}
	}

	func finish() {
		timer?.invalidate()
		timer = nil
		capture.stop()
		phase = .processing
		statusMessage = "正在整理…"
		client?.finish()
	}

	func saveEdits() {
		store.updateHistoryText(id: requestId, cleanedText: draft)
		for (from, to) in TextEditDiff.replacements(original: originalDraft, edited: draft) {
			_ = store.learnCorrection(original: from, replacement: to, requestId: requestId)
		}
		originalDraft = draft
		statusMessage = "已保存"
	}

	func reset() {
		teardown()
		phase = .idle
		draft = ""
		originalDraft = ""
		elapsed = 0
		statusMessage = "可以开始"
	}

	func teardown() {
		timer?.invalidate()
		timer = nil
		capture.stop()
		client?.abort()
		client = nil
		level = 0
	}

	private func handle(_ event: AsrStreamEvent) {
		switch event {
		case .ready:
			statusMessage = "正在听 · 轻声说就好"
		case let .partial(text):
			draft = text
			statusMessage = "正在听"
		case let .done(result):
			capture.stop()
			timer?.invalidate()
			timer = nil
			draft = result.text
			originalDraft = result.text
			if result.incomplete {
				phase = .incomplete
				statusMessage = result.text.isEmpty ? "未完整处理" : "未完整，可改后保存"
			} else if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				phase = .failed
				statusMessage = "没有听清，请再说一次"
			} else {
				phase = .done
				statusMessage = result.directStructured ? "已整理" : "已完成"
			}
			if !result.text.isEmpty {
				let historyId = store.pendingDictationRequestId ?? requestId
				store.appendHistory(
					DictationHistoryItem(
						id: historyId,
						source: store.pendingDictationRequestId == nil ? .main : .keyboard,
						status: result.incomplete ? .incomplete : .ready,
						cleanedText: result.text,
						directStructured: result.directStructured,
						durationMs: elapsed * 1000,
						processingTags: result.directStructured ? ["按场景整理"] : []
					)
				)
				if let pendingId = store.pendingDictationRequestId, !result.incomplete {
					try? AppGroupBridge().writeResult(
						DictationResult(
							requestId: pendingId,
							status: .ready,
							text: result.text,
							segments: result.segments,
							directStructured: result.directStructured
						)
					)
					store.pendingDictationRequestId = nil
				}
			}
			client = nil
		case let .failed(message):
			capture.stop()
			timer?.invalidate()
			timer = nil
			phase = .failed
			statusMessage = message
			client = nil
		}
	}
}
