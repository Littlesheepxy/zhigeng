import Foundation

public enum PersonalTermSource: String, Codable, Sendable {
	case manual
	case pinyinCorrection
	case desktopSync
}

/// 人 / 事 / 词。「我的画像」是统计视图，不是词条，不在此枚举内。
public enum PersonalTermKind: String, Codable, Sendable, CaseIterable {
	case person
	case project
	case word
}

public struct PersonalTerm: Codable, Equatable, Identifiable, Sendable {
	public var id: String
	public var text: String
	public var source: PersonalTermSource
	public var kind: PersonalTermKind
	public var weight: Int
	public var lastUsedAt: TimeInterval
	public var createdAt: TimeInterval

	public init(
		id: String = UUID().uuidString,
		text: String,
		source: PersonalTermSource,
		kind: PersonalTermKind = .word,
		weight: Int = 1,
		lastUsedAt: TimeInterval = Date().timeIntervalSince1970,
		createdAt: TimeInterval = Date().timeIntervalSince1970
	) {
		self.id = id
		self.text = text
		self.source = source
		self.kind = kind
		self.weight = weight
		self.lastUsedAt = lastUsedAt
		self.createdAt = createdAt
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(String.self, forKey: .id)
		text = try container.decode(String.self, forKey: .text)
		source = try container.decode(PersonalTermSource.self, forKey: .source)
		kind = try container.decodeIfPresent(PersonalTermKind.self, forKey: .kind) ?? .word
		weight = try container.decode(Int.self, forKey: .weight)
		lastUsedAt = try container.decode(TimeInterval.self, forKey: .lastUsedAt)
		createdAt = try container.decode(TimeInterval.self, forKey: .createdAt)
	}
}

public struct CorrectionEvent: Equatable, Sendable {
	public var original: String
	public var replacement: String
	public var requestId: String
	public var at: TimeInterval

	public init(original: String, replacement: String, requestId: String, at: TimeInterval = Date().timeIntervalSince1970) {
		self.original = original
		self.replacement = replacement
		self.requestId = requestId
		self.at = at
	}
}

/// Shared personal lexicon for pinyin candidate boosts and ASR hotWords.
///
/// Learning rules (v1):
/// - pinyin: picking a non-top candidate records a correction; every commit
///   reinforces via `recordUse`
/// - voice: same requestId + short window after insert (see `recordCorrection`)
/// - user can forget / undo later
public final class PersonalLexicon: @unchecked Sendable {
	public static let correctionWindowSeconds: TimeInterval = 30
	public static let maxHotWords = 100

	private var terms: [PersonalTerm]
	private let now: () -> TimeInterval

	public init(terms: [PersonalTerm] = [], now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
		self.terms = terms
		self.now = now
	}

	public var allTerms: [PersonalTerm] { terms }

	public func asrHotWords(limit: Int = PersonalLexicon.maxHotWords) -> [String] {
		rankedTexts(limit: limit)
	}

	public func rimeBoosts(limit: Int = PersonalLexicon.maxHotWords) -> [(text: String, weight: Int)] {
		ranked(limit: limit).map { ($0.text, min(5, max(1, $0.weight))) }
	}

	@discardableResult
	public func recordCorrection(
		original: String,
		replacement: String,
		requestId: String,
		insertedAt: TimeInterval,
		at: TimeInterval? = nil
	) -> PersonalTerm? {
		let moment = at ?? now()
		let o = original.trimmingCharacters(in: .whitespacesAndNewlines)
		let r = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !r.isEmpty, r != o else { return nil }
		guard !requestId.isEmpty else { return nil }
		guard moment - insertedAt <= Self.correctionWindowSeconds else { return nil }

		if let idx = terms.firstIndex(where: { $0.text.caseInsensitiveCompare(r) == .orderedSame }) {
			terms[idx].weight += 1
			terms[idx].lastUsedAt = moment
			terms[idx].source = .pinyinCorrection
			return terms[idx]
		}

		let term = PersonalTerm(text: r, source: .pinyinCorrection, weight: 2, lastUsedAt: moment, createdAt: moment)
		terms.append(term)
		return term
	}

	@discardableResult
	public func addManual(_ text: String, kind: PersonalTermKind = .word) -> PersonalTerm? {
		let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !t.isEmpty else { return nil }
		if let idx = terms.firstIndex(where: { $0.text.caseInsensitiveCompare(t) == .orderedSame }) {
			terms[idx].lastUsedAt = now()
			terms[idx].kind = kind
			return terms[idx]
		}
		let term = PersonalTerm(text: t, source: .manual, kind: kind, weight: 3, lastUsedAt: now())
		terms.append(term)
		return term
	}

	/// Reinforce a word the user actually committed (pinyin pick, voice correction, …).
	/// Unlike `recordCorrection` there is no window — choosing it is the signal.
	@discardableResult
	public func recordUse(_ text: String, source: PersonalTermSource = .pinyinCorrection) -> PersonalTerm? {
		let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !t.isEmpty else { return nil }
		if let idx = terms.firstIndex(where: { $0.text.caseInsensitiveCompare(t) == .orderedSame }) {
			terms[idx].weight += 1
			terms[idx].lastUsedAt = now()
			terms[idx].source = source
			return terms[idx]
		}
		let term = PersonalTerm(text: t, source: source, weight: 2, lastUsedAt: now(), createdAt: now())
		terms.append(term)
		return term
	}

	public func setKind(id: String, kind: PersonalTermKind) {
		guard let idx = terms.firstIndex(where: { $0.id == id }) else { return }
		terms[idx].kind = kind
	}

	public func forget(id: String) {
		terms.removeAll { $0.id == id }
	}

	public func encode() throws -> Data {
		try JSONEncoder().encode(terms)
	}

	public static func decode(from data: Data, now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) throws -> PersonalLexicon {
		let terms = try JSONDecoder().decode([PersonalTerm].self, from: data)
		return PersonalLexicon(terms: terms, now: now)
	}

	private func ranked(limit: Int) -> [PersonalTerm] {
		terms
			.sorted {
				if $0.weight != $1.weight { return $0.weight > $1.weight }
				return $0.lastUsedAt > $1.lastUsedAt
			}
			.prefix(limit)
			.map { $0 }
	}

	private func rankedTexts(limit: Int) -> [String] {
		ranked(limit: limit).map(\.text)
	}
}
