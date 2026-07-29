import Testing
@testable import ZhigengCore

@Test func textEditDiffExtractsSingleWordReplacement() {
	let pairs = TextEditDiff.replacements(
		original: "帮我跟小扬说一下，ARR 的表今晚改完。",
		edited: "帮我跟小杨说一下，ARR 的表今晚改完。"
	)
	#expect(pairs.count == 1)
	#expect(pairs[0].0 == "小扬")
	#expect(pairs[0].1 == "小杨")
}

@Test func textEditDiffIgnoresIdenticalText() {
	#expect(TextEditDiff.replacements(original: "一样", edited: "一样").isEmpty)
}

@Test func textEditDiffIgnoresHugeRewrite() {
	let pairs = TextEditDiff.replacements(
		original: "短句",
		edited: "这是完全重写的一大段内容，不应该被当成专名学习"
	)
	#expect(pairs.isEmpty)
}
