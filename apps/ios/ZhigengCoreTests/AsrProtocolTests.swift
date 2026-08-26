import XCTest
@testable import ZhigengCore

final class AsrProtocolTests: XCTestCase {
	func testParsePartialAndDone() {
		XCTAssertEqual(
			AsrProtocol.parseServerText(#"{"type":"partial","text":"你好"}"#),
			.partial(text: "你好")
		)
		XCTAssertEqual(
			AsrProtocol.parseServerText(#"{"type":"done","fullText":"你好世界","directStructured":true}"#),
			.done(fullText: "你好世界", directStructured: true)
		)
	}

	func testStartPayloadIncludesHotWordsAndToken() throws {
		let data = AsrProtocol.startPayload(authToken: "zk_test", hotWords: ["锦秋", "ARR"])
		let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
		XCTAssertEqual(obj["type"] as? String, "start")
		XCTAssertEqual(obj["authToken"] as? String, "zk_test")
		XCTAssertEqual(obj["hotWords"] as? [String], ["锦秋", "ARR"])
		XCTAssertEqual(obj["mode"] as? String, "structure")
	}

	func testDoneIsInsertable() {
		let state = AsrSessionState()
		state.handle(.partial(text: "半"))
		state.handle(.done(fullText: "完整句子", directStructured: true))
		XCTAssertEqual(state.result?.text, "完整句子")
		XCTAssertEqual(state.result?.isInsertable, true)
	}

	func testTimeoutMarksIncompleteEvenWithPartial() {
		let state = AsrSessionState()
		state.handle(.partial(text: "未完成"))
		state.requestFinish()
		state.handleFinishTimeout()
		XCTAssertEqual(state.result?.incomplete, true)
		XCTAssertEqual(state.result?.isInsertable, false)
		XCTAssertEqual(state.result?.text, "未完成")
	}

	func testUnexpectedCloseAfterFinishIsIncomplete() {
		let state = AsrSessionState()
		state.handle(.partial(text: "断线前"))
		state.requestFinish()
		state.handleUnexpectedClose()
		XCTAssertEqual(state.result?.incomplete, true)
		XCTAssertFalse(state.result?.isInsertable ?? true)
	}
}
