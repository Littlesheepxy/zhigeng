import XCTest
@testable import ZhigengCore

final class HomeReadyStateTests: XCTestCase {
	func testMissingMicrophoneAndKeyboard() {
		let kind = HomeReadyState.resolve(
			microphoneGranted: false,
			heartbeat: nil,
			sessionActiveUntil: nil,
			sessionModeLabel: nil
		)
		guard case let .setupIncomplete(missing) = kind else {
			return XCTFail("expected setupIncomplete")
		}
		XCTAssertEqual(missing, [.microphone, .keyboard])
	}

	func testFreshFullAccessIsReady() {
		let hb = KeyboardHeartbeat(lastSeenAt: Date().timeIntervalSince1970, hasFullAccess: true)
		let kind = HomeReadyState.resolve(
			microphoneGranted: true,
			heartbeat: hb,
			sessionActiveUntil: nil,
			sessionModeLabel: nil
		)
		XCTAssertEqual(kind, .ready)
	}

	func testStaleHeartbeatDoesNotClaimFullAccessOff() {
		let old = Date().timeIntervalSince1970 - KeyboardHeartbeat.freshWindowSeconds - 10
		let hb = KeyboardHeartbeat(lastSeenAt: old, hasFullAccess: false)
		let kind = HomeReadyState.resolve(
			microphoneGranted: true,
			heartbeat: hb,
			sessionActiveUntil: nil,
			sessionModeLabel: nil,
			keyboardInstalled: false
		)
		guard case let .setupIncomplete(missing) = kind else {
			return XCTFail("expected setupIncomplete for stale heartbeat")
		}
		XCTAssertEqual(missing, [.keyboard])
		XCTAssertFalse(missing.contains(.fullAccess))
	}

	func testInstalledKeyboardWithoutHeartbeatNeedsFullAccessConfirm() {
		let kind = HomeReadyState.resolve(
			microphoneGranted: true,
			heartbeat: nil,
			sessionActiveUntil: nil,
			sessionModeLabel: nil,
			keyboardInstalled: true
		)
		guard case let .setupIncomplete(missing) = kind else {
			return XCTFail("expected setupIncomplete")
		}
		XCTAssertEqual(missing, [.fullAccess])
	}

	func testFreshWithoutFullAccess() {
		let hb = KeyboardHeartbeat(lastSeenAt: Date().timeIntervalSince1970, hasFullAccess: false)
		let kind = HomeReadyState.resolve(
			microphoneGranted: true,
			heartbeat: hb,
			sessionActiveUntil: nil,
			sessionModeLabel: nil,
			keyboardInstalled: true
		)
		guard case let .setupIncomplete(missing) = kind else {
			return XCTFail("expected setupIncomplete")
		}
		XCTAssertEqual(missing, [.fullAccess])
	}

	func testSessionActiveWinsOverReady() {
		let hb = KeyboardHeartbeat(lastSeenAt: Date().timeIntervalSince1970, hasFullAccess: true)
		let until = Date().timeIntervalSince1970 + 900
		let kind = HomeReadyState.resolve(
			microphoneGranted: true,
			heartbeat: hb,
			sessionActiveUntil: until,
			sessionModeLabel: "画中画"
		)
		guard case let .sessionActive(remaining, mode) = kind else {
			return XCTFail("expected sessionActive")
		}
		XCTAssertGreaterThan(remaining, 800)
		XCTAssertEqual(mode, "画中画")
	}
}

final class KeyboardHeartbeatBridgeTests: XCTestCase {
	func testHeartbeatRoundTrip() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zg-hb-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		let bridge = AppGroupBridge(containerOverride: dir)
		let hb = KeyboardHeartbeat(hasFullAccess: true, extensionVersion: "0.1.0")
		try bridge.writeHeartbeat(hb)
		XCTAssertEqual(try bridge.readHeartbeat()?.hasFullAccess, true)
	}
}
