import Foundation

/// Extract short contiguous replacements from an edit (detail-page / keyboard correction).
/// Only learns when the changed span is short enough to be a term, not a rewrite.
public enum TextEditDiff {
	public static let maxTermLength = 12
	private static let namePrefix: Set<Character> = ["小", "老", "大", "阿"]

	public static func replacements(original: String, edited: String) -> [(String, String)] {
		let oChars = Array(original)
		let eChars = Array(edited)
		guard oChars != eChars else { return [] }

		var prefix = 0
		while prefix < oChars.count, prefix < eChars.count, oChars[prefix] == eChars[prefix] {
			prefix += 1
		}
		var oEnd = oChars.count
		var eEnd = eChars.count
		while oEnd > prefix, eEnd > prefix, oChars[oEnd - 1] == eChars[eEnd - 1] {
			oEnd -= 1
			eEnd -= 1
		}

		// Expand left for common Chinese name prefixes or Latin letters.
		// Expand right only for Latin/digit runs (e.g. AR → ARR).
		while prefix > 0 {
			let ch = oChars[prefix - 1]
			let nextFromLen = oEnd - (prefix - 1)
			let nextToLen = eEnd - (prefix - 1)
			guard nextFromLen <= maxTermLength, nextToLen <= maxTermLength else { break }
			if namePrefix.contains(ch) || isLatinLetter(ch) {
				prefix -= 1
			} else {
				break
			}
		}
		while oEnd < oChars.count, eEnd < eChars.count {
			let ch = oChars[oEnd]
			guard isLatinLetter(ch) || ch.isNumber else { break }
			let nextFromLen = oEnd + 1 - prefix
			let nextToLen = eEnd + 1 - prefix
			guard nextFromLen <= maxTermLength, nextToLen <= maxTermLength else { break }
			oEnd += 1
			eEnd += 1
		}

		let from = String(oChars[prefix..<oEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
		let to = String(eChars[prefix..<eEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
		guard !to.isEmpty, from != to else { return [] }
		guard to.count <= maxTermLength, from.count <= maxTermLength else { return [] }
		return [(from, to)]
	}

	private static func isLatinLetter(_ c: Character) -> Bool {
		c.isASCII && c.isLetter
	}
}
