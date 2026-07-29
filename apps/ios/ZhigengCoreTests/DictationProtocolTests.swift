import XCTest
@testable import ZhigengCore

final class DictationProtocolTests: XCTestCase {
	private var tempDir: URL!
	private var bridge: AppGroupBridge!

	override func setUpWithError() throws {
		tempDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("zg-proto-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
		bridge = AppGroupBridge(containerOverride: tempDir)
	}

	override func tearDownWithError() throws {
		try? FileManager.default.removeItem(at: tempDir)
	}

	func testChineseLayoutControlsVoiceDeletePlacement() {
		XCTAssertEqual(ChineseKeyboardLayout.nineKey.voiceDeletePlacement, .topTrailing)
		XCTAssertEqual(ChineseKeyboardLayout.fullKeyboard.voiceDeletePlacement, .aboveSend)
	}

	func testCommandRoundTripAndConsumeOnce() throws {
		let command = DictationCommand(kind: .start, requestId: "r1")
		try bridge.writeCommand(command)
		let first = try bridge.consumeCommand()
		XCTAssertEqual(first?.kind, .start)
		XCTAssertEqual(first?.requestId, "r1")
		XCTAssertNil(try bridge.consumeCommand())
	}

	func testSessionAliveRequiresHeartbeatAndDeadline() throws {
		let now: TimeInterval = 1_000
		let alive = DictationSession(
			activeUntil: now + 60,
			state: .idle,
			mode: .pip,
			heartbeatAt: now - 2
		)
		XCTAssertTrue(alive.isServiceAlive(now: now))

		let staleHeartbeat = DictationSession(
			activeUntil: now + 60,
			state: .idle,
			mode: .pip,
			heartbeatAt: now - 30
		)
		XCTAssertFalse(staleHeartbeat.isServiceAlive(now: now))

		let expired = DictationSession(
			activeUntil: now - 1,
			state: .idle,
			mode: .liveActivity,
			heartbeatAt: now
		)
		XCTAssertFalse(expired.isServiceAlive(now: now))
	}

	func testPartialResultUsesRevisionAndIsNotInsertable() throws {
		let partial = DictationResult(
			requestId: "r1",
			status: .recording,
			text: "半",
			revision: 3
		)
		XCTAssertFalse(partial.isInsertable)
		XCTAssertEqual(partial.revision, 3)

		try bridge.writeResult(partial)
		XCTAssertNil(try bridge.consumeInsertableResult(matching: "r1"))
		XCTAssertEqual(try bridge.readResult()?.revision, 3)
	}

	func testFinalResultRoundTripsVoiceSegments() throws {
		let word = VoiceWord(
			text: "知更",
			startTimeMs: 120,
			endTimeMs: 480,
			confidence: 0.92
		)
		let segment = VoiceSegment(
			text: "知更。",
			startTimeMs: 120,
			endTimeMs: 520,
			definite: true,
			words: [word]
		)
		let result = DictationResult(
			requestId: "r1",
			status: .ready,
			text: "知更。",
			segments: [segment],
			revision: 4
		)

		try bridge.writeResult(result)

		XCTAssertEqual(try bridge.readResult()?.segments, [segment])
	}

	func testLegacyResultWithoutSegmentsDecodesWithEmptySegments() throws {
		let json = """
		{
		  "requestId": "legacy",
		  "status": "ready",
		  "text": "旧结果",
		  "directStructured": false,
		  "ts": 1000,
		  "revision": 1
		}
		"""

		let result = try JSONDecoder().decode(DictationResult.self, from: Data(json.utf8))

		XCTAssertEqual(result.segments, [])
	}

	func testVolcPayloadParserKeepsUtterancesAndWords() throws {
		let payload = """
		{
		  "result": {
		    "text": "喂，董老板。",
		    "utterances": [{
		      "definite": true,
		      "start_time": 770,
		      "end_time": 1930,
		      "text": "喂，董老板。",
		      "words": [{
		        "text": "董",
		        "start_time": 1530,
		        "end_time": 1570,
		        "confidence": 0.86
		      }]
		    }]
		  }
		}
		"""

		let result = try XCTUnwrap(VolcAsrPayloadParser.parse(payload))

		XCTAssertEqual(result.text, "喂，董老板。")
		XCTAssertEqual(result.segments.first?.definite, true)
		XCTAssertEqual(result.segments.first?.words.first?.text, "董")
		XCTAssertEqual(result.segments.first?.words.first?.confidence, 0.86)
	}

	func testConsumeNewerRevisionOnly() throws {
		try bridge.writeResult(
			DictationResult(requestId: "r1", status: .recording, text: "一", revision: 1)
		)
		XCTAssertEqual(try bridge.readResultIfNewer(than: 0)?.revision, 1)
		XCTAssertNil(try bridge.readResultIfNewer(than: 1))

		try bridge.writeResult(
			DictationResult(requestId: "r1", status: .recording, text: "一二", revision: 2)
		)
		XCTAssertEqual(try bridge.readResultIfNewer(than: 1)?.text, "一二")
	}
}
