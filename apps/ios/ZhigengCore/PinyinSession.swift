import Foundation

/// The composing buffer between the keys and the document: what has been typed but not
/// yet committed, how it reads, and what it could become.
///
/// Kept out of the keyboard extension's view layer so it can be tested with `swift test`,
/// and because committing a candidate that covers only part of the buffer is the one
/// piece of pinyin input that silently loses the user's keys when it is wrong.
public struct PinyinSession {
	private let dictionary: PinyinDictionary
	private let composer: PinyinComposer

	public private(set) var typed = ""

	/// Digits 2-9 instead of letters. The two layouts cannot share a buffer -- the same
	/// characters mean different things -- so switching drops whatever was in flight.
	public var nineKey: Bool {
		didSet {
			if nineKey != oldValue { typed = "" }
		}
	}

	public init(dictionary: PinyinDictionary, nineKey: Bool = false) {
		self.dictionary = dictionary
		self.composer = PinyinComposer(dictionary: dictionary)
		self.nineKey = nineKey
	}

	public var isComposing: Bool { !typed.isEmpty }

	public var input: PinyinInput {
		nineKey ? .nineKey(typed) : .full(typed)
	}

	public func candidates(limit: Int = 12, boosts: [String: Int] = [:]) -> [PinyinCandidate] {
		guard isComposing else { return [] }
		return composer.candidates(for: input, limit: limit, boosts: boosts)
	}

	// MARK: - Editing

	public mutating func append(_ character: Character) {
		let accepted = character == "'"
			|| (nineKey ? character.isNumber && character != "0" && character != "1"
			            : character.isASCII && character.isLetter)
		guard accepted else { return }
		typed.append(Character(character.lowercased()))
	}

	/// `false` when there was nothing to erase, which is the caller's cue to delete
	/// document text instead.
	public mutating func backspace() -> Bool {
		guard isComposing else { return false }
		typed.removeLast()
		return true
	}

	/// Consumes the keys the candidate covers and returns the text to insert. Whatever
	/// the candidate did not cover stays in the buffer for the user to keep composing.
	public mutating func commit(_ candidate: PinyinCandidate) -> String {
		var remaining = candidate.length
		var index = typed.startIndex
		while index < typed.endIndex, remaining > 0 {
			if typed[index] != "'" { remaining -= 1 }
			index = typed.index(after: index)
		}
		// A separator sitting on the new boundary has already done its job.
		while index < typed.endIndex, typed[index] == "'" {
			index = typed.index(after: index)
		}
		typed = String(typed[index...])
		return candidate.text
	}

	public mutating func clear() {
		typed = ""
	}

	// MARK: - Code line

	/// How the keys read, split into syllables — `ni'hao`, including for nine-key where
	/// the user pressed digits and needs to see what the keyboard made of them.
	public var display: String {
		guard isComposing else { return "" }
		var byStart: [Int: [PinyinSpan]] = [:]
		for span in PinyinSegmenter.spans(input) {
			byStart[span.start, default: []].append(span)
		}

		var syllables: [String] = []
		var cursor = 0
		let keyCount = input.keys.count
		while cursor < keyCount, let here = byStart[cursor], !here.isEmpty {
			guard let longest = here.map(\.length).max() else { break }
			// Nine-key spans are ambiguous by construction (one digit, three letters).
			// Resolving by how common the syllable is agrees with the candidate the
			// language model puts first often enough to be worth its five lines.
			let pick = here
				.filter { $0.length == longest }
				.sorted { lhs, rhs in
					let left = commonness(lhs.syllable), right = commonness(rhs.syllable)
					return left == right ? lhs.syllable < rhs.syllable : left > right
				}
				.first
			guard let pick else { break }
			syllables.append(pick.syllable)
			cursor += pick.length
		}

		// Letters the segmenter could not place (a typo, usually) still have to be visible.
		if cursor < keyCount {
			syllables.append(untypedTail(from: cursor))
		}
		return syllables.joined(separator: "'")
	}

	private func commonness(_ syllable: String) -> Int {
		dictionary.entries(for: syllable).first?.weight ?? 0
	}

	private func untypedTail(from key: Int) -> String {
		var skipped = 0
		var index = typed.startIndex
		while index < typed.endIndex, skipped < key {
			if typed[index] != "'" { skipped += 1 }
			index = typed.index(after: index)
		}
		return String(typed[index...]).replacingOccurrences(of: "'", with: "")
	}
}
