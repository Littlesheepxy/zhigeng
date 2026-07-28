import AVFoundation
import Combine
import Foundation
import ZhigengCore

/// Shared mic capture: 16 kHz mono PCM for ASR + live level for waveform UI.
/// Supports warm mode (engine stays up; caller gates PCM) for long-lived sessions.
@MainActor
final class AudioCaptureEngine: ObservableObject {
	@Published private(set) var level = 0.0
	@Published private(set) var isRunning = false

	/// When false, PCM callbacks are suppressed but the engine may still run (warm mode).
	nonisolated var feedEnabled: Bool {
		get { tapState.feedEnabled }
		set { tapState.feedEnabled = newValue }
	}

	private var engine: AVAudioEngine?
	private var exclusive = true
	private nonisolated let tapState = AudioTapState()

	func start(onPCM: @escaping (Data) -> Void, onLevel: ((Double) -> Void)? = nil) -> Bool {
		stop()
		configureTapState(onPCM: onPCM, onLevel: onLevel)
		feedEnabled = true
		exclusive = true
		return startEngine()
	}

	/// Keep the mic engine warm without delivering PCM until `feedEnabled = true`.
	/// Standby stays mixable so the user's music keeps playing until we actually record.
	func startWarm(onPCM: @escaping (Data) -> Void, onLevel: ((Double) -> Void)? = nil) -> Bool {
		stop()
		configureTapState(onPCM: onPCM, onLevel: onLevel)
		feedEnabled = false
		exclusive = false
		return startEngine()
	}

	/// Recording takes the session exclusively so other audio (music) is interrupted;
	/// standby returns it to mixable. Re-activating in place keeps the warm engine and
	/// PiP player alive, which a deactivate/reactivate cycle would tear down.
	func setExclusive(_ value: Bool) {
		guard value != exclusive else { return }
		exclusive = value
		try? applySessionCategory()
	}

	/// `deactivateSession: false` keeps the shared AVAudioSession alive so a
	/// coexisting PiP player isn't paused (which would tear down the PiP window).
	func stop(deactivateSession: Bool = true) {
		if let engine {
			engine.inputNode.removeTap(onBus: 0)
			engine.stop()
		}
		engine = nil
		tapState.clear()
		level = 0
		isRunning = false
		feedEnabled = true
		if deactivateSession {
			try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
		}
	}

	private func applySessionCategory() throws {
		let session = AVAudioSession.sharedInstance()
		var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
		if !exclusive {
			options.insert(.mixWithOthers)
		}
		try session.setCategory(.playAndRecord, mode: .measurement, options: options)
		try session.setActive(true)
	}

	private func startEngine() -> Bool {
		do {
			let session = AVAudioSession.sharedInstance()
			try session.setPreferredSampleRate(16_000)
			try applySessionCategory()

			let engine = AVAudioEngine()
			let input = engine.inputNode
			let inputFormat = input.outputFormat(forBus: 0)
			guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { return false }

			let targetFormat = AVAudioFormat(
				commonFormat: .pcmFormatInt16,
				sampleRate: 16_000,
				channels: 1,
				interleaved: true
			)!
			let converter = AVAudioConverter(from: inputFormat, to: targetFormat)

			// The tap block must be built in a nonisolated context: a closure literal formed
			// inside this MainActor method inherits MainActor isolation, and AVFAudio invokes
			// it on the realtime messenger queue -> runtime isolation assert -> SIGTRAP.
			input.installTap(
				onBus: 0,
				bufferSize: 1_024,
				format: inputFormat,
				block: Self.makeTapBlock(
					tapState: tapState,
					converter: converter,
					inputFormat: inputFormat,
					targetFormat: targetFormat
				)
			)

			engine.prepare()
			try engine.start()
			self.engine = engine
			isRunning = true
			return true
		} catch {
			stop()
			return false
		}
	}

	private func configureTapState(onPCM: @escaping (Data) -> Void, onLevel: ((Double) -> Void)?) {
		tapState.configure(
			onPCM: onPCM,
			onLevel: { [weak self] target in
				guard let self else { return }
				let smoothed = self.level + (target - self.level) * (target > self.level ? 0.62 : 0.28)
				let next = smoothed < 0.008 ? 0 : smoothed
				self.level = next
				onLevel?(next)
			}
		)
	}

	private nonisolated static func makeTapBlock(
		tapState: AudioTapState,
		converter: AVAudioConverter?,
		inputFormat: AVAudioFormat,
		targetFormat: AVAudioFormat
	) -> AVAudioNodeTapBlock {
		{ buffer, _ in
			if let target = Self.normalizedLevel(from: buffer) {
				Task { @MainActor in tapState.deliverLevel(target) }
			}
			guard tapState.feedEnabled, let converter else { return }
			let ratio = targetFormat.sampleRate / inputFormat.sampleRate
			let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
			guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else { return }
			var error: NSError?
			// Safe: the converter consumes the block synchronously within this tap callback.
			nonisolated(unsafe) let inputBuffer = buffer
			nonisolated(unsafe) var inputConsumed = false
			let inputBlock: AVAudioConverterInputBlock = { _, status in
				guard !inputConsumed else {
					status.pointee = .noDataNow
					return nil
				}
				inputConsumed = true
				status.pointee = .haveData
				return inputBuffer
			}
			converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
			guard error == nil, outBuffer.frameLength > 0,
			      let channels = outBuffer.int16ChannelData else { return }
			let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
			let data = Data(bytes: channels[0], count: byteCount)
			Task { @MainActor in
				guard tapState.feedEnabled else { return }
				tapState.deliverPCM(data)
			}
		}
	}

	private nonisolated static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double? {
		guard let channel = buffer.floatChannelData?[0] else { return nil }
		let count = Int(buffer.frameLength)
		guard count > 0 else { return nil }
		var sum = Float.zero
		for index in 0..<count {
			sum += channel[index] * channel[index]
		}
		let rms = sqrt(sum / Float(count))
		let decibels = 20 * log10(max(rms, 0.0001))
		return VoiceWaveformMath.normalizedLevel(decibels: decibels)
	}
}

private final class AudioTapState: @unchecked Sendable {
	private let lock = NSLock()
	private var feeding = true
	private var onPCM: ((Data) -> Void)?
	private var onLevel: ((Double) -> Void)?

	var feedEnabled: Bool {
		get { lock.withLock { feeding } }
		set { lock.withLock { feeding = newValue } }
	}

	@MainActor
	func configure(onPCM: @escaping (Data) -> Void, onLevel: @escaping (Double) -> Void) {
		self.onPCM = onPCM
		self.onLevel = onLevel
	}

	@MainActor
	func clear() {
		onPCM = nil
		onLevel = nil
	}

	@MainActor
	func deliverPCM(_ data: Data) {
		onPCM?(data)
	}

	@MainActor
	func deliverLevel(_ value: Double) {
		onLevel?(value)
	}
}
