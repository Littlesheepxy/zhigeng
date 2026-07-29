import Foundation

public enum AsrStreamEvent: Equatable, Sendable {
	case ready
	case partial(String)
	case done(VoiceResult)
	case failed(String)
}

/// WebSocket client for `apps/asr-proxy` `/asr/stream`.
public final class AsrStreamClient: @unchecked Sendable {
	public static let defaultBaseURL = "ws://127.0.0.1:3003"

	public struct Config: Sendable {
		public var baseURL: String
		public var authToken: String?
		public var hotWords: [String]
		public var languageHints: [String]
		public var mode: String
		public var finishTimeoutMs: Int

		public init(
			baseURL: String = AsrStreamClient.defaultBaseURL,
			authToken: String? = nil,
			hotWords: [String] = [],
			languageHints: [String] = ["zh", "en"],
			mode: String = "structure",
			finishTimeoutMs: Int = 8_000
		) {
			self.baseURL = baseURL
			self.authToken = authToken
			self.hotWords = hotWords
			self.languageHints = languageHints
			self.mode = mode
			self.finishTimeoutMs = finishTimeoutMs
		}
	}

	private let config: Config
	private let onEvent: @Sendable (AsrStreamEvent) -> Void
	private let state = AsrSessionState()
	private var task: URLSessionWebSocketTask?
	private var session: URLSession?
	private var finishTimeoutWork: DispatchWorkItem?
	private let lock = NSLock()
	private var started = false

	public init(config: Config = Config(), onEvent: @escaping @Sendable (AsrStreamEvent) -> Void) {
		self.config = config
		self.onEvent = onEvent
	}

	public static func streamURL(base: String) -> URL {
		let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		return URL(string: "\(trimmed)/asr/stream")!
	}

	public static func pcm16Data(from samples: [Float]) -> Data {
		var data = Data(capacity: samples.count * 2)
		for sample in samples {
			let clipped = max(-1, min(1, sample))
			let intSample = Int16((clipped * Float(Int16.max)).rounded())
			var little = intSample.littleEndian
			withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
		}
		return data
	}

	public func start() {
		lock.lock()
		defer { lock.unlock() }
		guard !started else { return }
		started = true

		let url = Self.streamURL(base: config.baseURL)
		let session = URLSession(configuration: .default)
		let task = session.webSocketTask(with: url)
		self.session = session
		self.task = task
		task.resume()
		receiveLoop(task)
		sendJSON(AsrProtocol.startPayload(
			languageHints: config.languageHints,
			mode: config.mode,
			authToken: config.authToken,
			hotWords: config.hotWords
		)) { [weak self] error in
			if let error {
				self?.fail("无法开始识别：\(error.localizedDescription)")
			}
		}
	}

	public func sendPCM(_ data: Data) {
		guard !data.isEmpty else { return }
		task?.send(.data(data)) { _ in }
	}

	public func sendPCM(samples: [Float]) {
		sendPCM(Self.pcm16Data(from: samples))
	}

	public func finish() {
		state.requestFinish()
		sendJSON(AsrProtocol.finishPayload()) { _ in }
		scheduleFinishTimeout()
	}

	public func abort() {
		sendJSON(AsrProtocol.abortPayload()) { _ in }
		cleanup()
		emit(.done(VoiceResult(text: "", directStructured: false, incomplete: false)))
	}

	public func close() {
		cleanup()
	}

	private func sendJSON(_ data: Data, completion: @escaping @Sendable (Error?) -> Void) {
		guard let text = String(data: data, encoding: .utf8) else {
			completion(nil)
			return
		}
		task?.send(.string(text), completionHandler: completion)
	}

	private func receiveLoop(_ task: URLSessionWebSocketTask) {
		task.receive { [weak self] result in
			guard let self else { return }
			switch result {
			case let .failure(error):
				if !self.state.resolved {
					self.state.handleUnexpectedClose()
					if let result = self.state.result {
						self.emit(.done(result))
					} else {
						self.fail(error.localizedDescription)
					}
				}
				self.cleanup()
			case let .success(message):
				switch message {
				case let .string(text):
					self.handleServerText(text)
				case .data:
					break
				@unknown default:
					break
				}
				if self.task === task, !self.state.resolved {
					self.receiveLoop(task)
				}
			}
		}
	}

	private func handleServerText(_ text: String) {
		let message = AsrProtocol.parseServerText(text)
		switch message {
		case .ready:
			state.handle(message)
			emit(.ready)
		case let .partial(partial):
			state.handle(message)
			emit(.partial(partial))
		case .done:
			finishTimeoutWork?.cancel()
			state.handle(message)
			if let result = state.result {
				emit(.done(result))
			}
			cleanup()
		case let .error(message):
			finishTimeoutWork?.cancel()
			state.handle(.error(message: message))
			if let result = state.result, !result.text.isEmpty {
				emit(.done(result))
			} else {
				fail(message)
			}
			cleanup()
		case .unknown:
			break
		}
	}

	private func scheduleFinishTimeout() {
		finishTimeoutWork?.cancel()
		let work = DispatchWorkItem { [weak self] in
			guard let self, !self.state.resolved else { return }
			self.state.handleFinishTimeout()
			if let result = self.state.result {
				self.emit(.done(result))
			} else {
				self.fail("识别超时，请重说一遍")
			}
			self.cleanup()
		}
		finishTimeoutWork = work
		DispatchQueue.global().asyncAfter(
			deadline: .now() + .milliseconds(config.finishTimeoutMs),
			execute: work
		)
	}

	private func fail(_ message: String) {
		emit(.failed(message))
	}

	private func emit(_ event: AsrStreamEvent) {
		onEvent(event)
	}

	private func cleanup() {
		finishTimeoutWork?.cancel()
		finishTimeoutWork = nil
		task?.cancel(with: .goingAway, reason: nil)
		task = nil
		session?.invalidateAndCancel()
		session = nil
		lock.lock()
		started = false
		lock.unlock()
	}
}
