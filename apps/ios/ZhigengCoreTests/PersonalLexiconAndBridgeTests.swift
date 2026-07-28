import XCTest
@testable import ZhigengCore

final class PersonalLexiconTests: XCTestCase {
	func testRecordCorrectionWithinWindowLearnsReplacement() {
		let lexicon = PersonalLexicon(now: { 1_000 })
		let term = lexicon.recordCorrection(
			original: "金秋",
			replacement: "锦秋",
			requestId: "r1",
			insertedAt: 990,
			at: 1_000
		)
		XCTAssertEqual(term?.text, "锦秋")
		XCTAssertEqual(lexicon.asrHotWords(), ["锦秋"])
		XCTAssertEqual(lexicon.rimeBoosts().first?.weight, 2)
	}

	func testRecordCorrectionOutsideWindowIsIgnored() {
		let lexicon = PersonalLexicon(now: { 1_000 })
		let term = lexicon.recordCorrection(
			original: "金秋",
			replacement: "锦秋",
			requestId: "r1",
			insertedAt: 900,
			at: 1_000
		)
		XCTAssertNil(term)
		XCTAssertTrue(lexicon.asrHotWords().isEmpty)
	}

	func testIdenticalReplacementIsIgnored() {
		let lexicon = PersonalLexicon()
		XCTAssertNil(
			lexicon.recordCorrection(
				original: "知更",
				replacement: "知更",
				requestId: "r1",
				insertedAt: Date().timeIntervalSince1970
			)
		)
	}

	func testRepeatedCorrectionIncreasesWeight() {
		var t: TimeInterval = 1_000
		let lexicon = PersonalLexicon(now: { t })
		_ = lexicon.recordCorrection(original: "a", replacement: "ARR", requestId: "1", insertedAt: 990, at: 1_000)
		t = 1_010
		_ = lexicon.recordCorrection(original: "a", replacement: "ARR", requestId: "2", insertedAt: 1_005, at: 1_010)
		XCTAssertEqual(lexicon.rimeBoosts().first?.weight, 3)
	}

	func testForgetRemovesTerm() {
		let lexicon = PersonalLexicon()
		let term = lexicon.addManual("InputSurface")!
		lexicon.forget(id: term.id)
		XCTAssertTrue(lexicon.asrHotWords().isEmpty)
	}

	func testRecordUseAddsAndReinforces() {
		let lexicon = PersonalLexicon()
		XCTAssertEqual(lexicon.recordUse("锦秋")?.weight, 2)
		XCTAssertEqual(lexicon.recordUse("锦秋")?.weight, 3)
		XCTAssertEqual(lexicon.asrHotWords(), ["锦秋"])
	}

	func testRecordUseIgnoresBlank() {
		XCTAssertNil(PersonalLexicon().recordUse("  "))
	}
}

final class AppGroupBridgeTests: XCTestCase {
	private var tempDir: URL!
	private var bridge: AppGroupBridge!

	override func setUpWithError() throws {
		tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("zg-appgroup-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
		bridge = AppGroupBridge(containerOverride: tempDir)
	}

	override func tearDownWithError() throws {
		try? FileManager.default.removeItem(at: tempDir)
	}

	func testRequestRoundTrip() throws {
		let request = DictationRequest(requestId: "abc", source: "keyboard")
		try bridge.writeRequest(request)
		let loaded = try bridge.readRequest()
		XCTAssertEqual(loaded?.requestId, "abc")
	}

	func testConsumeInsertableResultRequiresMatchingRequestId() throws {
		try bridge.writeResult(
			DictationResult(requestId: "a", status: .ready, text: "你好")
		)
		XCTAssertNil(try bridge.consumeInsertableResult(matching: "b"))
		let consumed = try bridge.consumeInsertableResult(matching: "a")
		XCTAssertEqual(consumed?.text, "你好")
		XCTAssertNil(try bridge.readResult())
	}

	func testIncompleteResultIsNotInsertable() throws {
		try bridge.writeResult(
			DictationResult(requestId: "a", status: .incomplete, text: "半截")
		)
		XCTAssertNil(try bridge.consumeInsertableResult(matching: "a"))
		XCTAssertEqual(try bridge.readResult()?.status, .incomplete)
	}

	func testDictationResultReadyRequiresNonEmptyText() {
		XCTAssertFalse(DictationResult(requestId: "a", status: .ready, text: "  ").isInsertable)
		XCTAssertTrue(DictationResult(requestId: "a", status: .ready, text: "ok").isInsertable)
	}
}

final class PersonalTermKindTests: XCTestCase {
	func testLegacyJSONWithoutKindDecodesAsWord() throws {
		let legacy = """
		[{"id":"1","text":"ARR","source":"manual","weight":3,"lastUsedAt":1,"createdAt":1}]
		""".data(using: .utf8)!
		let lexicon = try PersonalLexicon.decode(from: legacy)
		XCTAssertEqual(lexicon.allTerms.first?.kind, .word)
	}

	func testKindRoundTripsAndManualAddSupportsKind() throws {
		let lexicon = PersonalLexicon()
		_ = lexicon.addManual("小杨", kind: .person)
		let data = try lexicon.encode()
		let reloaded = try PersonalLexicon.decode(from: data)
		XCTAssertEqual(reloaded.allTerms.first?.kind, .person)
	}

	func testSetKindReclassifiesTerm() throws {
		let lexicon = PersonalLexicon()
		let term = try XCTUnwrap(lexicon.addManual("季度报告"))
		lexicon.setKind(id: term.id, kind: .project)
		XCTAssertEqual(lexicon.allTerms.first?.kind, .project)
	}
}
