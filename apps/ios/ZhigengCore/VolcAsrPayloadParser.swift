import Foundation

public enum VolcAsrPayloadParser {
	public static func parse(_ payload: String) -> VoiceResult? {
		guard !payload.isEmpty else { return nil }
		guard let data = payload.data(using: .utf8),
		      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else {
			return VoiceResult(text: payload)
		}
		return parseObject(root)
	}

	private static func parseObject(_ root: [String: Any]) -> VoiceResult? {
		if let payload = root["payload"] as? [String: Any],
		   let nested = parseObject(payload)
		{
			return nested
		}

		if let result = root["result"] as? [String: Any] {
			return makeResult(from: result)
		}

		if let results = root["result"] as? [[String: Any]] {
			let parsed = results.compactMap(makeResult)
			guard !parsed.isEmpty else { return nil }
			return VoiceResult(
				text: parsed.map(\.text).joined(),
				segments: parsed.flatMap(\.segments)
			)
		}

		return makeResult(from: root)
	}

	private static func makeResult(from object: [String: Any]) -> VoiceResult? {
		let segments = (object["utterances"] as? [[String: Any]] ?? []).compactMap(parseSegment)
		let text = (object["text"] as? String) ?? segments.map(\.text).joined()
		guard !text.isEmpty else { return nil }
		return VoiceResult(text: text, segments: segments)
	}

	private static func parseSegment(_ object: [String: Any]) -> VoiceSegment? {
		guard let text = object["text"] as? String, !text.isEmpty else { return nil }
		let words = (object["words"] as? [[String: Any]] ?? []).compactMap(parseWord)
		return VoiceSegment(
			text: text,
			startTimeMs: int(object["start_time"]),
			endTimeMs: int(object["end_time"]),
			definite: object["definite"] as? Bool,
			words: words
		)
	}

	private static func parseWord(_ object: [String: Any]) -> VoiceWord? {
		guard let text = object["text"] as? String, !text.isEmpty else { return nil }
		return VoiceWord(
			text: text,
			startTimeMs: int(object["start_time"]),
			endTimeMs: int(object["end_time"]),
			confidence: (object["confidence"] as? NSNumber)?.doubleValue
		)
	}

	private static func int(_ value: Any?) -> Int? {
		(value as? NSNumber)?.intValue
	}
}
