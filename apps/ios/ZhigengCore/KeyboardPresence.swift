import Foundation

/// System keyboard list (`AppleKeyboards`). Detects “added”, not Full Access.
public enum KeyboardPresence {
	public static let extensionBundleId = "app.zhigeng.ios.keyboard"

	public static func isInstalled(
		defaults: UserDefaults = .standard,
		bundleId: String = extensionBundleId
	) -> Bool {
		guard let keyboards = defaults.object(forKey: "AppleKeyboards") as? [String]
		else { return false }
		return keyboards.contains { $0 == bundleId || $0.hasPrefix(bundleId + ".") }
	}
}
