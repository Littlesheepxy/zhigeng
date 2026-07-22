import AVFoundation
import AVKit
import UIKit

/// Keeps the main app process alive via a real Picture-in-Picture window (idle mic off).
@MainActor
final class PictureInPictureSession: NSObject {
	private var player: AVQueuePlayer?
	private var looper: AVPlayerLooper?
	private var playerLayer: AVPlayerLayer?
	private var controller: AVPictureInPictureController?
	private var hostView: UIView?
	private var possibleObservation: NSKeyValueObservation?
	private var startDeadline: Timer?
	private(set) var isActive = false
	var onStopped: (() -> Void)?
	var onStarted: (() -> Void)?
	var onFailed: ((String) -> Void)?

	func start(in hostView: UIView) throws {
		stop()
		guard AVPictureInPictureController.isPictureInPictureSupported() else {
			throw PictureInPictureError.unsupported
		}
		// PiP needs a playback-capable audio session before the player starts.
		let audioSession = AVAudioSession.sharedInstance()
		try? audioSession.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
		try? audioSession.setActive(true)

		let url = try Self.standbyVideoURL()
		let item = AVPlayerItem(url: url)
		let player = AVQueuePlayer(playerItem: item)
		player.isMuted = true
		player.actionAtItemEnd = .none
		let looper = AVPlayerLooper(player: player, templateItem: item)

		let layer = AVPlayerLayer(player: player)
		layer.videoGravity = .resizeAspectFill
		layer.frame = CGRect(x: 0, y: 0, width: 160, height: 90)
		hostView.layer.addSublayer(layer)
		// Must stay on-screen: PiP reports "not possible" for off-screen/hidden layers.
		// Nearly transparent + non-interactive so it doesn't cover the UI.
		hostView.frame = CGRect(x: 0, y: 0, width: 160, height: 90)
		hostView.alpha = 0.02

		let controller = AVPictureInPictureController(playerLayer: layer)
		controller?.delegate = self

		self.player = player
		self.looper = looper
		self.playerLayer = layer
		self.controller = controller
		self.hostView = hostView

		player.play()
		NSLog("[ZG] pip start: possible=\(controller?.isPictureInPicturePossible ?? false)")
		// A blind delayed start fails silently on device; wait until PiP reports possible.
		if controller?.isPictureInPicturePossible == true {
			controller?.startPictureInPicture()
		} else {
			possibleObservation = controller?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, change in
				guard change.newValue == true else { return }
				Task { @MainActor in
					guard let self, !self.isActive else { return }
					NSLog("[ZG] pip became possible, starting")
					self.possibleObservation = nil
					// The mic session reconfigure can pause the player; make sure it runs.
					self.player?.play()
					self.controller?.startPictureInPicture()
				}
			}
		}
		startDeadline = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
			Task { @MainActor in
				guard let self, !self.isActive else { return }
				let possible = self.controller?.isPictureInPicturePossible ?? false
				let rate = self.player?.rate ?? -1
				let itemStatus = self.player?.currentItem?.status.rawValue ?? -1
				self.onFailed?("画中画启动超时（possible=\(possible) rate=\(rate) item=\(itemStatus)）")
			}
		}
	}

	func stop() {
		possibleObservation = nil
		startDeadline?.invalidate()
		startDeadline = nil
		if controller?.isPictureInPictureActive == true {
			controller?.stopPictureInPicture()
		}
		player?.pause()
		playerLayer?.removeFromSuperlayer()
		player = nil
		looper = nil
		playerLayer = nil
		controller = nil
		hostView = nil
		isActive = false
	}

	/// Tiny looping muted solid-color MP4 cached in Caches.
	private static func standbyVideoURL() throws -> URL {
		let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
		let url = dir.appendingPathComponent("zhigeng-pip-standby-v2.mp4")
		if FileManager.default.fileExists(atPath: url.path) { return url }
		try writeStandbyVideo(to: url)
		return url
	}

	/// Doubao-style guidance frame: white card with logo + "请拖到边缘隐藏".
	private static func renderStandbyFrame(size: CGSize) -> UIImage {
		let renderer = UIGraphicsImageRenderer(size: size)
		return renderer.image { ctx in
			UIColor.white.setFill()
			ctx.fill(CGRect(origin: .zero, size: size))

			let logoSide: CGFloat = size.height * 0.34
			if let logo = UIImage(named: "robin") {
				logo.draw(in: CGRect(
					x: (size.width - logoSide) / 2,
					y: size.height * 0.18,
					width: logoSide,
					height: logoSide
				))
			}

			let paragraph = NSMutableParagraphStyle()
			paragraph.alignment = .center
			let title = "请拖到边缘隐藏" as NSString
			let attributes: [NSAttributedString.Key: Any] = [
				.font: UIFont.systemFont(ofSize: size.height * 0.13, weight: .semibold),
				.foregroundColor: UIColor(white: 0.25, alpha: 1),
				.paragraphStyle: paragraph,
			]
			title.draw(
				in: CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.2),
				withAttributes: attributes
			)
		}
	}

	private static func writeStandbyVideo(to url: URL) throws {
		try? FileManager.default.removeItem(at: url)
		let width = 640
		let height = 360
		guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
			throw PictureInPictureError.encodeFailed
		}
		let settings: [String: Any] = [
			AVVideoCodecKey: AVVideoCodecType.h264,
			AVVideoWidthKey: width,
			AVVideoHeightKey: height,
		]
		let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
		input.expectsMediaDataInRealTime = false
		let adaptor = AVAssetWriterInputPixelBufferAdaptor(
			assetWriterInput: input,
			sourcePixelBufferAttributes: [
				kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
				kCVPixelBufferWidthKey as String: width,
				kCVPixelBufferHeightKey as String: height,
			]
		)
		guard writer.canAdd(input) else { throw PictureInPictureError.encodeFailed }
		writer.add(input)
		guard writer.startWriting() else { throw PictureInPictureError.encodeFailed }
		writer.startSession(atSourceTime: .zero)

		guard let cgImage = renderStandbyFrame(size: CGSize(width: width, height: height)).cgImage else {
			throw PictureInPictureError.encodeFailed
		}
		var buffer: CVPixelBuffer?
		CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
		guard let buffer else { throw PictureInPictureError.encodeFailed }
		CVPixelBufferLockBaseAddress(buffer, [])
		if let context = CGContext(
			data: CVPixelBufferGetBaseAddress(buffer),
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
		) {
			context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
		}
		CVPixelBufferUnlockBaseAddress(buffer, [])

		let frameCount = 30
		let fps: Int32 = 15
		for i in 0..<frameCount {
			while !input.isReadyForMoreMediaData {
				Thread.sleep(forTimeInterval: 0.01)
			}
			let time = CMTime(value: CMTimeValue(i), timescale: fps)
			adaptor.append(buffer, withPresentationTime: time)
		}
		input.markAsFinished()
		let semaphore = DispatchSemaphore(value: 0)
		writer.finishWriting { semaphore.signal() }
		semaphore.wait()
		guard writer.status == .completed else { throw PictureInPictureError.encodeFailed }
	}
}

enum PictureInPictureError: LocalizedError {
	case unsupported
	case encodeFailed

	var errorDescription: String? {
		switch self {
		case .unsupported: "此设备不支持画中画"
		case .encodeFailed: "画中画待命视频生成失败"
		}
	}
}

extension PictureInPictureSession: AVPictureInPictureControllerDelegate {
	nonisolated func pictureInPictureControllerDidStartPictureInPicture(
		_ pictureInPictureController: AVPictureInPictureController
	) {
		Task { @MainActor in
			self.isActive = true
			self.startDeadline?.invalidate()
			self.startDeadline = nil
			self.onStarted?()
		}
	}

	nonisolated func pictureInPictureController(
		_ pictureInPictureController: AVPictureInPictureController,
		failedToStartPictureInPictureWithError error: Error
	) {
		Task { @MainActor in
			self.isActive = false
			self.onFailed?(error.localizedDescription)
		}
	}

	nonisolated func pictureInPictureControllerDidStopPictureInPicture(
		_ pictureInPictureController: AVPictureInPictureController
	) {
		Task { @MainActor in
			self.isActive = false
			self.onStopped?()
		}
	}
}
