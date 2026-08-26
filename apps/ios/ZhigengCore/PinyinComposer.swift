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

/// What a key is to the table: nothing, the start of longer keys, or words in its own
/// right (which are also the start of longer keys).
public enum PinyinLookup: Equatable, Sendable {
	case miss
	case prefix
	case words([PinyinWordEntry])
}

/// Lookup by the letters as typed (no separators, `ü` written `v`). Both the in-memory
/// fixture and the on-disk table answer these questions with one binary search each.
public protocol PinyinDictionary: Sendable {
	func hasPrefix(_ prefix: String) -> Bool
	func entries(for key: String) -> [PinyinWordEntry]
	/// Both questions at once. The relaxed lattice asks them together thousands of times
	/// per keystroke, and answering them separately doubles the searches for no reason.
	func lookup(_ key: String) -> PinyinLookup
	var totalWeight: Int { get }
}

public extension PinyinDictionary {
	var totalWeight: Int { 1_000_000 }

	func lookup(_ key: String) -> PinyinLookup {
		let found = entries(for: key)
		if !found.isEmpty { return .words(found) }
		return hasPrefix(key) ? .prefix : .miss
	}
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

	/// Live spellings kept per position, and a ceiling on dictionary probes for the whole
	/// keystroke. Relaxed matching fans out multiplicatively; these are the CPU guardrails
	/// that keep it inside a keyboard's frame budget, not tuning knobs.
	private static let beam = 32
	private static let probeBudget = 40_000

	public func candidates(
		for input: PinyinInput,
		limit: Int = 12,
		boosts: [String: Int] = [:]
	) -> [PinyinCandidate] {
		let spelledOut = PinyinSpelling.parsesExactly(input)
		let lattice = wordLattice(input, spelledOut: spelledOut)
		guard lattice.contains(where: { !$0.isEmpty }) else { return [] }

		var ordered: [PinyinCandidate] = []
		if let sentence = bestPath(lattice: lattice, boosts: boosts) {
			ordered.append(sentence)
		}
		// Under the whole-sentence pick, the words that start where the cursor is, so the
		// user can commit a prefix and keep going. Personal boosts reorder before length
		// and corpus weight — that is the whole point of teaching the keyboard a word.
		ordered += readingsPerWord(lattice[0])
			.sorted { lhs, rhs in
				let leftBoost = boosts[lhs.text] ?? 0
				let rightBoost = boosts[rhs.text] ?? 0
				if leftBoost != rightBoost { return leftBoost > rightBoost }
				// Keys that spell something complete fill the bar with words the user
				// really typed. Guesses at the same length would otherwise crowd out the
				// shorter exact words they need to build a sentence by hand.
				if spelledOut, (lhs.cost == 0) != (rhs.cost == 0) { return lhs.cost == 0 }
				if lhs.length != rhs.length { return lhs.length > rhs.length }
				let leftScore = lhs.score(wordPenalty), rightScore = rhs.score(wordPenalty)
				if leftScore != rightScore { return leftScore > rightScore }
				return lhs.text < rhs.text
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
		/// How much the reading had to be relaxed to get here; zero when spelled out.
		let cost: Double

		func score(_ wordPenalty: Double) -> Double {
			log(Double(max(weight, 1))) - wordPenalty + cost
		}
	}

	/// Walks the dictionary's keys a syllable at a time rather than a letter at a time,
	/// which is what lets a stub like `h` stand for `hou`. `hasPrefix` is the pruning
	/// oracle: most of the thirty syllables an initial expands into die on the next key.
	private func wordLattice(_ input: PinyinInput, spelledOut: Bool) -> [[Match]] {
		let keys = input.keys
		var lattice: [[Match]] = Array(repeating: [], count: max(keys.count, 0))
		guard !keys.isEmpty else { return lattice }

		let readings = keys.indices.map { PinyinSpelling.readings(input, at: $0) }
		// When the keys already spell something complete, guesses that added letters of
		// their own step behind it. Fuzzy and typo readings are exempt: those are still
		// the letters the user typed, just read differently.
		let demotion = spelledOut ? PinyinSpelling.demoteWhenExact : 0
		var probes = 0

		for start in keys.indices {
			var layers = [[String: Reading]](repeating: [:], count: keys.count + 1)
			layers[start][""] = Reading(cost: 0, invented: false)
			for position in start..<keys.count {
				var layer = layers[position]
				if layer.isEmpty { continue }
				if layer.count > Self.beam {
					let kept = layer.sorted { $0.value.cost > $1.value.cost }.prefix(Self.beam)
					layer = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
				}
				for reading in readings[position] {
					for (prefix, reached) in layer {
						probes += 1
						if probes > Self.probeBudget { return lattice }
						let key = prefix + reading.syllable
						let found = dictionary.lookup(key)
						guard found != .miss else { continue }
						let end = position + reading.length
						let next = Reading(
							cost: reached.cost + reading.cost,
							invented: reached.invented || reading.invented
						)
						if let seen = layers[end][key], seen.cost >= next.cost { continue }
						layers[end][key] = next
						guard case .words(let entries) = found else { continue }
						let cost = next.cost + (next.invented ? demotion : 0)
						for entry in entries {
							lattice[start].append(
								Match(length: end - start, text: entry.text, weight: entry.weight, cost: cost)
							)
						}
					}
				}
			}
		}
		return lattice
	}

	private struct Reading {
		let cost: Double
		let invented: Bool
	}

	/// The same word often turns up read several ways — 中 spelled out in five keys, and
	/// again in six if the sixth is written off as a slip. Committing the wrong one eats
	/// a key that belonged to the next word, so a spelling the user actually typed always
	/// wins; between two guesses, the one that accounts for more keys does.
	private func readingsPerWord(_ matches: [Match]) -> [Match] {
		var best: [String: Match] = [:]
		for match in matches {
			guard let rival = best[match.text] else {
				best[match.text] = match
				continue
			}
			if match.cost == 0, rival.cost < 0 {
				best[match.text] = match
			} else if (match.cost == 0) == (rival.cost == 0), match.length > rival.length {
				best[match.text] = match
			}
		}
		return Array(best.values)
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
				let value = reached + match.score(wordPenalty) + personal
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
