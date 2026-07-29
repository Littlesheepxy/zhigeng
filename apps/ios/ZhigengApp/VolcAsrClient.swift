import Foundation
import ZhigengCore

/// Fetches Volc credentials from account-api and streams PCM through `VolcAsrEngine`.
final class VolcAsrClient: @unchecked Sendable {
	struct Config: Sendable {
		var apiBase: URL
		var authToken: String
		var hotWords: [String]
		var finishTimeoutMs: Int = 8_000
		var uid: String = "zhigeng-ios"
	}

	private struct TokenResponse: Decodable {
		let appId: String
		let resourceId: String
		let token: String
		let expireAt: String
	}

	private let config: Config
	private let onEvent: @Sendable (AsrStreamEvent) -> Void
	private var engine: VolcAsrEngine?
	private var finishTimeoutWork: DispatchWorkItem?
	private var lastPartial = ""
	private let lock = NSLock()
	private var started = false
	private var engineReady = false
	private var pendingPCM: [Data] = []

	init(config: Config, onEvent: @escaping @Sendable (AsrStreamEvent) -> Void) {
		self.config = config
		self.onEvent = onEvent
	}

	func start() {
		lock.lock()
		guard !started else {
			lock.unlock()
			return
		}
		started = true
		engineReady = false
		pendingPCM.removeAll(keepingCapacity: true)
		lock.unlock()

		Task {
			do {
				let credentials = try await Self.fetchToken(apiBase: config.apiBase, authToken: config.authToken)
				let engine = VolcAsrEngine { [weak self] event in
					self?.handleEngineEvent(event)
				}
				self.engine = engine
				guard engine.configure(
					credentials: .init(
						appId: credentials.appId,
						resourceId: credentials.resourceId,
						token: credentials.token
					),
					hotWords: config.hotWords,
					uid: config.uid
				), engine.start()
				else {
					fail("豆包引擎初始化失败")
					return
				}
			} catch {
				fail(Self.describe(error))
			}
		}
	}

	func sendPCM(_ data: Data) {
		lock.lock()
		defer { lock.unlock() }
		guard started, !data.isEmpty else { return }
		if engineReady {
			engine?.sendPCM(data)
		} else {
			// ponytail: buffer until SDK ready; ceiling ~2s of 16k mono PCM (~64KB), then drop oldest
			pendingPCM.append(data)
			var total = pendingPCM.reduce(0) { $0 + $1.count }
			while total > 64_000, !pendingPCM.isEmpty {
				total -= pendingPCM.removeFirst().count
			}
		}
	}

	func finish() {
		flushPendingPCM()
		scheduleFinishTimeout()
		engine?.finish()
	}

	func abort() {
		finishTimeoutWork?.cancel()
		engine?.abort()
		cleanup()
	}

	func close() {
		finishTimeoutWork?.cancel()
		engine?.close()
		cleanup()
	}

	private func handleEngineEvent(_ event: AsrStreamEvent) {
		switch event {
		case .ready:
			lock.lock()
			engineReady = true
			let buffered = pendingPCM
			pendingPCM.removeAll(keepingCapacity: true)
			lock.unlock()
			for chunk in buffered {
				engine?.sendPCM(chunk)
			}
			emit(.ready)
		case let .partial(text):
			lastPartial = text
			emit(.partial(text))
		case let .done(result):
			finishTimeoutWork?.cancel()
			emit(.done(result))
			cleanup()
		case let .failed(message):
			finishTimeoutWork?.cancel()
			emit(.failed(message))
			cleanup()
		}
	}

	private func flushPendingPCM() {
		lock.lock()
		let buffered = pendingPCM
		pendingPCM.removeAll(keepingCapacity: true)
		engineReady = true
		lock.unlock()
		for chunk in buffered {
			engine?.sendPCM(chunk)
		}
	}

	private func scheduleFinishTimeout() {
		finishTimeoutWork?.cancel()
		let work = DispatchWorkItem { [weak self] in
			guard let self else { return }
			if !self.lastPartial.isEmpty {
				self.emit(.done(VoiceResult(text: self.lastPartial, directStructured: false, incomplete: true)))
			} else {
				self.emit(.failed("识别超时，请重说一遍"))
			}
			self.engine?.close()
			self.cleanup()
		}
		finishTimeoutWork = work
		DispatchQueue.global().asyncAfter(
			deadline: .now() + .milliseconds(config.finishTimeoutMs),
			execute: work
		)
	}

	private static func fetchToken(apiBase: URL, authToken: String) async throws -> TokenResponse {
		guard let url = URL(string: "/asr/volc-token", relativeTo: apiBase) else {
			throw VolcAsrClientError.invalidURL
		}
		var request = URLRequest(url: url)
		request.timeoutInterval = 12
		request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
		let (data, response) = try await URLSession.shared.data(for: request)
		guard let http = response as? HTTPURLResponse else {
			throw VolcAsrClientError.unexpectedResponse
		}
		switch http.statusCode {
		case 200:
			return try JSONDecoder().decode(TokenResponse.self, from: data)
		case 401:
			throw VolcAsrClientError.notSignedIn
		case 503:
			throw VolcAsrClientError.notConfigured
		default:
			if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data), let error = body.error {
				throw VolcAsrClientError.server(error)
			}
			throw VolcAsrClientError.unexpectedResponse
		}
	}

	private static func describe(_ error: Error) -> String {
		if let volc = error as? VolcAsrClientError {
			return volc.errorDescription ?? "识别失败"
		}
		let ns = error as NSError
		if ns.domain == NSURLErrorDomain {
			switch ns.code {
			case NSURLErrorTimedOut:
				return "连接账户服务超时，请确认 Mac 上 account-api 已启动"
			case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
				return "无法连接账户服务，请检查 API 地址与同一 Wi-Fi"
			case NSURLErrorCannotFindHost:
				return "找不到账户服务地址，请在「我的 → 登录」核对 API"
			default:
				break
			}
		}
		return error.localizedDescription
	}

	private func fail(_ message: String) {
		emit(.failed(message))
		cleanup()
	}

	private func emit(_ event: AsrStreamEvent) {
		onEvent(event)
	}

	private func cleanup() {
		finishTimeoutWork?.cancel()
		finishTimeoutWork = nil
		if let engine {
			engine.close()
		}
		engine = nil
		lock.lock()
		started = false
		engineReady = false
		pendingPCM.removeAll(keepingCapacity: false)
		lock.unlock()
	}
}

private struct APIErrorBody: Decodable {
	let error: String?
}

enum VolcAsrClientError: LocalizedError {
	case invalidURL
	case unexpectedResponse
	case notSignedIn
	case notConfigured
	case server(String)

	var errorDescription: String? {
		switch self {
		case .invalidURL: "账户 API 地址无效"
		case .unexpectedResponse: "无法获取豆包识别凭证"
		case .notSignedIn: "请先登录账户后再使用听写"
		case .notConfigured: "服务端未配置豆包 ASR，请联系管理员"
		case .server(let code): "识别凭证获取失败：\(code)"
		}
	}
}
