import Foundation
import SpeechEngineAsrToB
import ZhigengCore
import os.log

/// Thin wrapper around Volc `SpeechEngineAsrToB` for streaming ASR with external PCM.
final class VolcAsrEngine: NSObject, SpeechEngineDelegate {
	struct Credentials: Sendable {
		let appId: String
		let resourceId: String
		let token: String
	}

	private let engine = SpeechEngine()
	private let queue = DispatchQueue(label: "app.zhigeng.volc-asr")
	private let queueKey = DispatchSpecificKey<Void>()
	private let onEvent: @Sendable (AsrStreamEvent) -> Void
	private var running = false
	private var ready = false
	private var finishRequested = false
	private var created = false
	private var pendingAudio = Data()
	private var fedSamples = 0

	init(onEvent: @escaping @Sendable (AsrStreamEvent) -> Void) {
		self.onEvent = onEvent
		super.init()
		queue.setSpecific(key: queueKey, value: ())
	}

	deinit {
		syncOnQueue {
			if created {
				_ = engine.send(SEDirectiveSyncStopEngine)
				engine.destroy()
				created = false
			}
		}
	}

	static func prepareEnvironment() {
		_ = SpeechEngine.prepareEnvironment()
	}

	func configure(credentials: Credentials, hotWords: [String], uid: String) -> Bool {
		var ok = false
		syncOnQueue {
			if created {
				_ = engine.send(SEDirectiveSyncStopEngine)
				engine.destroy()
				created = false
			}
			ready = false
			running = false
			finishRequested = false
			pendingAudio.removeAll(keepingCapacity: true)
			fedSamples = 0
			guard engine.createEngine(with: self) else { return }
			created = true
			engine.setStringParam(SE_ASR_ENGINE, forKey: SE_PARAMS_KEY_ENGINE_NAME_STRING)
			engine.setStringParam(credentials.appId, forKey: SE_PARAMS_KEY_APP_ID_STRING)
			engine.setStringParam(credentials.token, forKey: SE_PARAMS_KEY_APP_TOKEN_STRING)
			engine.setIntParam(Int(SEProtocolTypeSeed.rawValue), forKey: SE_PARAMS_KEY_PROTOCOL_TYPE_INT)
			engine.setStringParam(credentials.resourceId, forKey: SE_PARAMS_KEY_RESOURCE_ID_STRING)
			engine.setStringParam(uid, forKey: SE_PARAMS_KEY_UID_STRING)
			engine.setStringParam("wss://openspeech.bytedance.com", forKey: SE_PARAMS_KEY_ASR_ADDRESS_STRING)
			engine.setStringParam("/api/v3/sauc/bigmodel", forKey: SE_PARAMS_KEY_ASR_URI_STRING)
			engine.setStringParam(SE_RECORDER_TYPE_STREAM, forKey: SE_PARAMS_KEY_RECORDER_TYPE_STRING)
			engine.setIntParam(Int(SEAsrScenarioStreaming.rawValue), forKey: SE_PARAMS_KEY_ASR_SCENARIO_INT)
			engine.setStringParam(SE_ASR_RESULT_TYPE_FULL, forKey: SE_PARAMS_KEY_ASR_RESULT_TYPE_STRING)
			engine.setBoolParam(true, forKey: SE_PARAMS_KEY_ASR_SHOW_PUNC_BOOL)
			engine.setStringParam("{\"show_utterances\":true}", forKey: SE_PARAMS_KEY_ASR_REQ_PARAMS_STRING)
			engine.setBoolParam(false, forKey: SE_PARAMS_KEY_ASR_AUTO_STOP_BOOL)
			engine.setBoolParam(true, forKey: SE_PARAMS_KEY_PREVENT_PLAYER_CREATION_BOOL)
			engine.setIntParam(16_000, forKey: SE_PARAMS_KEY_CUSTOM_SAMPLE_RATE_INT)
			engine.setIntParam(1, forKey: SE_PARAMS_KEY_CUSTOM_CHANNEL_INT)
			engine.setStringParam(SE_LOG_LEVEL_WARN, forKey: SE_PARAMS_KEY_LOG_LEVEL_STRING)
			let initCode = engine.initEngine()
			NSLog("[ZG] ASR init code=\(initCode.rawValue)")
			ok = initCode == SENoError
			if ok, let json = Self.hotWordsJSON(hotWords) {
				_ = engine.send(SEDirectiveUpdateAsrHotWords, data: json)
			}
		}
		return ok
	}

	func start() -> Bool {
		var ok = false
		syncOnQueue {
			finishRequested = false
			ready = false
			let startCode = engine.send(SEDirectiveStartEngine)
			NSLog("[ZG] ASR start code=\(startCode.rawValue)")
			ok = startCode == SENoError
			running = ok
		}
		return ok
	}

