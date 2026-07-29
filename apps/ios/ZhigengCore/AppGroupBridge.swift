import Foundation

/// Atomic JSON read/write over the App Group container.
public final class AppGroupBridge: @unchecked Sendable {
	public let suiteName: String
	private let fileManager: FileManager
	private let containerOverride: URL?
	private let encoder = JSONEncoder()
	private let decoder = JSONDecoder()

	public init(
		suiteName: String = AppGroupConstants.suiteName,
		fileManager: FileManager = .default,
		containerOverride: URL? = nil
	) {
		self.suiteName = suiteName
		self.fileManager = fileManager
		self.containerOverride = containerOverride
	}

	public var containerURL: URL? {
		if let containerOverride { return containerOverride }
		return fileManager.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
	}

	public func writeRequest(_ request: DictationRequest) throws {
		try write(request, fileName: AppGroupConstants.requestFileName)
	}

	public func readRequest() throws -> DictationRequest? {
		try read(DictationRequest.self, fileName: AppGroupConstants.requestFileName)
	}

	public func writeResult(_ result: DictationResult) throws {
		try write(result, fileName: AppGroupConstants.resultFileName)
	}

	public func readResult() throws -> DictationResult? {
		try read(DictationResult.self, fileName: AppGroupConstants.resultFileName)
	}

	/// Returns an insertable result only when requestId matches and status is ready.
	public func consumeInsertableResult(matching requestId: String) throws -> DictationResult? {
		guard let result = try readResult() else { return nil }
		guard result.requestId == requestId else { return nil }
		guard result.isInsertable else { return nil }
		try clearResult()
		return result
	}

	public func clearResult() throws {
		try remove(fileName: AppGroupConstants.resultFileName)
	}

	public func writeSession(_ session: DictationSession) throws {
		try write(session, fileName: AppGroupConstants.sessionFileName)
	}

	public func readSession() throws -> DictationSession? {
		try read(DictationSession.self, fileName: AppGroupConstants.sessionFileName)
	}

	public func writeCommand(_ command: DictationCommand) throws {
		try write(command, fileName: AppGroupConstants.commandFileName)
	}

	public func readCommand() throws -> DictationCommand? {
		try read(DictationCommand.self, fileName: AppGroupConstants.commandFileName)
	}

	/// Returns and clears the pending command (if any).
	public func consumeCommand() throws -> DictationCommand? {
		guard let command = try readCommand() else { return nil }
		try remove(fileName: AppGroupConstants.commandFileName)
		return command
	}

	/// Newer revision only — does not clear the file (keyboard may re-read until final).
	public func readResultIfNewer(than revision: Int) throws -> DictationResult? {
		guard let result = try readResult(), result.revision > revision else { return nil }
		return result
	}

	public func writeLexicon(_ data: Data) throws {
		guard let url = fileURL(AppGroupConstants.lexiconFileName) else {
			throw AppGroupBridgeError.containerUnavailable
		}
		try atomicWrite(data, to: url)
	}

	public func readLexiconData() throws -> Data? {
		guard let url = fileURL(AppGroupConstants.lexiconFileName) else {
			throw AppGroupBridgeError.containerUnavailable
		}
		guard fileManager.fileExists(atPath: url.path) else { return nil }
		return try Data(contentsOf: url)
	}

	public func writeHeartbeat(_ heartbeat: KeyboardHeartbeat) throws {
		try write(heartbeat, fileName: AppGroupConstants.keyboardHeartbeatFileName)
	}

	public func readHeartbeat() throws -> KeyboardHeartbeat? {
		try read(KeyboardHeartbeat.self, fileName: AppGroupConstants.keyboardHeartbeatFileName)
	}

	private func write<T: Encodable>(_ value: T, fileName: String) throws {
		guard let url = fileURL(fileName) else {
			throw AppGroupBridgeError.containerUnavailable
		}
		let data = try encoder.encode(value)
		try atomicWrite(data, to: url)
	}

	private func read<T: Decodable>(_ type: T.Type, fileName: String) throws -> T? {
		guard let url = fileURL(fileName) else {
			throw AppGroupBridgeError.containerUnavailable
		}
		guard fileManager.fileExists(atPath: url.path) else { return nil }
		let data = try Data(contentsOf: url)
		return try decoder.decode(type, from: data)
	}

	private func remove(fileName: String) throws {
		guard let url = fileURL(fileName) else {
			throw AppGroupBridgeError.containerUnavailable
		}
		if fileManager.fileExists(atPath: url.path) {
			try fileManager.removeItem(at: url)
		}
	}

	private func fileURL(_ fileName: String) -> URL? {
		containerURL?.appendingPathComponent(fileName)
	}

	private func atomicWrite(_ data: Data, to url: URL) throws {
		let dir = url.deletingLastPathComponent()
		try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
		let temp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
		try data.write(to: temp, options: .atomic)
		if fileManager.fileExists(atPath: url.path) {
			_ = try fileManager.replaceItemAt(url, withItemAt: temp)
		} else {
			try fileManager.moveItem(at: temp, to: url)
		}
	}
}

public enum AppGroupBridgeError: Error, Equatable {
	case containerUnavailable
}
