import Foundation

public struct VoiceWord: Codable, Equatable, Sendable {
	public var text: String
	public var startTimeMs: Int?
	public var endTimeMs: Int?
	public var confidence: Double?

	public init(
		text: String,
		startTimeMs: Int? = nil,
		endTimeMs: Int? = nil,
		confidence: Double? = nil
	) {
		self.text = text
		self.startTimeMs = startTimeMs
		self.endTimeMs = endTimeMs
		self.confidence = confidence
	}
}

public struct VoiceSegment: Codable, Equatable, Sendable {
	public var text: String
	public var startTimeMs: Int?
	public var endTimeMs: Int?
	public var definite: Bool?
	public var words: [VoiceWord]

	public init(
		text: String,
		startTimeMs: Int? = nil,
		endTimeMs: Int? = nil,
		definite: Bool? = nil,
		words: [VoiceWord] = []
	) {
		self.text = text
		self.startTimeMs = startTimeMs
		self.endTimeMs = endTimeMs
		self.definite = definite
		self.words = words
	}
}

public struct VoiceResult: Equatable, Sendable {
	public var text: String
	public var directStructured: Bool
	public var incomplete: Bool
	public var segments: [VoiceSegment]

	public init(
		text: String,
		directStructured: Bool = false,
		incomplete: Bool = false,
		segments: [VoiceSegment] = []
	) {
		self.text = text
		self.directStructured = directStructured
		self.incomplete = incomplete
		self.segments = segments
	}

	public var isInsertable: Bool {
		!incomplete && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
}

public enum AsrClientMessage: Equatable, Sendable {
	case ready(model: String?)
	case partial(text: String)
	case done(fullText: String, directStructured: Bool)
	case error(message: String)
	case unknown
}

/// Parses asr-proxy text frames. Audio / WebSocket IO stays platform-specific.
public enum AsrProtocol {
	public static func parseServerText(_ text: String) -> AsrClientMessage {
		guard let data = text.data(using: .utf8),
		      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let type = obj["type"] as? String
		else {
			return .unknown
		}
		switch type {
		case "ready":
			return .ready(model: obj["model"] as? String)
		case "partial":
			return .partial(text: (obj["text"] as? String) ?? "")
		case "done":
			return .done(
				fullText: (obj["fullText"] as? String) ?? "",
				directStructured: (obj["directStructured"] as? Bool) ?? false
			)
		case "error":
			return .error(message: (obj["message"] as? String) ?? "ASR error")
		default:
			return .unknown
		}
	}

	public static func startPayload(
		sampleRate: Int = 16_000,
		format: String = "pcm",
		languageHints: [String] = ["zh", "en"],
		mode: String = "structure",
		authToken: String? = nil,
		hotWords: [String] = [],
		model: String? = nil
	) -> Data {
		var body: [String: Any] = [
			"type": "start",
			"sampleRate": sampleRate,
			"format": format,
			"languageHints": languageHints,
			"mode": mode,
		]
		if let authToken, !authToken.isEmpty {
			body["authToken"] = authToken
		}
		if !hotWords.isEmpty {
			body["hotWords"] = Array(hotWords.prefix(100))
		}
		if let model, !model.isEmpty {
			body["model"] = model
		}
		return try! JSONSerialization.data(withJSONObject: body)
	}

	public static func finishPayload() -> Data {
		try! JSONSerialization.data(withJSONObject: ["type": "finish"])
	}

	public static func abortPayload() -> Data {
		try! JSONSerialization.data(withJSONObject: ["type": "abort"])
	}
}

/// Session state machine mirroring packages/voice aliyun-asr incomplete rules.
public final class AsrSessionState: @unchecked Sendable {
	public private(set) var sessionReady = false
	public private(set) var finishRequested = false
	public private(set) var lastFullText = ""
	public private(set) var directStructured = false
	public private(set) var resolved = false
	public private(set) var result: VoiceResult?

	public init() {}

	public func handle(_ message: AsrClientMessage) {
		guard !resolved else { return }
		switch message {
		case .ready:
			sessionReady = true
		case let .partial(text):
			lastFullText = text
		case let .done(fullText, structured):
			lastFullText = fullText.isEmpty ? lastFullText : fullText
			directStructured = structured
			finalize(VoiceResult(text: lastFullText, directStructured: structured, incomplete: false))
		case let .error(message):
			finalize(VoiceResult(text: lastFullText, directStructured: false, incomplete: true))
			_ = message
		case .unknown:
			break
		}
	}

	public func requestFinish() {
		finishRequested = true
	}

	/// Socket closed before done: keep partial text but mark incomplete.
	public func handleUnexpectedClose() {
		guard !resolved else { return }
		if finishRequested, !lastFullText.isEmpty {
			finalize(VoiceResult(text: lastFullText, directStructured: directStructured, incomplete: true))
		} else if !lastFullText.isEmpty {
			finalize(VoiceResult(text: lastFullText, directStructured: false, incomplete: true))
		} else {
			finalize(VoiceResult(text: "", directStructured: false, incomplete: true))
		}
	}

	public func handleFinishTimeout() {
		guard !resolved else { return }
		finalize(VoiceResult(text: lastFullText, directStructured: directStructured, incomplete: true))
	}

	private func finalize(_ value: VoiceResult) {
		resolved = true
		result = value
	}
}
