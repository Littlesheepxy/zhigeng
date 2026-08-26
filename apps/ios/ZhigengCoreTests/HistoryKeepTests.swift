import XCTest
@testable import ZhigengCore

final class HistoryKeepTests: XCTestCase {
	func testLegacyJSONWithoutKeptAtDecodesAsNil() throws {
		let legacy = """
		[{"id":"1","createdAt":1,"source":"main","status":"ready","cleanedText":"hi","directStructured":false,"processingTags":[]}]
		""".data(using: .utf8)!
		let items = try JSONDecoder().decode([DictationHistoryItem].self, from: legacy)
		XCTAssertNil(items.first?.keptAt)
		XCTAssertFalse(items.first?.isKept ?? true)
	}

	func testPruneDropsUnkeptOlderThanRetention() {
		let now: TimeInterval = 1_000_000
		let day: TimeInterval = 86_400
		let keptOld = DictationHistoryItem(
			id: "kept",
			createdAt: now - 40 * day,
			source: .main,
			status: .ready,
			cleanedText: "keep me",
			keptAt: now - 39 * day
		)
		let unkeptOld = DictationHistoryItem(
			id: "drop",
			createdAt: now - 31 * day,
			source: .main,
			status: .ready,
			cleanedText: "drop me"
		)
		let unkeptFresh = DictationHistoryItem(
			id: "fresh",
			createdAt: now - 10 * day,
			source: .keyboard,
			status: .ready,
			cleanedText: "still here"
		)
		let pruned = DictationHistoryItem.prune([keptOld, unkeptOld, unkeptFresh], now: now)
		XCTAssertEqual(pruned.map(\.id), ["kept", "fresh"])
	}

	func testKeptAtRoundTrips() throws {
		var item = DictationHistoryItem(
			source: .main,
			status: .ready,
			cleanedText: "note",
			keptAt: 42
		)
		XCTAssertTrue(item.isKept)
		let data = try JSONEncoder().encode(item)
		item = try JSONDecoder().decode(DictationHistoryItem.self, from: data)
		XCTAssertEqual(item.keptAt, 42)
	}
}
