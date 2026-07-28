import XCTest
@testable import ZhigengCore

/// The composing buffer, exercised against the table that actually ships.
final class PinyinSessionTests: XCTestCase {
	private var session: PinyinSession!

	override func setUpWithError() throws {
		session = PinyinSession(dictionary: try TestDictionary.load())
	}

	private func type(_ text: String) {
		for character in text { session.append(character) }
	}

	func testStartsIdle() {
		XCTAssertFalse(session.isComposing)
		XCTAssertTrue(session.candidates().isEmpty)
	}

	func testTypingStartsComposing() {
		type("nihao")
		XCTAssertTrue(session.isComposing)
		XCTAssertEqual(session.candidates().first?.text, "你好")
	}

	/// The code line is what tells the user how their letters were split.
	func testDisplaySeparatesSyllables() {
		type("nihao")
		XCTAssertEqual(session.display, "ni'hao")
	}

	func testCommittingTheWholeBufferClearsIt() {
		type("nihao")
		let candidate = try! XCTUnwrap(session.candidates().first)
		XCTAssertEqual(session.commit(candidate), "你好")
		XCTAssertFalse(session.isComposing)
		XCTAssertEqual(session.display, "")
	}

	/// Picking a word that covers only part of what was typed has to leave the rest
	/// in the buffer, otherwise the user silently loses keys.
	func testCommittingAPrefixKeepsTheRest() {
		type("nihaoma")
		let short = try! XCTUnwrap(session.candidates().first { $0.text == "你好" })
		XCTAssertEqual(session.commit(short), "你好")
		XCTAssertTrue(session.isComposing)
		XCTAssertEqual(session.display, "ma")
	}

	func testBackspaceDropsOneKeyAndReportsHandled() {
		type("nihao")
		XCTAssertTrue(session.backspace())
		XCTAssertEqual(session.display, "ni'ha")
	}

	/// When nothing is being composed the keyboard must delete document text instead.
	func testBackspaceReportsUnhandledWhenIdle() {
		XCTAssertFalse(session.backspace())
	}

	func testClearDropsTheBuffer() {
		type("nihao")
		session.clear()
		XCTAssertFalse(session.isComposing)
	}

	func testNineKeyReachesTheSameWord() {
		session.nineKey = true
		type("64426") // n i h a o
		XCTAssertEqual(session.candidates().first?.text, "你好")
	}

	/// Nine-key users still need to see letters, not the digits they pressed.
	func testNineKeyDisplayShowsLetters() {
		session.nineKey = true
		type("64426")
		XCTAssertEqual(session.display, "ni'hao")
	}

	func testSwitchingLayoutDropsAmbiguousBuffer() {
		type("nihao")
		session.nineKey = true
		XCTAssertFalse(session.isComposing)
	}
}
