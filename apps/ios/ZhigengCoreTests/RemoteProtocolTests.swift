import XCTest
@testable import ZhigengCore

final class RemoteProtocolTests: XCTestCase {
	func testParsesPairingURL() throws {
		let url = try XCTUnwrap(
			URL(string: "zhigeng://pair?pid=pair_123&c=123456&api=http%3A%2F%2F192.168.1.8%3A3010")
		)
		let payload = try RemotePairingPayload(url: url)
		XCTAssertEqual(payload.pairingId, "pair_123")
		XCTAssertEqual(payload.code, "123456")
		XCTAssertEqual(payload.apiBase.absoluteString, "http://192.168.1.8:3010")
	}

	func testRejectsMalformedPairingURL() {
		XCTAssertThrowsError(
			try RemotePairingPayload(
				url: XCTUnwrap(URL(string: "https://example.com/pair?pid=x&c=123456"))
			)
		)
		XCTAssertThrowsError(
			try RemotePairingPayload(
				url: XCTUnwrap(URL(string: "zhigeng://pair?pid=x&c=12&api=http://localhost:3010"))
			)
		)
	}

	func testTurnStateAppliesRelayEvents() {
		var turn = RemoteTurnState(id: "turn-1", threadId: "thread-1", content: "整理桌面")
		turn.apply(status: "running", state: .object([
			"status": .string("working"),
			"result": .string("正在读取文件"),
		]))
		XCTAssertEqual(turn.status, .running)
		XCTAssertEqual(turn.headline, "正在读取文件")

		turn.apply(status: "completed", state: .object([
			"status": .string("done"),
			"result": .string("整理完成"),
		]))
		XCTAssertEqual(turn.status, .completed)
		XCTAssertEqual(turn.headline, "整理完成")
	}
}
