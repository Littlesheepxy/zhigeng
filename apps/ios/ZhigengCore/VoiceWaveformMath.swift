import Foundation

public enum VoiceWaveformMath {
	private static let profile = [0.34, 0.5, 0.72, 0.9, 1, 0.9, 0.72, 0.5, 0.34]
	private static let phase = [0.3, 2.1, 4.4, 1.2, 3.5, 5.2, 2.8, 0.8, 4.9]

	public static func normalizedLevel(decibels: Float) -> Double {
		min(1, max(0, (Double(decibels) + 50) / 50))
	}

	public static func barHeights(level: Double, time: TimeInterval) -> [Double] {
		let level = min(1, max(0, level))
		guard level > 0.008 else { return Array(repeating: 3, count: profile.count) }
		let energy = pow(level, 0.72)
		return profile.indices.map { index in
			let pulse = 0.72 + 0.28 * sin(time * (7.5 + Double(index % 3) * 1.4) + phase[index])
			return 3 + energy * 18 * profile[index] * pulse
		}
	}
}
