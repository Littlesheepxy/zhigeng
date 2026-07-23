import Foundation

public struct SpeechLexiconTerm: Equatable, Sendable {
	public var text: String
	public var weight: Int

	public init(text: String, weight: Int = 1) {
		self.text = text
		self.weight = weight
	}
}

public struct SpeechCorrectionCandidate: Equatable, Sendable {
	public var text: String
	public var weight: Int

	public init(text: String, weight: Int) {
		self.text = text
		self.weight = weight
	}
}

public struct SpeechCorrectionSpan: Equatable, Identifiable, Sendable {
	public var id: Int
	public var start: Int
	public var length: Int
	public var text: String
	public var candidates: [SpeechCorrectionCandidate]

	public init(
		id: Int,
		start: Int,
		length: Int,
		text: String,
		candidates: [SpeechCorrectionCandidate]
	) {
		self.id = id
		self.start = start
		self.length = length
		self.text = text
		self.candidates = candidates
	}
}

public struct SpeechCorrectionReplacement: Equatable, Sendable {
	public var deleteCount: Int
	public var insert: String
	public var original: String
	public var replacement: String

	public init(deleteCount: Int, insert: String, original: String, replacement: String) {
		self.deleteCount = deleteCount
		self.insert = insert
		self.original = original
		self.replacement = replacement
	}
}

public struct SpeechCorrectionAnchor: Equatable, Sendable {
	public var contextBefore: String
	public var contextAfter: String

	public init(contextBefore: String, contextAfter: String) {
		self.contextBefore = contextBefore
		self.contextAfter = contextAfter
	}

	public static func capture(
		insertedText: String,
		contextBefore: String,
		contextAfter: String
	) -> SpeechCorrectionAnchor {
		let prefix = contextBefore.hasSuffix(insertedText)
			? String(contextBefore.dropLast(insertedText.count))
			: contextBefore
		return SpeechCorrectionAnchor(
			contextBefore: String(prefix.suffix(24)),
			contextAfter: String(contextAfter.prefix(24))
		)
	}

	public func matches(
		insertedText: String,
		contextBefore: String,
		contextAfter: String
	) -> Bool {
		guard contextBefore.hasSuffix(insertedText) else { return false }
		let prefix = String(contextBefore.dropLast(insertedText.count).suffix(24))
		return prefix == self.contextBefore
			&& String(contextAfter.prefix(24)) == self.contextAfter
	}
}

public struct SpeechCorrectionState: Equatable, Sendable {
	public var requestId: String
	public var text: String
	public var spans: [SpeechCorrectionSpan]

	public init(requestId: String, text: String, spans: [SpeechCorrectionSpan]) {
		self.requestId = requestId
		self.text = text
		self.spans = spans
	}

	public static func build(
		requestId: String,
		text: String,
		lexicon: [SpeechLexiconTerm]
	) -> SpeechCorrectionState {
		let terms = lexicon
			.filter { !$0.text.isEmpty && $0.text.count <= 8 }
			.reduce(into: [String: [SpeechLexiconTerm]]()) { result, term in
				result[Self.normalizedPinyin(term.text), default: []].append(term)
			}
		let maxLength = min(8, lexicon.map(\.text.count).max() ?? 0)
		guard maxLength > 0 else {
			return SpeechCorrectionState(requestId: requestId, text: text, spans: [])
		}

		var matches: [SpeechCorrectionSpan] = []
		let characters = Array(text)
		for start in characters.indices {
			for length in 1...min(maxLength, characters.count - start) {
				let source = String(characters[start..<(start + length)])
				.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
				guard !source.isEmpty else { continue }
				let key = normalizedPinyin(source)
				let candidates = (terms[key] ?? [])
					.filter { $0.text != source }
					.reduce(into: [String: Int]()) { values, term in
						values[term.text] = max(values[term.text] ?? Int.min, term.weight)
					}
					.map { SpeechCorrectionCandidate(text: $0.key, weight: $0.value) }
					.sorted {
						if $0.weight != $1.weight { return $0.weight > $1.weight }
						return $0.text.localizedStandardCompare($1.text) == .orderedAscending
					}
				guard !candidates.isEmpty else { continue }
				matches.append(
					SpeechCorrectionSpan(
						id: 0,
						start: start,
						length: length,
						text: source,
						candidates: Array(candidates.prefix(4))
					)
				)
			}
		}

		var occupied = IndexSet()
		let selected = matches
			.sorted {
				if $0.length != $1.length { return $0.length > $1.length }
				return $0.start < $1.start
			}
			.filter { match in
				let range = IndexSet(integersIn: match.start..<(match.start + match.length))
				guard occupied.intersection(range).isEmpty else { return false }
				occupied.formUnion(range)
				return true
			}
			.sorted { $0.start < $1.start }
			.enumerated()
			.map { index, span in
				SpeechCorrectionSpan(
					id: index,
					start: span.start,
					length: span.length,
					text: span.text,
					candidates: span.candidates
				)
			}
		return SpeechCorrectionState(requestId: requestId, text: text, spans: selected)
	}

