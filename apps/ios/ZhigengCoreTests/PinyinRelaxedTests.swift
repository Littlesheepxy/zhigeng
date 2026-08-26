import XCTest
@testable import ZhigengCore

/// Typing shortcuts and slips, against the table that actually ships.
///
/// The numbers behind these cases come from `tools/pinyin-dict/probe.py`, which scores
/// hundreds of generated inputs in seconds. What lives here is the handful of behaviours
/// that must not silently disappear, plus the guarantee that relaxing the match did not
/// cost people who spell correctly anything.
final class PinyinRelaxedTests: XCTestCase {
	private var composer: PinyinComposer!

	override func setUpWithError() throws {
		composer = PinyinComposer(dictionary: try TestDictionary.load())
	}

	private func candidates(_ typed: String, limit: Int = 9) -> [String] {
		composer.candidates(for: .full(typed), limit: limit).map(\.text)
	}

	// MARK: - Half typed

	/// The everyday shortcut: stop partway and let the keyboard finish the word.
	func testHalfTypedWordCompletes() {
		XCTAssertEqual(candidates("shashih").first, "啥时候")
		XCTAssertEqual(candidates("zaiganm").first, "在干嘛")
	}

	/// Committing a completion has to consume every key that was typed, not the length
	/// of the word it grew into, or the leftovers reappear as garbage.
	func testCompletionConsumesTypedKeysOnly() {
		let candidate = composer.candidates(for: .full("shashih")).first { $0.text == "啥时候" }
		XCTAssertEqual(candidate?.length, 7)
	}

	// MARK: - Mixed and initials

	/// Spelling the first syllable out and abbreviating the rest, which is how most
	/// people actually cut corners.
	func testMixedFullAndInitialsReachesTheWord() {
		XCTAssertTrue(candidates("zaigm").contains("在干嘛"))
		XCTAssertTrue(candidates("shashih").contains("啥时候"))
	}

	/// Initials alone are ambiguous enough that the right word rarely leads; what
	/// matters is that it is on the bar at all.
	func testInitialsOnlyOffersTheWord() {
		XCTAssertTrue(candidates("ssh", limit: 12).contains("上市"))
		XCTAssertFalse(candidates("nh").isEmpty)
	}

	// MARK: - Fuzzy and typos

	/// The two confusions that most of southern China types with: the retroflex
	/// initials and the nasal finals.
	func testFuzzyInitialsAndFinals() {
		XCTAssertEqual(candidates("sanghai").first, "上海")
		XCTAssertEqual(candidates("yinghang").first, "银行")
	}

	func testTransposedLettersStillFindTheWord() {
		XCTAssertTrue(candidates("sahshihou").contains("啥时候"))
	}

	func testNeighbouringKeySlipStillFindsTheWord() {
		XCTAssertTrue(candidates("shashihpu").contains("啥时候"))
	}

	// MARK: - The gate

	/// Spelling a word out in full must still put it first. Every relaxation above is
	/// worthless if it costs the common case, and this is the one measurement that says
	/// so — `probe.py` scores six hundred more of these on every constant change.
	func testCorrectSpellingStillWins() {
		for (typed, word) in [
			("nihao", "你好"),
			("ni'hao", "你好"),
			("shashihou", "啥时候"),
			("zaiganma", "在干嘛"),
			("jintian", "今天"),
			("women", "我们"),
			("zhidao", "知道"),
			("shijian", "时间"),
			("gongzuo", "工作"),
			("xiexie", "谢谢"),
			("meiguanxi", "没关系"),
			("weishenme", "为什么"),
			("xianzai", "现在"),
			("keyi", "可以"),
			("haode", "好的"),
			("mingtian", "明天"),
			("dianhua", "电话"),
			("gongsi", "公司"),
			("pengyou", "朋友"),
			("wenti", "问题"),
			("kaishi", "开始"),
			("zhongguo", "中国"),
			("nver", "女儿"),
			("lvxing", "旅行"),
		] {
			XCTAssertEqual(candidates(typed).first, word, "打全拼 \(typed)")
		}
	}

	/// Nine-key already stretches one key into three letters; edit distance on top of
	/// that has no constraint left, so it stays off.
	func testNineKeyKeepsWorkingWithoutTypoCorrection() {
		let digits = composer.candidates(for: .nineKey("64426"), limit: 9).map(\.text)
		XCTAssertEqual(digits.first, "你好")
	}

	/// Letters that start no syllable read as nothing, however far the match is relaxed.
	/// Mashed keys that do start syllables are a different story — `qqqq` really can be
	/// read as 亲亲亲亲, and pretending otherwise would cost the initials shortcut.
	func testLettersThatStartNoSyllableStayEmpty() {
		XCTAssertTrue(candidates("iiii").isEmpty)
	}
}
