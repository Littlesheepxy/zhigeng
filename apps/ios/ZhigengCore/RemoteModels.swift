import Foundation

public enum RemoteProtocolError: Error {
	case invalidPairingURL
}

public struct RemotePairingPayload: Equatable, Sendable {
	public let pairingId: String
	public let code: String
	public let apiBase: URL

	public init(url: URL) throws {
		guard url.scheme == "zhigeng",
		      url.host == "pair",
		      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
		else { throw RemoteProtocolError.invalidPairingURL }
		let values = Dictionary(
			uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
				item.value.map { (item.name, $0) }
			}
		)
		guard let pairingId = values["pid"], !pairingId.isEmpty,
		      let code = values["c"], code.count == 6, code.allSatisfy(\.isNumber),
		      let apiBase = values["api"].flatMap(URL.init(string:)),
		      apiBase.scheme == "http" || apiBase.scheme == "https",
		      apiBase.host != nil
		else { throw RemoteProtocolError.invalidPairingURL }
		self.pairingId = pairingId
		self.code = code
		self.apiBase = apiBase
	}
}

public enum JSONValue: Codable, Equatable, Sendable {
	case string(String)
	case number(Double)
	case bool(Bool)
	case object([String: JSONValue])
	case array([JSONValue])
	case null

	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if container.decodeNil() {
			self = .null
		} else if let value = try? container.decode(Bool.self) {
			self = .bool(value)
		} else if let value = try? container.decode(Double.self) {
			self = .number(value)
		} else if let value = try? container.decode(String.self) {
			self = .string(value)
		} else if let value = try? container.decode([String: JSONValue].self) {
			self = .object(value)
		} else {
			self = .array(try container.decode([JSONValue].self))
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
		case .string(let value): try container.encode(value)
		case .number(let value): try container.encode(value)
		case .bool(let value): try container.encode(value)
		case .object(let value): try container.encode(value)
		case .array(let value): try container.encode(value)
		case .null: try container.encodeNil()
		}
	}

	public var stringValue: String? {
		if case .string(let value) = self { value } else { nil }
	}

	public var objectValue: [String: JSONValue]? {
		if case .object(let value) = self { value } else { nil }
	}

	public var arrayValue: [JSONValue]? {
		if case .array(let value) = self { value } else { nil }
	}

	public var boolValue: Bool? {
		if case .bool(let value) = self { value } else { nil }
	}
}

public enum RemoteTurnStatus: String, Codable, Sendable {
	case queued
	case dispatched
	case running
	case awaitingApproval = "awaiting_approval"
	case completed
	case failed
	case canceled

	public init(relayValue: String) {
		self = Self(rawValue: relayValue) ?? .running
	}
}

public struct RemoteTurnState: Identifiable, Equatable, Sendable {
	public let id: String
	public let threadId: String
	public let content: String
	public var status: RemoteTurnStatus
	public var headline: String
	public var state: JSONValue?

	public init(
		id: String,
		threadId: String,
		content: String,
		status: RemoteTurnStatus = .queued,
		headline: String = "等待 Mac 接收"
	) {
		self.id = id
		self.threadId = threadId
		self.content = content
		self.status = status
		self.headline = headline
	}

	public mutating func apply(status relayStatus: String, state: JSONValue?) {
		status = RemoteTurnStatus(relayValue: relayStatus)
		self.state = state
		guard case .object(let object) = state else {
			headline = status == .completed ? "已完成" : relayStatus
			return
		}
		headline =
			object["result"]?.stringValue
			?? object["error"]?.stringValue
			?? object["message"]?.stringValue
			?? object["status"]?.stringValue
			?? relayStatus
	}
}

public struct RemoteThreadSummary: Identifiable, Codable, Equatable, Sendable {
	public let id: String
	public let title: String
	public let status: String
	public let createdAt: String
	public let updatedAt: String

	public init(id: String, title: String, status: String, createdAt: String, updatedAt: String) {
		self.id = id
		self.title = title
		self.status = status
		self.createdAt = createdAt
		self.updatedAt = updatedAt
	}
}
