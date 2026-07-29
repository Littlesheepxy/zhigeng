import Testing
@testable import ZhigengCore

@Test func asrStreamURLBuildsStreamPath() {
	#expect(
		AsrStreamClient.streamURL(base: "wss://example.com").absoluteString
			== "wss://example.com/asr/stream"
	)
	#expect(
		AsrStreamClient.streamURL(base: "ws://192.168.1.8:3003/").absoluteString
			== "ws://192.168.1.8:3003/asr/stream"
	)
}

@Test func pcm16LittleEndianEncodesSamples() {
	let data = AsrStreamClient.pcm16Data(from: [0, 0.5, -1, 1])
	#expect(data.count == 8)
	let samples = data.withUnsafeBytes { buf -> [Int16] in
		Array(buf.bindMemory(to: Int16.self))
	}
	#expect(samples[0] == 0)
	#expect(samples[1] == 16383 || samples[1] == 16384)
	#expect(samples[2] == -32767)
	#expect(samples[3] == 32767)
}
