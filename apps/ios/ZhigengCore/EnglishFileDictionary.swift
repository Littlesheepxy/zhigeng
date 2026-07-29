import Foundation

/// Reads the `ZEN1` table produced by `tools/english-dict/build.py`.
///
/// Memory-mapped like the pinyin table: the keyboard extension only pays for pages a
/// lookup actually touches. Unigrams drive in-word completion; bigrams drive next-word
/// suggestions after a commit.
public struct EnglishFileDictionary: Sendable {
	public enum LoadError: Error {
		case unreadable
		case badMagic
		case unsupportedVersion(UInt32)
		case truncated
	}

	private static let headerSize = 40
	private static let unigramSize = 12
	private static let bigramSize = 16

	private let data: Data
	private let unigramCount: Int
	private let bigramCount: Int
	private let unigramOffset: Int
	private let bigramOffset: Int
	private let poolOffset: Int

	public init(contentsOf url: URL) throws {
		guard let mapped = try? Data(contentsOf: url, options: .mappedIfSafe) else {
			throw LoadError.unreadable
		}
		guard mapped.count >= Self.headerSize else { throw LoadError.truncated }
		guard mapped.prefix(4).elementsEqual("ZEN1".utf8) else { throw LoadError.badMagic }

		let header = mapped.withUnsafeBytes { bytes -> (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32) in
			(
				UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 4, as: UInt32.self)),
				UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 8, as: UInt32.self)),
				UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 12, as: UInt32.self)),
				UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 16, as: UInt32.self)),
				UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 20, as: UInt32.self)),
				UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 24, as: UInt32.self))
			)
		}
		guard header.0 == 1 else { throw LoadError.unsupportedVersion(header.0) }

		unigramCount = Int(header.1)
		bigramCount = Int(header.2)
		unigramOffset = Int(header.3)
		bigramOffset = Int(header.4)
		poolOffset = Int(header.5)
		data = mapped

		guard unigramOffset + unigramCount * Self.unigramSize <= bigramOffset,
		      bigramOffset + bigramCount * Self.bigramSize <= poolOffset,
		      poolOffset <= mapped.count
		else { throw LoadError.truncated }
	}

	public static func bundled() throws -> EnglishFileDictionary {
		guard let url = bundledURL() else { throw LoadError.unreadable }
		return try EnglishFileDictionary(contentsOf: url)
	}

	/// Same layout rule as the pinyin table: one copy in the containing app.
	static func bundledURL() -> URL? {
		if let url = Bundle.main.url(forResource: "english", withExtension: "zed") {
			return url
		}
		var directory = Bundle.main.bundleURL
		for _ in 0..<2 {
			directory = directory.deletingLastPathComponent()
			let candidate = directory.appendingPathComponent("english.zed")
			if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
		}
		return nil
	}

	/// Prefix completions ranked by weight.
	public func completions(prefix: String, limit: Int = 8) -> [String] {
		let needle = Array(prefix.lowercased().utf8)
		guard !needle.isEmpty, unigramCount > 0, limit > 0 else { return [] }
		return data.withUnsafeBytes { bytes -> [String] in
			var index = lowerBoundUnigram(bytes, needle)
			var scored: [(String, Int)] = []
			while index < unigramCount {
				let (offset, length, weight) = unigramAt(bytes, index)
				guard length >= needle.count,
				      memcmp(bytes.baseAddress! + poolOffset + offset, needle, needle.count) == 0
				else { break }
				let start = bytes.baseAddress! + poolOffset + offset
				let word = String(
					decoding: UnsafeRawBufferPointer(start: start, count: length),
					as: UTF8.self
				)
				scored.append((word, weight))
				index += 1
			}
			scored.sort { lhs, rhs in
				if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
				return lhs.0 < rhs.0
			}
			return scored.prefix(limit).map(\.0)
		}
	}

	/// Next-word suggestions for `previous`, already ranked by bigram weight.
	public func nextWords(after previous: String, limit: Int = 8) -> [String] {
		let needle = Array(previous.lowercased().utf8)
		guard !needle.isEmpty, bigramCount > 0, limit > 0 else { return [] }
		return data.withUnsafeBytes { bytes -> [String] in
			var index = lowerBoundBigram(bytes, needle)
			var found: [String] = []
			while index < bigramCount, found.count < limit {
				let (prevOffset, prevLen, nextOffset, nextLen, _) = bigramAt(bytes, index)
				guard prevLen == needle.count,
				      memcmp(bytes.baseAddress! + poolOffset + prevOffset, needle, needle.count) == 0
				else { break }
				let start = bytes.baseAddress! + poolOffset + nextOffset
				found.append(
					String(decoding: UnsafeRawBufferPointer(start: start, count: nextLen), as: UTF8.self)
				)
				index += 1
			}
			return found
		}
	}

	// MARK: - Binary search

	private func unigramAt(
		_ bytes: UnsafeRawBufferPointer,
		_ index: Int
	) -> (offset: Int, length: Int, weight: Int) {
		let base = unigramOffset + index * Self.unigramSize
		return (
			Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: base, as: UInt32.self))),
			Int(UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: base + 8, as: UInt16.self))),
			Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: base + 4, as: UInt32.self)))
		)
	}

	private func bigramAt(
		_ bytes: UnsafeRawBufferPointer,
		_ index: Int
	) -> (prevOffset: Int, prevLen: Int, nextOffset: Int, nextLen: Int, weight: Int) {
		let base = bigramOffset + index * Self.bigramSize
		return (
			Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: base, as: UInt32.self))),
			Int(bytes.loadUnaligned(fromByteOffset: base + 12, as: UInt8.self)),
			Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: base + 4, as: UInt32.self))),
			Int(bytes.loadUnaligned(fromByteOffset: base + 13, as: UInt8.self)),
			Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: base + 8, as: UInt32.self)))
		)
	}

	private func lowerBoundUnigram(_ bytes: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Int {
		var low = 0
		var high = unigramCount
		while low < high {
			let mid = (low + high) / 2
			let (offset, length, _) = unigramAt(bytes, mid)
			if compare(bytes, offset: offset, length: length, needle: needle) < 0 {
				low = mid + 1
			} else {
				high = mid
			}
		}
		return low
	}

	private func lowerBoundBigram(_ bytes: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Int {
		var low = 0
		var high = bigramCount
		while low < high {
			let mid = (low + high) / 2
			let (offset, length, _, _, _) = bigramAt(bytes, mid)
			if compare(bytes, offset: offset, length: length, needle: needle) < 0 {
				low = mid + 1
			} else {
				high = mid
			}
		}
		return low
	}

	private func compare(
		_ bytes: UnsafeRawBufferPointer,
		offset: Int,
		length: Int,
		needle: [UInt8]
	) -> Int {
		let shared = min(length, needle.count)
		var order = shared == 0
			? 0
			: Int(memcmp(bytes.baseAddress! + poolOffset + offset, needle, shared))
		if order == 0 {
			if length < needle.count { order = -1 }
			else if length > needle.count { order = 1 }
		}
		return order
	}
}