	func sendPCM(_ data: Data) {
		guard !data.isEmpty else { return }
		queue.async { [weak self] in
			guard let self, self.running, self.ready else { return }
			self.pendingAudio.append(data)
			let chunkBytes = 16_000 * MemoryLayout<Int16>.size / 5
			while self.pendingAudio.count >= chunkBytes {
				var chunk = Data(self.pendingAudio.prefix(chunkBytes))
				self.pendingAudio.removeFirst(chunkBytes)
				self.feedAudio(&chunk)
			}
		}
	}

	func finish() {
		queue.async { [weak self] in
			guard let self, self.running else { return }
			if !self.pendingAudio.isEmpty {
				var remainder = self.pendingAudio
				self.pendingAudio.removeAll(keepingCapacity: true)
				self.feedAudio(&remainder)
			}
			self.finishRequested = true
			_ = self.engine.send(SEDirectiveFinishTalking)
		}
	}

	func abort() {
		queue.async { [weak self] in
			guard let self else { return }
			self.running = false
			self.ready = false
			self.pendingAudio.removeAll(keepingCapacity: false)
			if self.created {
				_ = self.engine.send(SEDirectiveSyncStopEngine)
				self.engine.destroy()
				self.created = false
			}
		}
	}

	func close() {
		queue.async { [weak self] in
			guard let self else { return }
			self.running = false
			self.ready = false
			self.pendingAudio.removeAll(keepingCapacity: false)
			if self.created {
				_ = self.engine.send(SEDirectiveSyncStopEngine)
				self.engine.destroy()
				self.created = false
			}
		}
	}

	func onMessage(with type: SEMessageType, andData data: Data) {
		let payload = String(data: data, encoding: .utf8) ?? ""
		Self.logDiagnostic("ASR message type=\(type.rawValue) bytes=\(data.count)")
		switch type {
		case SEEngineStart, SEConnectionConnected:
			queue.async { [weak self] in
				self?.ready = true
			}
			emit(.ready)
		case SEPartialResult, SEAsrPartialResult:
			if let text = Self.extractText(from: payload), !text.isEmpty {
				emit(.partial(text))
			}
		case SEFinalResult:
			queue.async { [weak self] in
				self?.running = false
				self?.ready = false
			}
			emit(.done(VolcAsrPayloadParser.parse(payload) ?? VoiceResult(text: "")))
		case SEEngineError:
			queue.async { [weak self] in
				self?.running = false
				self?.ready = false
			}
			emit(.failed(Self.extractError(from: payload) ?? "豆包识别失败"))
		case SEEngineStop:
			if finishRequested {
				queue.async { [weak self] in
					self?.running = false
					self?.ready = false
				}
			}
		default:
			break
		}
	}

	private func emit(_ event: AsrStreamEvent) {
		onEvent(event)
	}

	private func feedAudio(_ data: inout Data) {
		let sampleCount = data.count / MemoryLayout<Int16>.size
		guard sampleCount > 0 else { return }
		data.withUnsafeMutableBytes { raw in
			guard let base = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
			let code = engine.feedAudio(base, length: Int32(sampleCount))
			fedSamples += sampleCount
			if fedSamples == sampleCount || fedSamples / 16_000 != (fedSamples - sampleCount) / 16_000 {
				Self.logDiagnostic("ASR fed samples=\(fedSamples) code=\(code.rawValue)")
			}
			if code != SENoError {
				Self.logDiagnostic("ASR feed code=\(code.rawValue) samples=\(sampleCount)")
			}
		}
	}

	private static func logDiagnostic(_ message: String) {
		os_log(
			"%{public}@",
			log: OSLog(subsystem: "app.zhigeng.ios", category: "asr"),
			type: .fault,
			"[ZG] \(message)"
		)
	}

	private func syncOnQueue(_ operation: () -> Void) {
		if DispatchQueue.getSpecific(key: queueKey) != nil {
			operation()
		} else {
			queue.sync(execute: operation)
		}
	}

	private static func hotWordsJSON(_ words: [String]) -> String? {
		let hotwords: [[String: Any]] = words.prefix(100).map {
			["word": $0, "scale": 2.0]
		}
		let body: [String: Any] = ["hotwords": hotwords]
		guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
		return String(data: data, encoding: .utf8)
	}

	static func extractText(from payload: String) -> String? {
		VolcAsrPayloadParser.parse(payload)?.text
	}

	static func extractError(from payload: String) -> String? {
		guard let data = payload.data(using: .utf8),
		      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return payload.isEmpty ? nil : payload }
		if let message = root["message"] as? String, !message.isEmpty { return message }
		if let errMsg = root["err_msg"] as? String, !errMsg.isEmpty { return errMsg }
		if let error = root["error"] as? String, !error.isEmpty { return error }
		return extractText(from: payload)
	}
}
