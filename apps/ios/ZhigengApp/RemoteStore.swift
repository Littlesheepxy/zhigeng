import Foundation
import Observation
import Security
import UIKit
import ZhigengCore

struct RemoteApproval: Identifiable, Equatable {
	struct Option: Identifiable, Equatable {
		let id: String
		let label: String
		let tone: String?
	}

	let id: String
	let turnId: String
	let requestId: String
	let title: String
	let message: String
	let risk: String?
	let options: [Option]
}

private struct RemoteSession: Codable {
	let apiBase: URL
	let token: String
	let email: String
}

private struct AuthVerifyResponse: Decodable {
	struct User: Decodable { let email: String }
	let apiKey: String
	let user: User
}

private struct ThreadListResponse: Decodable {
	let threads: [RemoteThreadSummary]
}

private struct TurnResponse: Decodable {
	let id: String
	let threadId: String
	let content: String
	let status: String
}

private struct ThreadDetailResponse: Decodable {
	let id: String
	let turns: [TurnResponse]
}

private struct APIErrorBody: Decodable {
	let error: String?
}

private enum RemoteAPIError: LocalizedError {
	case response(String)

	var errorDescription: String? {
		switch self {
		case .response(let code):
			switch code {
			case "unauthorized": "登录已过期，请重新登录"
			case "forbidden": "配对码与当前账户不匹配"
			case "expired": "配对码已失效，请在 Mac 上重新生成"
			case "mac_offline": "Mac 当前不在线"
			case "mac_busy": "Mac 正在执行另一个任务"
			default: code
			}
		}
	}
}

@Observable
@MainActor
final class RemoteStore {
	private static let keychainService = "app.zhigeng.ios.remote"
	private static let keychainAccount = "session"

	var pairing: RemotePairingPayload?
	var email = ""
	var code = ""
	var signedIn = false
	var macOnline = false
	var isBusy = false
	var error: String?
	var threads: [RemoteThreadSummary] = []
	var activeThreadId: String?
	var turns: [RemoteTurnState] = []
	var approval: RemoteApproval?

	var asrAuthToken: String? { session?.token }
	var accountApiBase: URL? {
		guard let base = session?.apiBase else { return nil }
		return Self.rewrittenForDevice(base)
	}

	/// Default account-api for standalone login (LAN). Override via UserDefaults `accountApiBase`.
	static var defaultAccountApiBase: URL {
		if let saved = UserDefaults.standard.string(forKey: "accountApiBase"),
		   let url = URL(string: saved), url.host != nil
		{
			return rewrittenForDevice(url)
		}
		#if targetEnvironment(simulator)
		return URL(string: "http://127.0.0.1:3010")!
		#else
		return URL(string: "http://172.16.1.15:3010")!
		#endif
	}

	/// True-device cannot reach Mac's loopback; rewrite to LAN default host.
	static func rewrittenForDevice(_ url: URL) -> URL {
		#if targetEnvironment(simulator)
		return url
		#else
		guard let host = url.host, host == "127.0.0.1" || host == "localhost" else { return url }
		var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
		let lanHost = (UserDefaults.standard.string(forKey: "accountApiBase").flatMap(URL.init).flatMap(\.host))
			?? "172.16.1.15"
		comps?.host = (lanHost == "127.0.0.1" || lanHost == "localhost") ? "172.16.1.15" : lanHost
		return comps?.url ?? url
		#endif
	}

	private var session: RemoteSession?
	private var webSocket: URLSessionWebSocketTask?
	private var receiveTask: Task<Void, Never>?

	init() {
		session = Self.loadSession()
		signedIn = session != nil
		email = session?.email ?? ""
		if session != nil {
			Task {
				await refreshThreads()
				connect()
			}
		}
	}

	func preparePairing(url: URL) {
		do {
			let payload = try RemotePairingPayload(url: url)
			if session?.apiBase != payload.apiBase {
				session = nil
				signedIn = false
				Self.clearSession()
				disconnect()
			}
			pairing = payload
			error = nil
		} catch {
			self.error = "这个二维码不是有效的知更 Mac 配对码"
		}
	}

