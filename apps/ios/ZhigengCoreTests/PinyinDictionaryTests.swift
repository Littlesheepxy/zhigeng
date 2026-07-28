import XCTest
@testable import ZhigengCore

/// Quality gate for the shipped table. These are the sentences a user actually types;
/// if a change to the ranking breaks one of them, it broke the keyboard.
final class PinyinDictionaryTests: XCTestCase {
	private var dictionary: PinyinFileDictionary!
	private var composer: PinyinComposer!

	override func setUpWithError() throws {
		dictionary = try TestDictionary.load()
		composer = PinyinComposer(dictionary: dictionary)
	}

	private func best(_ typed: String) -> String {
		composer.candidates(for: .full(typed), limit: 1).first?.text ?? ""
	}

	private func candidates(_ typed: String) -> [String] {
		composer.candidates(for: .full(typed), limit: 12).map(\.text)
	}

	func testTableLoads() {
		XCTAssertGreaterThan(dictionary.totalWeight, 1_000_000)
		XCTAssertEqual(dictionary.entries(for: "zhongguo").first?.text, "中国")
	}

	func testPrefixProbeMatchesLongerKeys() {
		XCTAssertTrue(dictionary.hasPrefix("zhonggu"))
		XCTAssertTrue(dictionary.hasPrefix("z"))
		XCTAssertFalse(dictionary.hasPrefix("zzzzq"))
	}

	func testPolyphoneReadingsBothResolve() {
		XCTAssertTrue(dictionary.entries(for: "hang").contains { $0.text == "行" })
		XCTAssertTrue(dictionary.entries(for: "xing").contains { $0.text == "行" })
		XCTAssertEqual(dictionary.entries(for: "yinhang").first?.text, "银行")
	}

	func testCommonWords() {
		XCTAssertEqual(best("zhongguo"), "中国")
		XCTAssertEqual(best("xianzai"), "现在")
		XCTAssertEqual(best("beijing"), "北京")
		XCTAssertEqual(best("renminbi"), "人民币")
		XCTAssertEqual(best("rengongzhineng"), "人工智能")
	}

	func testShortSentences() {
		XCTAssertEqual(best("woshizhongguoren"), "我是中国人")
		XCTAssertEqual(best("jintiantianqizhenhao"), "今天天气真好")
		XCTAssertEqual(best("womingtianyaokaihui"), "我明天要开会")
	}

	func testSegmentationAmbiguityResolvesToTheCommonReading() {
		XCTAssertEqual(best("xian"), "先")
		XCTAssertEqual(best("fangan"), "方案")
	}

	/// Everyday words whose correct pick depends on the weights being real corpus
	/// frequencies. A word-segmentation frequency table ranks the rarer but less
	/// ambiguous word first here (zaijian -> 在建, nihao -> 拟好).
	func testEverydayWordsOutrankTheirRarerHomophones() {
		XCTAssertEqual(best("zaijian"), "再见")
		XCTAssertEqual(best("nihao"), "你好")
		XCTAssertEqual(best("xiexie"), "谢谢")
		XCTAssertEqual(best("zenmeyang"), "怎么样")
		XCTAssertEqual(best("meiyou"), "没有")
	}

	/// Wanxiang annotates 嗯 as n/ng; people type en. Without the alias these are empty
	/// or land on 恩恩.
	func testInterjectionEnAliases() {
		XCTAssertEqual(best("en"), "嗯")
		XCTAssertEqual(best("enen"), "嗯嗯")
		XCTAssertEqual(best("enne"), "嗯呢")
		XCTAssertTrue(candidates("en").contains("恩"))
	}
}
