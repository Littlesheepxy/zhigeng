import XCTest
@testable import ZhigengCore

final class SpeechCorrectionTests: XCTestCase {
	func testSamePinyinCandidatesAreRankedByWeight() throws {
		let state = SpeechCorrectionState.build(
			requestId: "r1",
			text: "明天找账期确认",
			lexicon: [
				SpeechLexiconTerm(text: "张琪", weight: 8),
				SpeechLexiconTerm(text: "章琦", weight: 3),
				SpeechLexiconTerm(text: "无关", weight: 99),
			]
		)

		let span = try XCTUnwrap(state.spans.first(where: { $0.text == "账期" }))
		XCTAssertEqual(span.candidates.map(\.text), ["张琪", "章琦"])
	}

	func testReplacementRequiresCurrentSentenceAtCursor() throws {
		let state = SpeechCorrectionState.build(
			requestId: "r1",
			text: "联系账期",
			lexicon: [SpeechLexiconTerm(text: "张琪", weight: 4)]
		)
		let span = try XCTUnwrap(state.spans.first)

		XCTAssertNil(
			state.replacement(
				spanID: span.id,
				with: "张琪",
				contextBefore: "宿主内容已经变化"
			)
		)

		let replacement = try XCTUnwrap(
			state.replacement(
				spanID: span.id,
				with: "张琪",
				contextBefore: "前文联系账期"
			)
		)
		XCTAssertEqual(replacement.deleteCount, 4)
		XCTAssertEqual(replacement.insert, "联系张琪")
		XCTAssertEqual(replacement.original, "账期")
		XCTAssertEqual(replacement.replacement, "张琪")
	}

	func testCursorOffsetTargetsSelectedSpanEnd() throws {
		let state = SpeechCorrectionState.build(
			requestId: "r1",
			text: "联系账期以后回复",
			lexicon: [SpeechLexiconTerm(text: "张琪", weight: 4)]
		)
		let span = try XCTUnwrap(state.spans.first)

		XCTAssertEqual(state.cursorOffsetAfterSpan(span.id, contextBefore: "联系账期以后回复"), -4)
		XCTAssertNil(state.cursorOffsetAfterSpan(span.id, contextBefore: "不匹配"))
	}

	func testCursorOffsetsUseUTF16UnitsForEmoji() throws {
		let state = SpeechCorrectionState.build(
			requestId: "r1",
			text: "账期👨‍👩‍👧‍👦",
			lexicon: [SpeechLexiconTerm(text: "张琪", weight: 4)]
		)
		let span = try XCTUnwrap(state.spans.first)

		XCTAssertEqual(state.cursorOffsetAfterSpan(span.id, contextBefore: state.text), -11)
		XCTAssertEqual(
			CursorNavigation.horizontalOffset(
				steps: -1,
				contextBefore: "前👨‍👩‍👧‍👦",
				contextAfter: ""
			),
			-11
		)
		XCTAssertEqual(
			CursorNavigation.horizontalOffset(
				steps: 1,
				contextBefore: "",
				contextAfter: "👨‍👩‍👧‍👦后"
			),
			11
		)
	}

	func testCorrectionAnchorRejectsSameSentenceAtAnotherLocation() {
		let anchor = SpeechCorrectionAnchor.capture(
			insertedText: "重复句",
			contextBefore: "甲方前文重复句",
			contextAfter: "甲方后文"
		)

		XCTAssertTrue(
			anchor.matches(
				insertedText: "重复句",
				contextBefore: "甲方前文重复句",
				contextAfter: "甲方后文"
			)
		)
		XCTAssertFalse(
			anchor.matches(
				insertedText: "重复句",
				contextBefore: "乙方前文重复句",
				contextAfter: "乙方后文"
			)
		)
	}

	func testCandidateReplacementPreservesAdjacentPunctuation() throws {
		let state = SpeechCorrectionState.build(
			requestId: "r1",
			text: "联系账期,稍后回复。",
			lexicon: [SpeechLexiconTerm(text: "张琪", weight: 4)]
		)
		let span = try XCTUnwrap(state.spans.first)
		let replacement = try XCTUnwrap(
			state.replacement(
				spanID: span.id,
				with: "张琪",
				contextBefore: state.text
			)
		)

		XCTAssertEqual(span.text, "账期")
		XCTAssertEqual(replacement.insert, "联系张琪,稍后回复。")
	}

	func testVerticalCursorUsesExplicitLinesThenFallsBackToCoarseSteps() {
		XCTAssertEqual(
			CursorNavigation.verticalOffset(
				direction: .up,
				contextBefore: "第一行\n第二",
				contextAfter: "行",
				approximateLineLength: 6
			),
			-4
		)
		XCTAssertEqual(
			CursorNavigation.verticalOffset(
				direction: .down,
				contextBefore: "第一",
				contextAfter: "行\n第二行",
				approximateLineLength: 6
			),
			4
		)
		XCTAssertEqual(
			CursorNavigation.verticalOffset(
				direction: .up,
				contextBefore: "这是一段自动换行文字",
				contextAfter: "",
				approximateLineLength: 6
			),
			-6
		)
	}
}
