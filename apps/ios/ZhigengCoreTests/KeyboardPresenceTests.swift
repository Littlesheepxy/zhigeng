import XCTest
@testable import ZhigengCore

final class KeyboardPresenceTests: XCTestCase {
	func testInstalledWhenBundleIdListed() {
		let suite = "zg.keyboard.presence.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suite)!
		defer { defaults.removePersistentDomain(forName: suite) }
		defaults.set(["app.zhigeng.ios.keyboard"], forKey: "AppleKeyboards")
		XCTAssertTrue(KeyboardPresence.isInstalled(defaults: defaults))
	}

	func testNotInstalledWhenEmpty() {
		let suite = "zg.keyboard.presence.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suite)!
		defer { defaults.removePersistentDomain(forName: suite) }
		defaults.set(["com.apple.keyboard"], forKey: "AppleKeyboards")
		XCTAssertFalse(KeyboardPresence.isInstalled(defaults: defaults))
	}
}
