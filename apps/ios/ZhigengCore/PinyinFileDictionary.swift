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

	/// The table shipped with the framework, built by `tools/pinyin-dict/build.py`.
	public static func bundled() throws -> PinyinFileDictionary {
		guard let url = Bundle.module.url(forResource: "pinyin", withExtension: "zpd") else {
			throw LoadError.unreadable
		}
		return try PinyinFileDictionary(contentsOf: url)
	}

	public func hasPrefix(_ prefix: String) -> Bool {
		let needle = Array(prefix.utf8)
		guard !needle.isEmpty, recordCount > 0 else { return false }
		return data.withUnsafeBytes { bytes in
			let index = lowerBound(bytes, needle)
			guard index < recordCount else { return false }
			let (offset, length) = keyRange(bytes, index)
			guard length >= needle.count else { return false }
			return memcmp(bytes.baseAddress! + keyPoolOffset + offset, needle, needle.count) == 0
		}
	}

	public func entries(for key: String) -> [PinyinWordEntry] {
		let needle = Array(key.utf8)
		guard !needle.isEmpty, recordCount > 0 else { return [] }
		return data.withUnsafeBytes { bytes -> [PinyinWordEntry] in
			var index = lowerBound(bytes, needle)
			var found: [PinyinWordEntry] = []
			while index < recordCount {
				let (offset, length) = keyRange(bytes, index)
				guard length == needle.count,
				      memcmp(bytes.baseAddress! + keyPoolOffset + offset, needle, needle.count) == 0
				else { break }
				found.append(entry(bytes, index))
				index += 1
			}
			return found
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
	private func lowerBound(_ bytes: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Int {
		var low = 0
		var high = recordCount
		while low < high {
			let mid = (low + high) / 2
			let (offset, length) = keyRange(bytes, mid)
			let shared = min(length, needle.count)
			var order = shared == 0 ? 0 : memcmp(bytes.baseAddress! + keyPoolOffset + offset, needle, shared)
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
