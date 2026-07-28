import XCTest
@testable import ZhigengCore

final class PinyinSegmenterTests: XCTestCase {
	private func syllables(_ spans: [PinyinSpan]) -> Set<String> {
		Set(spans.map(\.syllable))
	}

	private func span(_ spans: [PinyinSpan], start: Int, length: Int) -> PinyinSpan? {
		spans.first { $0.start == start && $0.length == length }
	}

	func testSegmentsUnambiguousInput() {
		let spans = PinyinSegmenter.spans(PinyinInput.full("nihao"))
		XCTAssertEqual(span(spans, start: 0, length: 2)?.syllable, "ni")
		XCTAssertEqual(span(spans, start: 2, length: 3)?.syllable, "hao")
	}

	/// `xian` is either 西安 or 先; the lattice must keep both for the language model to score.
	func testAmbiguousInputKeepsEveryPath() {
		let spans = PinyinSegmenter.spans(PinyinInput.full("xian"))
		XCTAssertEqual(span(spans, start: 0, length: 4)?.syllable, "xian")
		XCTAssertEqual(span(spans, start: 0, length: 2)?.syllable, "xi")
		XCTAssertEqual(span(spans, start: 2, length: 2)?.syllable, "an")
	}

	func testApostropheForcesSyllableBoundary() {
		let spans = PinyinSegmenter.spans(PinyinInput.full("xi'an"))
		XCTAssertNil(span(spans, start: 0, length: 4), "隔音符必须切断 xian 这条路径")
		XCTAssertEqual(span(spans, start: 0, length: 2)?.syllable, "xi")
		XCTAssertEqual(span(spans, start: 2, length: 2)?.syllable, "an")
	}

	func testVIsTypedForUmlautU() {
		XCTAssertEqual(span(PinyinSegmenter.spans(PinyinInput.full("lv")), start: 0, length: 2)?.syllable, "lü")
		XCTAssertEqual(span(PinyinSegmenter.spans(PinyinInput.full("nve")), start: 0, length: 3)?.syllable, "nüe")
	}

	/// While typing, the tail is usually an incomplete syllable; it still needs to drive candidates.
	func testTrailingPrefixIsMarkedPartial() {
		let spans = PinyinSegmenter.spans(PinyinInput.full("nihaom"))
		let tail = span(spans, start: 5, length: 1)
		XCTAssertEqual(tail?.syllable, "m")
		XCTAssertEqual(tail?.isPartial, true)
		XCTAssertEqual(span(spans, start: 0, length: 2)?.isPartial, false)
	}

	func testPartialSpanOnlyAppearsAtTheTail() {
		let spans = PinyinSegmenter.spans(PinyinInput.full("nihao"))
		XCTAssertTrue(spans.filter(\.isPartial).allSatisfy { $0.start + $0.length == 5 })
	}

	func testRejectsImpossibleLetterRuns() {
		XCTAssertTrue(PinyinSegmenter.spans(PinyinInput.full("zzz")).filter { !$0.isPartial }.isEmpty)
	}

	/// Nine-key is the same lattice with a letter *set* per position instead of one letter.
	func testNineKeyExpandsDigitsToLetterSets() {
		// 6 -> mno, 4 -> ghi
		let spans = PinyinSegmenter.spans(PinyinInput.nineKey("64"))
		XCTAssertTrue(syllables(spans).isSuperset(of: ["ni", "mi"]), "得到 \(syllables(spans))")
	}

	func testNineKeyAndFullKeyboardAgreeOnUnambiguousDigits() {
		// 4-4-6-2-6 -> "hao" is not reachable; use 6424 (ni-hao is 6424... ) keep it simple: 42 -> ha/ia/...
		let full = PinyinSegmenter.spans(PinyinInput.full("ni"))
		let nine = PinyinSegmenter.spans(PinyinInput.nineKey("64"))
		XCTAssertTrue(syllables(nine).isSuperset(of: syllables(full)))
	}

	func testEmptyInputProducesNoSpans() {
		XCTAssertTrue(PinyinSegmenter.spans(PinyinInput.full("")).isEmpty)
	}
}