	public func replacement(
		spanID: Int,
		with candidate: String,
		contextBefore: String
	) -> SpeechCorrectionReplacement? {
		guard contextBefore.hasSuffix(text),
		      let span = spans.first(where: { $0.id == spanID }),
		      span.candidates.contains(where: { $0.text == candidate }),
		      let updated = replacingText(in: span, with: candidate)
		else { return nil }
		return SpeechCorrectionReplacement(
			deleteCount: text.count,
			insert: updated,
			original: span.text,
			replacement: candidate
		)
	}

	public func cursorOffsetAfterSpan(_ spanID: Int, contextBefore: String) -> Int? {
		guard contextBefore.hasSuffix(text),
		      let span = spans.first(where: { $0.id == spanID })
		else { return nil }
		let upper = text.index(text.startIndex, offsetBy: span.start + span.length)
		return -text[upper...].utf16.count
	}

	private func replacingText(in span: SpeechCorrectionSpan, with replacement: String) -> String? {
		guard span.start >= 0, span.length > 0, span.start + span.length <= text.count else { return nil }
		let lower = text.index(text.startIndex, offsetBy: span.start)
		let upper = text.index(lower, offsetBy: span.length)
		var result = text
		result.replaceSubrange(lower..<upper, with: replacement)
		return result
	}

	private static func normalizedPinyin(_ text: String) -> String {
		let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
		let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
		return plain.lowercased().filter { $0.isLetter || $0.isNumber }
	}
}

public enum CursorVerticalDirection: Sendable {
	case up
	case down
}

public enum CursorNavigation {
	public static func horizontalOffset(
		steps: Int,
		contextBefore: String,
		contextAfter: String
	) -> Int {
		guard steps != 0 else { return 0 }
		if steps < 0 {
			let count = min(-steps, contextBefore.count)
			let start = contextBefore.index(contextBefore.endIndex, offsetBy: -count)
			return -contextBefore[start...].utf16.count
		}
		let count = min(steps, contextAfter.count)
		let end = contextAfter.index(contextAfter.startIndex, offsetBy: count)
		return contextAfter[..<end].utf16.count
	}

	public static func verticalOffset(
		direction: CursorVerticalDirection,
		contextBefore: String,
		contextAfter: String,
		approximateLineLength: Int
	) -> Int {
		let step = max(1, approximateLineLength)
		switch direction {
		case .up:
			if let newline = contextBefore.lastIndex(of: "\n") {
				let currentColumn = contextBefore.distance(from: contextBefore.index(after: newline), to: contextBefore.endIndex)
				let earlier = contextBefore[..<newline]
				let previousStart = earlier.lastIndex(of: "\n").map { earlier.index(after: $0) } ?? earlier.startIndex
				let previousLength = earlier.distance(from: previousStart, to: earlier.endIndex)
				let targetColumn = min(currentColumn, previousLength)
				let target = earlier.index(previousStart, offsetBy: targetColumn)
				return -contextBefore[target...].utf16.count
			}
			// ponytail: soft-wrap geometry is unavailable to keyboard extensions; use a coarse character step.
			let start = contextBefore.index(
				contextBefore.endIndex,
				offsetBy: -min(step, contextBefore.count)
			)
			return -contextBefore[start...].utf16.count
		case .down:
			if let newline = contextAfter.firstIndex(of: "\n") {
				let nextStart = contextAfter.index(after: newline)
				let trailing = contextAfter[nextStart...]
				let nextEnd = trailing.firstIndex(of: "\n") ?? trailing.endIndex
				let nextLength = trailing.distance(from: trailing.startIndex, to: nextEnd)
				let currentColumn = contextBefore
					.split(separator: "\n", omittingEmptySubsequences: false)
					.last?
					.count ?? 0
				let targetColumn = min(currentColumn, nextLength)
				let target = trailing.index(trailing.startIndex, offsetBy: targetColumn)
				return contextAfter[..<target].utf16.count
			}
			let end = contextAfter.index(
				contextAfter.startIndex,
				offsetBy: min(step, contextAfter.count)
			)
			return contextAfter[..<end].utf16.count
		}
	}
}
