import Foundation
import ZhigengCore

/// `swift test` has no app bundle to read the table out of, so tests locate it in the
/// source tree. Keeping this out of the shipping loaders means those paths never grow a
/// branch that only exists on a developer's machine.
enum TestDictionary {
	static func load() throws -> PinyinFileDictionary {
		try PinyinFileDictionary(contentsOf: resource("pinyin.zpd"))
	}

	static func loadEnglish() throws -> EnglishFileDictionary {
		try EnglishFileDictionary(contentsOf: resource("english.zed"))
	}

	private static func resource(_ name: String) -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // ZhigengCoreTests
			.deletingLastPathComponent()  // apps/ios
			.appendingPathComponent("ZhigengCore/Resources/\(name)")
	}
}
