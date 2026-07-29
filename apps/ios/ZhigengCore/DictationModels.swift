import Foundation

public enum AppGroupConstants {
	public static let suiteName = "group.app.zhigeng.ios"
	public static let chineseKeyboardLayoutKey = "keyboard.chineseLayout"
	public static let requestFileName = "dictation_request.json"
	public static let resultFileName = "dictation_result.json"
	public static let sessionFileName = "dictation_session.json"
	public static let commandFileName = "dictation_command.json"
	public static let lexiconFileName = "personal_lexicon.json"
	public static let keyboardHeartbeatFileName = "keyboard_heartbeat.json"
	/// Darwin notification name for result ready (App Group + notify).
	public static let resultReadyNotification = "app.zhigeng.ios.dictation.result"
	public static let commandReadyNotification = "app.zhigeng.ios.dictation.command"
}

public enum VoiceDeletePlacement: Equatable, Sendable {
	case topTrailing
	case aboveSend
}

public enum ChineseKeyboardLayout: String, CaseIterable, Codable, Sendable {
	case nineKey
	case fullKeyboard

	public var voiceDeletePlacement: VoiceDeletePlacement {
		switch self {
		case .nineKey: .topTrailing
		case .fullKeyboard: .aboveSend
		}
	}
}

/// Heartbeat written by the keyboard extension; main app must not invent Full Access.
public struct KeyboardHeartbeat: Codable, Equatable, Sendable {
	public var lastSeenAt: TimeInterval
	public var hasFullAccess: Bool
	public var extensionVersion: String

	public init(
		lastSeenAt: TimeInterval = Date().timeIntervalSince1970,
		hasFullAccess: Bool,
		extensionVersion: String = "0.1.0"
	) {
		self.lastSeenAt = lastSeenAt
		self.hasFullAccess = hasFullAccess
		self.extensionVersion = extensionVersion
	}

	public static let freshWindowSeconds: TimeInterval = 7 * 24 * 60 * 60

	public var isFresh: Bool {
		Date().timeIntervalSince1970 - lastSeenAt <= Self.freshWindowSeconds
	}
}

public enum DictationHistorySource: String, Codable, Sendable {
	case main
	case keyboard
	case demo
}

/// Local history for the main app only — not shared via App Group.
public struct DictationHistoryItem: Codable, Equatable, Identifiable, Sendable {
	public static let retentionDays = 30

	public var id: String
	public var createdAt: TimeInterval
	public var source: DictationHistorySource
	public var status: DictationStatus
	public var cleanedText: String
	public var directStructured: Bool
	public var durationMs: Int?
	public var errorMessage: String?
	public var processingTags: [String]
	/// nil = 未留下；有值 = 用户手动点过「留下」
	public var keptAt: TimeInterval?

	public var isKept: Bool { keptAt != nil }

	public init(
		id: String = UUID().uuidString,
		createdAt: TimeInterval = Date().timeIntervalSince1970,
		source: DictationHistorySource,
		status: DictationStatus,
		cleanedText: String,
		directStructured: Bool = false,
		durationMs: Int? = nil,
		errorMessage: String? = nil,
		processingTags: [String] = [],
		keptAt: TimeInterval? = nil
	) {
		self.id = id
		self.createdAt = createdAt
		self.source = source
		self.status = status
		self.cleanedText = cleanedText
		self.directStructured = directStructured
		self.durationMs = durationMs
		self.errorMessage = errorMessage
		self.processingTags = processingTags
		self.keptAt = keptAt
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(String.self, forKey: .id)
		createdAt = try container.decode(TimeInterval.self, forKey: .createdAt)
		source = try container.decode(DictationHistorySource.self, forKey: .source)
		status = try container.decode(DictationStatus.self, forKey: .status)
		cleanedText = try container.decode(String.self, forKey: .cleanedText)
		directStructured = try container.decode(Bool.self, forKey: .directStructured)
		durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
		errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
		processingTags = try container.decodeIfPresent([String].self, forKey: .processingTags) ?? []
		keptAt = try container.decodeIfPresent(TimeInterval.self, forKey: .keptAt)
	}

	/// Keep all manually kept items; drop unkept older than retentionDays.
	public static func prune(
		_ items: [DictationHistoryItem],
		now: TimeInterval = Date().timeIntervalSince1970,
		retentionDays: Int = retentionDays
	) -> [DictationHistoryItem] {
		let cutoff = now - TimeInterval(retentionDays) * 86_400
		return items.filter { $0.isKept || $0.createdAt >= cutoff }
	}
}

public enum HomeReadyKind: Equatable, Sendable {
	case setupIncomplete(missing: [HomeSetupItem])
	case ready
	case sessionActive(remainingSeconds: Int, modeLabel: String)
	case error(message: String, actionTitle: String)
}

public enum HomeSetupItem: String, Equatable, CaseIterable, Sendable {
	case microphone
	case keyboard
	case fullAccess
}

