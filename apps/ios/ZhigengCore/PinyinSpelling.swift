import Foundation

/// One way to read a run of keys as a single syllable, and what that reading costs.
public struct PinyinReading: Equatable, Sendable {
	/// Keys consumed from the input.
	public let length: Int
	/// Dictionary key form of the syllable — letters as typed, `ü` written `v`.
	public let syllable: String
	/// Log-space penalty, zero for a syllable the user spelled out in full.
	public let cost: Double
	/// The reading supplies letters that were never typed. This is the one relaxation
	/// that has to lose to a complete spelling of the same keys.
	public let invented: Bool
}

/// Everything the composer does beyond exact spelling: typing half a syllable, typing
/// only its initial, confusing s/sh, or hitting the wrong key.
///
/// Each relaxation carries a fixed penalty, which is what stops the guesses from burying
/// the people who spell correctly. The constants were tuned by `tools/pinyin-dict/probe.py`
/// against the shipped table; the gate is that full-pinyin accuracy does not move.
public enum PinyinSpelling {
	/// A guess that invented letters, when the keys also spell something complete.
	/// Deliberately not applied to fuzzy or typo readings: a fuzzy spelling is itself
	/// valid pinyin, so demoting it whenever an exact parse exists disables it outright.
	public static let demoteWhenExact = -2.0
	static let fuzzyCost = -2.0
	static let typoCost = -6.0
	/// Shorter stubs stand for more syllables, so they are worth less.
	static func prefixCost(_ length: Int) -> Double {
		switch length {
		case 1: return -3.0
		case 2: return -1.5
		default: return -1.0
		}
	}

	/// The longest Mandarin syllable (`zhuang`) is six letters.
	static let maxSyllableLength = 6

	// MARK: - Readings

	/// Every syllable the keys starting at `start` could stand for.
	public static func readings(_ input: PinyinInput, at start: Int) -> [PinyinReading] {
		let keys = input.keys
		guard start < keys.count else { return [] }

		var out: [PinyinReading] = []
		var frontier: Set<String> = [""]
		var index = start
		while index < keys.count {
			if index > start, input.boundaries.contains(index) { break }
			var next: Set<String> = []
			for prefix in frontier {
				for letter in keys[index] {
					let candidate = prefix + String(letter)
					if PinyinSyllableTable.prefixes.contains(candidate) { next.insert(candidate) }
				}
			}
			if next.isEmpty { break }
			frontier = next
			index += 1
			let length = index - start

			for typed in frontier {
				let spelled = PinyinSyllableTable.keyForms[typed]
				if let spelled {
					out.append(PinyinReading(length: length, syllable: spelled, cost: 0, invented: false))
					for variant in PinyinSyllableTable.fuzzy[spelled] ?? [] {
						out.append(PinyinReading(length: length, syllable: variant, cost: fuzzyCost, invented: false))
					}
				}
				// What the user might still be in the middle of typing. This is both the
				// tail completion (`shashih` -> shashihou) and 混拼 (`sha`+`s`+`h`).
				for candidate in PinyinSyllableTable.byPrefix[typed] ?? [] where candidate != spelled {
					out.append(
						PinyinReading(length: length, syllable: candidate, cost: prefixCost(length), invented: true)
					)
				}
			}
		}

		return out + typoReadings(input, at: start)
	}

	/// A mistyped syllable is usually not a valid prefix of anything, so the walk above
	/// dies on it — `sahshihou` stops at `sa`. These readings look at the raw letters
	/// instead, which is also why they are nine-key's exclusion: one key already stands
	/// for three letters there, and edit distance on top of that has no constraint left.
	private static func typoReadings(_ input: PinyinInput, at start: Int) -> [PinyinReading] {
		let keys = input.keys
		var out: [PinyinReading] = []
		var segment = ""
		var index = start
		while index < keys.count, index - start < maxSyllableLength {
			if index > start, input.boundaries.contains(index) { break }
			guard keys[index].count == 1, let letter = keys[index].first else { break }
			segment.append(letter)
			index += 1
			guard segment.count >= 2 else { continue }
			for candidate in editDistanceOne(segment) {
				out.append(
					PinyinReading(length: index - start, syllable: candidate, cost: typoCost, invented: false)
				)
			}
		}
		return out
	}

	/// Syllables one slip away: a neighbouring key, two letters swapped, or one letter
	/// too many. A missing letter is left to the prefix expansion above, which already
	/// covers it and costs less.
	static func editDistanceOne(_ segment: String) -> [String] {
		let letters = Array(segment)
		var found: Set<String> = []

		for i in letters.indices {
			for neighbour in PinyinSyllableTable.keyNeighbours[letters[i]] ?? [] {
				var swapped = letters
				swapped[i] = neighbour
				if let key = PinyinSyllableTable.keyForms[String(swapped)] { found.insert(key) }
			}
			var dropped = letters
			dropped.remove(at: i)
			if let key = PinyinSyllableTable.keyForms[String(dropped)] { found.insert(key) }
		}
		for i in letters.indices.dropLast() {
			var transposed = letters
			transposed.swapAt(i, i + 1)
			if let key = PinyinSyllableTable.keyForms[String(transposed)] { found.insert(key) }
		}

		found.remove(PinyinSyllableTable.keyForms[segment] ?? "")
		return Array(found)
	}

	// MARK: - Exact cover

	/// Whether the keys spell complete syllables end to end. When they do, the user has
	/// typed valid pinyin and guesses that invented letters step aside.
	public static func parsesExactly(_ input: PinyinInput) -> Bool {
		let count = input.keys.count
		guard count > 0 else { return false }
		var reachable = [Bool](repeating: false, count: count + 1)
		reachable[0] = true
		for span in PinyinSegmenter.spans(input).sorted(by: { $0.start < $1.start }) where !span.isPartial {
			if reachable[span.start] { reachable[span.start + span.length] = true }
		}
		return reachable[count]
	}
}
