import Foundation
import ZhigengCore

/// `swift test` has no app bundle to read the table out of, so tests locate it in the
/// source tree. Keeping this out of `PinyinFileDictionary` means the shipping lookup
/// never has a path that only exists on a developer's machine.
enum TestDictionary {
	static func load() throws -> PinyinFileDictionary {
		try PinyinFileDictionary(contentsOf: url)
	}

	static var url: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // ZhigengCoreTests
			.deletingLastPathComponent()  // apps/ios
			.appendingPathComponent("ZhigengCore/Resources/pinyin.zpd")
	}
}
