import Foundation

/// Composing buffer for English: the unfinished word, the last committed word (for
/// next-word prediction), and the candidate list the bar should show.
public struct EnglishSession {
	private let dictionary: EnglishFileDictionary

	public private(set) var typed = ""
	public private(set) var previousWord = ""

	public init(dictionary: EnglishFileDictionary) {
		self.dictionary = dictionary
	}

	public var isComposing: Bool { !typed.isEmpty }

	/// Completions while typing; next-word suggestions once the buffer is empty and we
	/// know what came before. Empty when neither applies.
	public func candidates(limit: Int = 8) -> [String] {
		if isComposing {
			return dictionary.completions(prefix: typed, limit: limit)
		}
		if !previousWord.isEmpty {
			return dictionary.nextWords(after: previousWord, limit: limit)
		}
		return []
	}

	public mutating func append(_ character: Character) {
		guard character.isASCII, character.isLetter else { return }
		typed.append(Character(character.lowercased()))
	}

	/// `false` when the buffer was already empty — caller should delete in the document.
	public mutating func backspace() -> Bool {
		guard isComposing else { return false }
		typed.removeLast()
		return true
	}

	/// Commit a bar suggestion. While composing it replaces the typed prefix; otherwise
	/// it is a next-word pick. Always leaves a trailing space so the next prediction is ready.
	public mutating func commit(_ word: String) -> String {
		typed = ""
		previousWord = word.lowercased()
		return word + " "
	}

	/// Space / return path: keep what the user typed (no silent autocorrect) and advance
	/// the prediction context. Empty buffer just inserts a space.
	public mutating func commitTyped() -> String {
		guard isComposing else { return " " }
		let word = typed
		typed = ""
		previousWord = word
		return word + " "
	}

	public mutating func clear() {
		typed = ""
	}

	/// Seed prediction from document context when the user did not type the previous
	/// word through this keyboard (cursor move, paste, app switch).
	public mutating func setPreviousWord(_ word: String) {
		let cleaned = word.lowercased().filter(\.isLetter)
		previousWord = cleaned
	}
}
