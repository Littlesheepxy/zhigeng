import XCTest
@testable import ZhigengCore

final class PinyinPersonalBoostTests: XCTestCase {
	func testBoostedWordOutranksHeavierUnboostedHomophone() throws {
		let composer = PinyinComposer(dictionary: try TestDictionary.load())
		let plain = composer.candidates(for: .full("jinqiu"), limit: 8).map(\.text)
		XCTAssertEqual(plain.first, "进球", "corpus baseline: \(plain)")
		XCTAssertTrue(plain.contains("金秋"))

		let boosted = composer.candidates(
			for: .full("jinqiu"),
			limit: 8,
			boosts: ["金秋": 5]
		).map(\.text)
		XCTAssertEqual(boosted.first, "金秋", "boosted ranking: \(boosted)")
	}

	func testUnrelatedBoostDoesNotReorder() throws {
		let composer = PinyinComposer(dictionary: try TestDictionary.load())
		let plain = composer.candidates(for: .full("zhongguo"), limit: 3).map(\.text)
		let boosted = composer.candidates(
			for: .full("zhongguo"),
			limit: 3,
			boosts: ["完全无关": 5]
		).map(\.text)
		XCTAssertEqual(plain, boosted)
	}
}
