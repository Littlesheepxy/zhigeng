import Testing
@testable import ZhigengCore

@Test func streamingInsertionReplacesGrowingPartial() {
	var state = StreamingInsertionState()
	let first = state.apply(revision: 1, nextPartial: "你好", contextBefore: "前文")
	#expect(first == .replace(deleteCount: 0, insert: "你好"))
	#expect(state.lastPartial == "你好")

	let second = state.apply(revision: 2, nextPartial: "你好世界", contextBefore: "前文你好")
	#expect(second == .replace(deleteCount: 2, insert: "你好世界"))
	#expect(state.lastPartial == "你好世界")
}

@Test func streamingInsertionAbortsWhenUserMovesCursor() {
	var state = StreamingInsertionState()
	_ = state.apply(revision: 1, nextPartial: "你好", contextBefore: "")
	let action = state.apply(revision: 2, nextPartial: "你好啊", contextBefore: "别的地方")
	#expect(action == .abort)
	#expect(state.aborted)
	#expect(state.apply(revision: 3, nextPartial: "你好啊吗", contextBefore: "别的地方") == .abort)
}

@Test func streamingInsertionSkipsStaleOrDuplicateRevision() {
	var state = StreamingInsertionState()
	_ = state.apply(revision: 2, nextPartial: "甲", contextBefore: "")
	#expect(state.apply(revision: 2, nextPartial: "乙", contextBefore: "甲") == .skip)
	#expect(state.apply(revision: 1, nextPartial: "丙", contextBefore: "甲") == .skip)
	#expect(state.lastPartial == "甲")
}

@Test func streamingInsertionCountsChineseGraphemesForDelete() {
	var state = StreamingInsertionState()
	_ = state.apply(revision: 1, nextPartial: "你好👋", contextBefore: "前")
	let action = state.apply(revision: 2, nextPartial: "你好世界", contextBefore: "前你好👋")
	#expect(action == .replace(deleteCount: 3, insert: "你好世界"))
}

@Test func streamingInsertionFinalClearsPartialTracking() {
	var state = StreamingInsertionState()
	_ = state.apply(revision: 1, nextPartial: "草稿", contextBefore: "")
	let final = state.applyFinal(revision: 2, text: "定稿", contextBefore: "草稿")
	#expect(final == .replace(deleteCount: 2, insert: "定稿"))
	#expect(state.lastPartial.isEmpty)
	#expect(state.lastRevision == 2)
}
