import Foundation

public struct PinyinWordEntry: Equatable, Sendable {
	public let text: String
	/// Raw corpus frequency; the composer turns it into a log probability.
	public let weight: Int

	public init(text: String, weight: Int) {
		self.text = text
		self.weight = weight
	}
}

/// Lookup by the letters as typed (no separators, `ü` written `v`). Both the in-memory
/// fixture and the on-disk table answer these two questions with one binary search each.
public protocol PinyinDictionary: Sendable {
	func hasPrefix(_ prefix: String) -> Bool
	func entries(for key: String) -> [PinyinWordEntry]
	var totalWeight: Int { get }
}

public extension PinyinDictionary {
	var totalWeight: Int { 1_000_000 }
}

public struct PinyinCandidate: Equatable, Sendable {
	public let text: String
	/// How many keys this candidate consumes, so the caller knows what is left to type.
	public let length: Int

	public init(text: String, length: Int) {
		self.text = text
		self.length = length
	}
}

public struct PinyinComposer {
	private let dictionary: PinyinDictionary
	/// `log Z` from `P(word) = weight / Z`. Because every word contributes one of these,
	/// it is also exactly the penalty that stops the path from splintering into single characters.
	private let wordPenalty: Double

	public init(dictionary: PinyinDictionary) {
		self.dictionary = dictionary
		wordPenalty = log(Double(max(dictionary.totalWeight, 2)))
	}

	public func candidates(
		for input: PinyinInput,
		limit: Int = 12,
		boosts: [String: Int] = [:]
	) -> [PinyinCandidate] {
		let lattice = wordLattice(input)
		guard lattice.contains(where: { !$0.isEmpty }) else { return [] }

		var ordered: [PinyinCandidate] = []
		if let sentence = bestPath(lattice: lattice, boosts: boosts) {
			ordered.append(sentence)
		}
		// Under the whole-sentence pick, the words that start where the cursor is, so the
		// user can commit a prefix and keep going. Personal boosts reorder before length
		// and corpus weight — that is the whole point of teaching the keyboard a word.
		ordered += lattice[0]
			.sorted { lhs, rhs in
				let leftBoost = boosts[lhs.text] ?? 0
				let rightBoost = boosts[rhs.text] ?? 0
				if leftBoost != rightBoost { return leftBoost > rightBoost }
				if lhs.length != rhs.length { return lhs.length > rhs.length }
				return lhs.weight > rhs.weight
			}
			.map { PinyinCandidate(text: $0.text, length: $0.length) }

		var seen: Set<String> = []
		return Array(ordered.filter { seen.insert($0.text).inserted }.prefix(limit))
	}

	// MARK: - Lattice

	private struct Match {
		let length: Int
		let text: String
		let weight: Int
	}

	/// Same frontier walk as the syllable segmenter, but over the dictionary's keys, so a
	/// nine-key press standing for three letters costs nothing extra.
	private func wordLattice(_ input: PinyinInput) -> [[Match]] {
		let keys = input.keys
		var lattice: [[Match]] = Array(repeating: [], count: max(keys.count, 0))
		guard !keys.isEmpty else { return lattice }

		for start in keys.indices {
			var frontier: Set<String> = [""]
			var index = start
			while index < keys.count {
				if index > start, input.boundaries.contains(index) { break }
				var next: Set<String> = []
				for prefix in frontier {
					for letter in keys[index] {
						let candidate = prefix + String(letter)
						if dictionary.hasPrefix(candidate) {
							next.insert(candidate)
						}
					}
				}
				if next.isEmpty { break }
				frontier = next
				index += 1
				for key in frontier {
					for entry in dictionary.entries(for: key) {
						lattice[start].append(Match(length: index - start, text: entry.text, weight: entry.weight))
					}
				}
			}
		}
		return lattice
	}

	// MARK: - Viterbi

	private func bestPath(lattice: [[Match]], boosts: [String: Int]) -> PinyinCandidate? {
		let count = lattice.count
		var score = [Double?](repeating: nil, count: count + 1)
		var back = [(from: Int, text: String)?](repeating: nil, count: count + 1)
		score[0] = 0

		for start in 0..<count {
			guard let reached = score[start] else { continue }
			for match in lattice[start] {
				let end = start + match.length
				// Personal boost is added in log-space. Level 5 ≈ e^10 ≈ 22k× on the
				// linear weight, enough to lift a mid-corpus word over a heavier rival
				// without inventing matches that are not in the table.
				let personal = Double(boosts[match.text] ?? 0) * 2.0
				let value = reached + log(Double(max(match.weight, 1))) - wordPenalty + personal
				if score[end] == nil || value > score[end]! {
					score[end] = value
					back[end] = (from: start, text: match.text)
				}
			}
		}

		// Prefer the path that covers the most keys; the tail is usually still being typed.
		guard let end = (1...count).reversed().first(where: { score[$0] != nil }) else { return nil }

		var text = ""
		var cursor = end
		while cursor > 0, let step = back[cursor] {
			text = step.text + text
			cursor = step.from
		}
		guard !text.isEmpty else { return nil }
		return PinyinCandidate(text: text, length: end)
	}
}