	func requestCode() async {
		guard let apiBase = pairing?.apiBase, !email.trimmingCharacters(in: .whitespaces).isEmpty
		else {
			error = "请输入邮箱"
			return
		}
		await perform {
			let body = try JSONEncoder().encode(["email": email.trimmingCharacters(in: .whitespaces)])
			let _: EmptyResponse = try await request(
				apiBase: apiBase,
				path: "/auth/request-code",
				method: "POST",
				body: body
			)
		}
	}

	func verifyAndClaim() async -> Bool {
		guard let pairing else {
			error = "请重新扫描 Mac 上的二维码"
			return false
		}
		var success = false
		await perform {
			let authBody = try JSONEncoder().encode([
				"email": email.trimmingCharacters(in: .whitespaces),
				"code": code.trimmingCharacters(in: .whitespaces),
			])
			let auth: AuthVerifyResponse = try await request(
				apiBase: pairing.apiBase,
				path: "/auth/verify",
				method: "POST",
				body: authBody
			)
			let nextSession = RemoteSession(
				apiBase: pairing.apiBase,
				token: auth.apiKey,
				email: auth.user.email
			)
			let claimBody = try JSONEncoder().encode([
				"pairingId": pairing.pairingId,
				"code": pairing.code,
				"deviceName": UIDevice.current.name,
			])
			let _: EmptyResponse = try await request(
				apiBase: pairing.apiBase,
				path: "/devices/pairing/claim",
				method: "POST",
				token: nextSession.token,
				body: claimBody
			)
			session = nextSession
			Self.saveSession(nextSession)
			UserDefaults.standard.set(pairing.apiBase.absoluteString, forKey: "accountApiBase")
			signedIn = true
			self.pairing = nil
			self.code = ""
			success = true
			await refreshThreads()
			connect()
		}
		return success
	}

	/// Email login for ASR / account without Mac pairing.
	func signInStandalone(apiBase: URL, email: String, code: String) async -> Bool {
		var success = false
		await perform {
			let authBody = try JSONEncoder().encode([
				"email": email.trimmingCharacters(in: .whitespacesAndNewlines),
				"code": code.trimmingCharacters(in: .whitespacesAndNewlines),
			])
			let auth: AuthVerifyResponse = try await request(
				apiBase: apiBase,
				path: "/auth/verify",
				method: "POST",
				body: authBody
			)
			let nextSession = RemoteSession(
				apiBase: apiBase,
				token: auth.apiKey,
				email: auth.user.email
			)
			session = nextSession
			Self.saveSession(nextSession)
			UserDefaults.standard.set(apiBase.absoluteString, forKey: "accountApiBase")
			self.email = auth.user.email
			signedIn = true
			success = true
		}
		return success
	}

	func requestStandaloneCode(apiBase: URL, email: String) async {
		await perform {
			let body = try JSONEncoder().encode([
				"email": email.trimmingCharacters(in: .whitespacesAndNewlines),
			])
			let _: OkResponse = try await request(
				apiBase: apiBase,
				path: "/auth/request-code",
				method: "POST",
				body: body
			)
		}
	}

	func signOutAccount() {
		session = nil
		signedIn = false
		email = ""
		Self.clearSession()
		disconnect()
	}

	func claimWithExistingSession() async -> Bool {
		guard let pairing, let session, session.apiBase == pairing.apiBase else { return false }
		var success = false
		await perform {
			let claimBody = try JSONEncoder().encode([
				"pairingId": pairing.pairingId,
				"code": pairing.code,
				"deviceName": UIDevice.current.name,
			])
			let _: EmptyResponse = try await request(
				apiBase: pairing.apiBase,
				path: "/devices/pairing/claim",
				method: "POST",
				token: session.token,
				body: claimBody
			)
			self.pairing = nil
			success = true
			await refreshThreads()
			connect()
		}
		return success
	}

	func refreshThreads() async {
		guard let session else { return }
		do {
			let response: ThreadListResponse = try await request(
				apiBase: session.apiBase,
				path: "/remote/threads",
				token: session.token
			)
			threads = response.threads
		} catch {
			self.error = error.localizedDescription
		}
	}