/// Pure reducer for the home hero — keeps UI honest about keyboard/Full Access detection.
public enum HomeReadyState {
	public static func resolve(
		microphoneGranted: Bool,
		heartbeat: KeyboardHeartbeat?,
		sessionActiveUntil: TimeInterval?,
		sessionModeLabel: String?,
		now: TimeInterval = Date().timeIntervalSince1970,
		serviceError: String? = nil,
		keyboardInstalled: Bool = false
	) -> HomeReadyKind {
		if let serviceError, !serviceError.isEmpty {
			return .error(message: serviceError, actionTitle: "查看说明")
		}
		if let until = sessionActiveUntil, until > now {
			return .sessionActive(
				remainingSeconds: Int(until - now),
				modeLabel: sessionModeLabel ?? "即听即写"
			)
		}
		var missing: [HomeSetupItem] = []
		if !microphoneGranted { missing.append(.microphone) }

		let keyboardSeen = keyboardInstalled || (heartbeat?.isFresh == true)
		if !keyboardSeen {
			missing.append(.keyboard)
			return .setupIncomplete(missing: missing)
		}
		// Full Access can only be confirmed after the keyboard extension runs once.
		if heartbeat?.isFresh != true || heartbeat?.hasFullAccess != true {
			missing.append(.fullAccess)
		}
		if missing.isEmpty {
			return .ready
		}
		return .setupIncomplete(missing: missing)
	}
}

public enum DictationStatus: String, Codable, Sendable {
	case idle
	case requesting
	case recording
	case processing
	case ready
	case incomplete
	case error
}

public struct DictationRequest: Codable, Equatable, Sendable {
	public var requestId: String
	public var createdAt: TimeInterval
	public var source: String

	public init(requestId: String = UUID().uuidString, createdAt: TimeInterval = Date().timeIntervalSince1970, source: String = "keyboard") {
		self.requestId = requestId
		self.createdAt = createdAt
		self.source = source
	}
}

public struct DictationResult: Codable, Equatable, Sendable {
	public var requestId: String
	public var status: DictationStatus
	public var text: String
	public var segments: [VoiceSegment]
	public var directStructured: Bool
	public var ts: TimeInterval
	public var errorMessage: String?
	/// Monotonic per request; keyboard applies only newer revisions.
	public var revision: Int

	public init(
		requestId: String,
		status: DictationStatus,
		text: String = "",
		segments: [VoiceSegment] = [],
		directStructured: Bool = false,
		ts: TimeInterval = Date().timeIntervalSince1970,
		errorMessage: String? = nil,
		revision: Int = 0
	) {
		self.requestId = requestId
		self.status = status
		self.text = text
		self.segments = segments
		self.directStructured = directStructured
		self.ts = ts
		self.errorMessage = errorMessage
		self.revision = revision
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		requestId = try container.decode(String.self, forKey: .requestId)
		status = try container.decode(DictationStatus.self, forKey: .status)
		text = try container.decode(String.self, forKey: .text)
		segments = try container.decodeIfPresent([VoiceSegment].self, forKey: .segments) ?? []
		directStructured = try container.decodeIfPresent(Bool.self, forKey: .directStructured) ?? false
		ts = try container.decode(TimeInterval.self, forKey: .ts)
		errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
		revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
	}

	public var isInsertable: Bool {
		status == .ready && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
}

public enum DictationSessionMode: String, Codable, Sendable {
	case pip
	case liveActivity
}

public enum DictationCommandKind: String, Codable, Sendable {
	case start
	case stop
	case cancel
}

public struct DictationCommand: Codable, Equatable, Sendable {
	public var commandId: String
	public var requestId: String
	public var kind: DictationCommandKind
	public var createdAt: TimeInterval

	public init(
		kind: DictationCommandKind,
		requestId: String = UUID().uuidString,
		commandId: String = UUID().uuidString,
		createdAt: TimeInterval = Date().timeIntervalSince1970
	) {
		self.commandId = commandId
		self.requestId = requestId
		self.kind = kind
		self.createdAt = createdAt
	}
}

public struct DictationSession: Codable, Equatable, Sendable {
	/// Heartbeat older than this → keyboard treats service as dead.
	public static let heartbeatFreshSeconds: TimeInterval = 8

	public var activeUntil: TimeInterval
	public var state: DictationStatus
	public var mode: DictationSessionMode?
	public var heartbeatAt: TimeInterval?

	public init(
		activeUntil: TimeInterval,
		state: DictationStatus = .idle,
		mode: DictationSessionMode? = nil,
		heartbeatAt: TimeInterval? = nil
	) {
		self.activeUntil = activeUntil
		self.state = state
		self.mode = mode
		self.heartbeatAt = heartbeatAt
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		activeUntil = try container.decode(TimeInterval.self, forKey: .activeUntil)
		state = try container.decode(DictationStatus.self, forKey: .state)
		mode = try container.decodeIfPresent(DictationSessionMode.self, forKey: .mode)
		heartbeatAt = try container.decodeIfPresent(TimeInterval.self, forKey: .heartbeatAt)
	}

	public var isActive: Bool {
		isActive(now: Date().timeIntervalSince1970)
	}

	public func isActive(now: TimeInterval) -> Bool {
		now < activeUntil
	}

	/// Alive = not expired AND recent heartbeat from main app.
	public func isServiceAlive(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
		guard isActive(now: now), let heartbeatAt else { return false }
		return now - heartbeatAt <= Self.heartbeatFreshSeconds
	}
}
