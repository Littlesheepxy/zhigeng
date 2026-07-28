import XCTest
@testable import ZhigengCore

/// Keys are the letters as typed (no separators, `ü` written `v`) — the same shape the
/// on-disk dictionary uses, so the composer is exercised exactly as it runs on device.
private struct FixtureDictionary: PinyinDictionary {
	private let byKey: [String: [PinyinWordEntry]]
	private let allPrefixes: Set<String>

	init(_ pairs: [(String, String, Int)]) {
		var grouped: [String: [PinyinWordEntry]] = [:]
		var prefixes: Set<String> = []
		for (key, text, weight) in pairs {
			grouped[key, default: []].append(PinyinWordEntry(text: text, weight: weight))
			var prefix = ""
			for letter in key {
				prefix.append(letter)
				prefixes.insert(prefix)
			}
		}
		byKey = grouped.mapValues { $0.sorted { $0.weight > $1.weight } }
		allPrefixes = prefixes
	}

	func hasPrefix(_ prefix: String) -> Bool { allPrefixes.contains(prefix) }
	func entries(for key: String) -> [PinyinWordEntry] { byKey[key] ?? [] }
}

final class PinyinComposerTests: XCTestCase {
	private let dictionary = FixtureDictionary([
		("wo", "我", 9000), ("wo", "窝", 300),
		("shi", "是", 9500), ("shi", "时", 4000), ("shi", "事", 2000),
		("zhong", "中", 5000), ("zhong", "种", 2000),
		("guo", "国", 4000), ("guo", "过", 3500),
		("ren", "人", 6000),
		("zhongguo", "中国", 8000),
		("guoren", "国人", 400),
		("zhongguoren", "中国人", 1200),
		("shizhong", "时钟", 900),
		("xian", "先", 3000), ("xian", "现", 2800),
		("zai", "在", 7000),
		("xianzai", "现在", 9000),
		("xi", "西", 2000),
		("an", "安", 1500),
		("anzai", "安在", 5),
	])

	private func best(_ text: String) -> String? {
		PinyinComposer(dictionary: dictionary).candidates(for: .full(text), limit: 8).first?.text
	}

	func testComposesWholeSentence() {
		XCTAssertEqual(best("woshizhongguoren"), "我是中国人")
	}

	/// 现在 must beat the 西安在 segmentation even though 西/安/在 are all common on their own.
	func testPrefersHigherScoringSegmentation() {
		XCTAssertEqual(best("xianzai"), "现在")
	}

	func testPrefersMultiCharacterWordOverCharacterByCharacter() {
		XCTAssertEqual(best("shizhong"), "时钟")
	}

	/// Below the whole-sentence pick, the user needs shorter words to build a sentence by hand.
	func testOffersShorterPrefixCandidates() {
		let candidates = PinyinComposer(dictionary: dictionary).candidates(for: .full("zhongguo"), limit: 10)
		XCTAssertEqual(candidates.first?.text, "中国")
		XCTAssertTrue(candidates.contains { $0.text == "中" && $0.length == 5 }, "得到 \(candidates)")
	}

	func testCandidatesAreDeduplicated() {
		let candidates = PinyinComposer(dictionary: dictionary).candidates(for: .full("zhongguo"), limit: 10)
		XCTAssertEqual(Set(candidates.map(\.text)).count, candidates.count)
	}

	func testNineKeyReachesTheSameSentence() {
		let composer = PinyinComposer(dictionary: dictionary)
		// wo=96 shi=744 zhong=94664 guo=486 ren=736
		let nine = composer.candidates(for: .nineKey("9674494664486736"), limit: 20)
		XCTAssertTrue(nine.contains { $0.text == "我是中国人" }, "得到 \(nine.prefix(5).map(\.text))")
	}

	func testUnknownInputDoesNotCrashAndYieldsNothing() {
		XCTAssertTrue(PinyinComposer(dictionary: dictionary).candidates(for: .full("qqqq"), limit: 5).isEmpty)
	}

	func testEmptyInputYieldsNothing() {
		XCTAssertTrue(PinyinComposer(dictionary: dictionary).candidates(for: .full(""), limit: 5).isEmpty)
	}
}