	func createThreadAndSend(_ text: String) async {
		guard let session, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
		await perform {
			let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
			let threadBody = try JSONEncoder().encode([
				"title": String(trimmed.prefix(36)),
				"clientRequestId": UUID().uuidString,
			])
			let thread: RemoteThreadSummary = try await request(
				apiBase: session.apiBase,
				path: "/remote/threads",
				method: "POST",
				token: session.token,
				body: threadBody
			)
			activeThreadId = thread.id
			threads.removeAll { $0.id == thread.id }
			threads.insert(thread, at: 0)
			let turnBody = try JSONEncoder().encode([
				"content": trimmed,
				"clientRequestId": UUID().uuidString,
			])
			let turn: TurnResponse = try await request(
				apiBase: session.apiBase,
				path: "/remote/threads/\(thread.id)/turns",
				method: "POST",
				token: session.token,
				body: turnBody
			)
			turns.append(
				RemoteTurnState(
					id: turn.id,
					threadId: turn.threadId,
					content: turn.content,
					status: RemoteTurnStatus(relayValue: turn.status)
				)
			)
		}
	}

	func selectThread(_ threadId: String) async {
		guard let session else { return }
		await perform {
			let detail: ThreadDetailResponse = try await request(
				apiBase: session.apiBase,
				path: "/remote/threads/\(threadId)",
				token: session.token
			)
			activeThreadId = detail.id
			turns = detail.turns.map {
				RemoteTurnState(
					id: $0.id,
					threadId: $0.threadId,
					content: $0.content,
					status: RemoteTurnStatus(relayValue: $0.status)
				)
			}
		}
	}

	func send(_ text: String) async {
		guard let session else { return }
		guard let threadId = activeThreadId else {
			await createThreadAndSend(text)
			return
		}
		await perform {
			let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
			let turnBody = try JSONEncoder().encode([
				"content": trimmed,
				"clientRequestId": UUID().uuidString,
			])
			let turn: TurnResponse = try await request(
				apiBase: session.apiBase,
				path: "/remote/threads/\(threadId)/turns",
				method: "POST",
				token: session.token,
				body: turnBody
			)
			turns.append(
				RemoteTurnState(
					id: turn.id,
					threadId: turn.threadId,
					content: turn.content,
					status: RemoteTurnStatus(relayValue: turn.status)
				)
			)
		}
	}

	func newThread() {
		activeThreadId = nil
		turns = []
	}

	func respond(to approval: RemoteApproval, option: RemoteApproval.Option) async {
		guard let session else { return }
		await perform {
			let body = try JSONEncoder().encode([
				"decision": option.id,
				"optionId": option.id,
				"requestId": approval.requestId,
				"modality": "click",
			])
			let _: EmptyResponse = try await request(
				apiBase: session.apiBase,
				path: "/remote/approvals/\(approval.id)/respond",
				method: "POST",
				token: session.token,
				body: body
			)
			self.approval = nil
		}
	}

	func disconnect() {
		receiveTask?.cancel()
		receiveTask = nil
		webSocket?.cancel(with: .goingAway, reason: nil)
		webSocket = nil
		macOnline = false
	}

	private func connect() {
		guard let session else { return }
		disconnect()
		var components = URLComponents(url: session.apiBase, resolvingAgainstBaseURL: false)
		components?.scheme = session.apiBase.scheme == "https" ? "wss" : "ws"
		components?.path = "/remote/ws/phone"
		components?.queryItems = [URLQueryItem(name: "token", value: session.token)]
		guard let url = components?.url else { return }
		let task = URLSession.shared.webSocketTask(with: url)
		webSocket = task
		task.resume()
		receiveTask = Task { [weak self] in
			await self?.receiveLoop(task)
		}
	}

	private func receiveLoop(_ task: URLSessionWebSocketTask) async {
		do {
			while !Task.isCancelled {
				let message = try await task.receive()
				let data: Data
				switch message {
				case .data(let value): data = value
				case .string(let value): data = Data(value.utf8)
				@unknown default: continue
				}
				if let frame = try? JSONDecoder().decode(JSONValue.self, from: data) {
					apply(frame)
				}
			}
		} catch {
			if !Task.isCancelled {
				macOnline = false
				self.error = "与 Mac 的连接已断开"
			}
		}
	}

