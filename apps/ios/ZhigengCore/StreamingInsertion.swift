import Foundation

public enum StreamingInsertionAction: Equatable, Sendable {
	case replace(deleteCount: Int, insert: String)
	case skip
	case abort
}

/// Tracks the last streamed partial so the keyboard can safely rewrite at the cursor.
/// If the user edits or moves the caret, context no longer ends with `lastPartial` → abort.
public struct StreamingInsertionState: Equatable, Sendable {
	public var lastPartial: String
	public var lastRevision: Int
	public var aborted: Bool

	public init(lastPartial: String = "", lastRevision: Int = 0, aborted: Bool = false) {
		self.lastPartial = lastPartial
		self.lastRevision = lastRevision
		self.aborted = aborted
	}

	public mutating func apply(
		revision: Int,
		nextPartial: String,
		contextBefore: String
	) -> StreamingInsertionAction {
		guard !aborted else { return .abort }
		guard revision > lastRevision else { return .skip }
		if !lastPartial.isEmpty, !contextBefore.hasSuffix(lastPartial) {
			aborted = true
			return .abort
		}
		let deleteCount = lastPartial.count
		lastPartial = nextPartial
		lastRevision = revision
		return .replace(deleteCount: deleteCount, insert: nextPartial)
	}

	public mutating func applyFinal(
		revision: Int,
		text: String,
		contextBefore: String
	) -> StreamingInsertionAction {
		let action = apply(revision: revision, nextPartial: text, contextBefore: contextBefore)
		if case .replace = action {
			lastPartial = ""
		}
		return action
	}

	public mutating func reset() {
		lastPartial = ""
		lastRevision = 0
		aborted = false
	}
}
