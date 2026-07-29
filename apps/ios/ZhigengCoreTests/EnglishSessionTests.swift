import XCTest
import ZhigengCore

final class EnglishSessionTests: XCTestCase {
	private var session: EnglishSession!
	private var dictionary: EnglishFileDictionary!

	override func setUpWithError() throws {
		dictionary = try TestDictionary.loadEnglish()
		session = EnglishSession(dictionary: dictionary)
	}

	func testCompletionsRankCommonWordsFirst() {
		let words = dictionary.completions(prefix: "th", limit: 5)
		XCTAssertTrue(words.contains("the"))
		XCTAssertEqual(words.first, "the")
	}

	func testExactMatchStaysFirstWhenFullyTyped() {
		let words = dictionary.completions(prefix: "the", limit: 5)
		XCTAssertEqual(words.first, "the")
	}

	func testNextWordAfterThank() {
		let words = dictionary.nextWords(after: "thank", limit: 5)
		XCTAssertTrue(words.contains("you"), "got \(words)")
	}

	func testSessionCommitAdvancesPrediction() {
		for ch in "thank" { session.append(ch) }
		XCTAssertEqual(session.commit("thank").trimmingCharacters(in: .whitespaces), "thank")
		XCTAssertFalse(session.isComposing)
		XCTAssertTrue(session.candidates().contains("you"))
	}

	func testCommitTypedKeepsUserSpelling() {
		for ch in "teh" { session.append(ch) }
		XCTAssertEqual(session.commitTyped(), "teh ")
		XCTAssertEqual(session.previousWord, "teh")
	}

	func testBackspaceReturnsFalseWhenEmpty() {
		XCTAssertFalse(session.backspace())
		session.append("a")
		XCTAssertTrue(session.backspace())
		XCTAssertFalse(session.isComposing)
	}
}
