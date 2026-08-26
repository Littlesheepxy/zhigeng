import Testing
@testable import ZhigengCore

@Test func voiceWaveformUsesRealLevelAndSymmetricProfile() {
	#expect(VoiceWaveformMath.normalizedLevel(decibels: -80) == 0)
	#expect(VoiceWaveformMath.normalizedLevel(decibels: 0) == 1)

	let silent = VoiceWaveformMath.barHeights(level: 0, time: 0)
	#expect(silent == Array(repeating: 3, count: 9))

	let speaking = VoiceWaveformMath.barHeights(level: 1, time: 0)
	#expect(speaking[4] > speaking[0])
	#expect(speaking[4] > 3)
}