	private func apply(_ frame: JSONValue) {
		guard let object = frame.objectValue, let type = object["type"]?.stringValue else { return }
		switch type {
		case "presence":
			macOnline = object["online"]?.boolValue ?? false
		case "turn.updated":
			guard let turnId = object["turnId"]?.stringValue,
			      let threadId = object["threadId"]?.stringValue,
			      let status = object["status"]?.stringValue
			else { return }
			let state = object["event"]?.objectValue?["payload"]
			if let index = turns.firstIndex(where: { $0.id == turnId }) {
				turns[index].apply(status: status, state: state)
			} else {
				var turn = RemoteTurnState(id: turnId, threadId: threadId, content: "")
				turn.apply(status: status, state: state)
				turns.append(turn)
			}
		case "approval.requested":
			guard let approvalObject = object["approval"]?.objectValue,
			      let approvalId = approvalObject["id"]?.stringValue,
			      let turnId = object["turnId"]?.stringValue,
			      let request = object["request"]?.objectValue
			else { return }
			let options = (request["options"]?.arrayValue ?? []).compactMap { value -> RemoteApproval.Option? in
				guard let option = value.objectValue,
				      let id = option["id"]?.stringValue,
				      let label = option["label"]?.stringValue
				else { return nil }
				return RemoteApproval.Option(id: id, label: label, tone: option["tone"]?.stringValue)
			}
			approval = RemoteApproval(
				id: approvalId,
				turnId: turnId,
				requestId: request["id"]?.stringValue ?? approvalId,
				title: request["title"]?.stringValue ?? "需要确认",
				message: request["message"]?.stringValue ?? "",
				risk: request["risk"]?.stringValue,
				options: options
			)
		default:
			break
		}
	}

	private func perform(_ operation: () async throws -> Void) async {
		isBusy = true
		error = nil
		defer { isBusy = false }
		do {
			try await operation()
		} catch {
			self.error = error.localizedDescription
		}
	}

	private func request<T: Decodable>(
		apiBase: URL,
		path: String,
		method: String = "GET",
		token: String? = nil,
		body: Data? = nil
	) async throws -> T {
		guard let url = URL(string: path, relativeTo: apiBase) else {
			throw RemoteAPIError.response("invalid_url")
		}
		var request = URLRequest(url: url)
		request.httpMethod = method
		request.httpBody = body
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		if let token {
			request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		}
		let (data, response) = try await URLSession.shared.data(for: request)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
		else {
			let code = (try? JSONDecoder().decode(APIErrorBody.self, from: data).error) ?? "request_failed"
			throw RemoteAPIError.response(code)
		}
		if T.self == EmptyResponse.self, data.isEmpty {
			return EmptyResponse() as! T
		}
		return try JSONDecoder().decode(T.self, from: data)
	}

	private static func saveSession(_ session: RemoteSession) {
		guard let data = try? JSONEncoder().encode(session) else { return }
		clearSession()
		SecItemAdd([
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: keychainService,
			kSecAttrAccount: keychainAccount,
			kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
			kSecValueData: data,
		] as CFDictionary, nil)
	}

	private static func loadSession() -> RemoteSession? {
		var result: CFTypeRef?
		let status = SecItemCopyMatching([
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: keychainService,
			kSecAttrAccount: keychainAccount,
			kSecReturnData: true,
			kSecMatchLimit: kSecMatchLimitOne,
		] as CFDictionary, &result)
		guard status == errSecSuccess, let data = result as? Data else { return nil }
		return try? JSONDecoder().decode(RemoteSession.self, from: data)
	}

	private static func clearSession() {
		SecItemDelete([
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: keychainService,
			kSecAttrAccount: keychainAccount,
		] as CFDictionary)
	}
}

private struct EmptyResponse: Decodable {
	init() {}
}

private struct OkResponse: Decodable {
	let ok: Bool?
}
