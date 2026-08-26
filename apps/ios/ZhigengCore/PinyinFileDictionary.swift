import Foundation

/// Reads the `ZPD1` table produced by `tools/pinyin-dict/build.py`.
///
/// The file is memory mapped and searched in place: nothing is decoded up front, so the
/// keyboard extension pays for pages it actually touches rather than for the whole table.
/// That matters — a custom keyboard is killed somewhere around 50 MB resident.
public struct PinyinFileDictionary: PinyinDictionary {
	public enum LoadError: Error {
		case unreadable
		case badMagic
		case unsupportedVersion(UInt32)
		case truncated
	}

	private static let headerSize = 32
	private static let recordSize = 16

	private let data: Data
	private let recordCount: Int
	private let recordsOffset: Int
	private let keyPoolOffset: Int
	private let wordPoolOffset: Int
	public let totalWeight: Int

	public init(contentsOf url: URL) throws {
		guard let mapped = try? Data(contentsOf: url, options: .mappedIfSafe) else {
			throw LoadError.unreadable
		}
		guard mapped.count >= Self.headerSize else { throw LoadError.truncated }

		guard mapped.prefix(4).elementsEqual("ZPD1".utf8) else { throw LoadError.badMagic }

		let header: (version: UInt32, count: UInt32, total: UInt64, records: UInt32, keys: UInt32, words: UInt32)
		header = mapped.withUnsafeBytes { bytes in
			(
				UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 4, as: UInt32.self)),
				UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 8, as: UInt32.self)),
				UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: 12, as: UInt64.self)),
				UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 20, as: UInt32.self)),
				UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 24, as: UInt32.self)),
				UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 28, as: UInt32.self))
			)
		}
		guard header.version == 1 else { throw LoadError.unsupportedVersion(header.version) }

		recordCount = Int(header.count)
		recordsOffset = Int(header.records)
		keyPoolOffset = Int(header.keys)
		wordPoolOffset = Int(header.words)
		totalWeight = Int(header.total)
		data = mapped

		guard recordsOffset + recordCount * Self.recordSize <= keyPoolOffset,
		      keyPoolOffset <= wordPoolOffset,
		      wordPoolOffset <= mapped.count
		else { throw LoadError.truncated }
	}

	/// The table shipped with the app, built by `tools/pinyin-dict/build.py`.
	public static func bundled() throws -> PinyinFileDictionary {
		guard let url = bundledURL() else { throw LoadError.unreadable }
		return try PinyinFileDictionary(contentsOf: url)
	}

	/// The 26MB table ships once, in the containing app. An extension lives at
	/// `Zhigeng.app/PlugIns/X.appex` and reads its way up to the app bundle instead of
	/// carrying a second copy, which is what kept the installed size at 73MB.
	///
	/// Walking up is bounded to the two levels that nesting actually uses; a plain loop
	/// to the filesystem root would happily find a stale table in some parent directory.
	static func bundledURL() -> URL? {
		if let url = Bundle.main.url(forResource: "pinyin", withExtension: "zpd") {
			return url
		}
		var directory = Bundle.main.bundleURL
		for _ in 0..<2 {
			directory = directory.deletingLastPathComponent()
			let candidate = directory.appendingPathComponent("pinyin.zpd")
			if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
		}
		return nil
	}

	public func hasPrefix(_ prefix: String) -> Bool {
		lookup(prefix) != .miss
	}

	public func entries(for key: String) -> [PinyinWordEntry] {
		guard case .words(let found) = lookup(key) else { return [] }
		return found
	}

	/// The relaxed lattice runs this thousands of times per keystroke, so it does the one
	/// binary search both answers need, reads the key straight out of the mapped bytes,
	/// and builds `PinyinWordEntry` strings only on a real hit.
	public func lookup(_ key: String) -> PinyinLookup {
		guard !key.isEmpty, recordCount > 0 else { return .miss }
		var key = key
		return key.withUTF8 { needle in
			data.withUnsafeBytes { bytes -> PinyinLookup in
				var index = lowerBound(bytes, needle)
				guard index < recordCount else { return .miss }
				let (offset, length) = keyRange(bytes, index)
				guard length >= needle.count,
				      memcmp(bytes.baseAddress! + keyPoolOffset + offset, needle.baseAddress!, needle.count) == 0
				else { return .miss }
				guard length == needle.count else { return .prefix }

				var found: [PinyinWordEntry] = []
				while index < recordCount {
					let (offset, length) = keyRange(bytes, index)
					guard length == needle.count,
					      memcmp(bytes.baseAddress! + keyPoolOffset + offset, needle.baseAddress!, needle.count) == 0
					else { break }
					found.append(entry(bytes, index))
					index += 1
				}
				return .words(found)
			}
		}
	}

	// MARK: - Raw access

	private func recordBase(_ index: Int) -> Int { recordsOffset + index * Self.recordSize }

	private func keyRange(_ bytes: UnsafeRawBufferPointer, _ index: Int) -> (offset: Int, length: Int) {
		let base = recordBase(index)
		let offset = Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: base, as: UInt32.self)))
		let length = Int(bytes.loadUnaligned(fromByteOffset: base + 12, as: UInt8.self))
		return (offset, length)
	}

	private func entry(_ bytes: UnsafeRawBufferPointer, _ index: Int) -> PinyinWordEntry {
		let base = recordBase(index)
		let wordOffset = Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: base + 4, as: UInt32.self)))
		let weight = Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: base + 8, as: UInt32.self)))
		let wordLength = Int(bytes.loadUnaligned(fromByteOffset: base + 13, as: UInt8.self))
		let start = bytes.baseAddress! + wordPoolOffset + wordOffset
		let text = String(
			decoding: UnsafeRawBufferPointer(start: start, count: wordLength),
			as: UTF8.self
		)
		return PinyinWordEntry(text: text, weight: weight)
	}

	/// First record whose key is >= `needle`, comparing raw bytes.
	private func lowerBound(_ bytes: UnsafeRawBufferPointer, _ needle: UnsafeBufferPointer<UInt8>) -> Int {
		var low = 0
		var high = recordCount
		while low < high {
			let mid = (low + high) / 2
			let (offset, length) = keyRange(bytes, mid)
			let shared = min(length, needle.count)
			var order = shared == 0
				? 0
				: memcmp(bytes.baseAddress! + keyPoolOffset + offset, needle.baseAddress!, shared)
			if order == 0 { order = length < needle.count ? -1 : 0 }
			if order < 0 {
				low = mid + 1
			} else {
				high = mid
			}
		}
		return low
	}
}
