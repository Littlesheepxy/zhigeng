import SwiftUI
import UIKit

extension Image {
	static var robin: Image {
		bundledPNG(named: "robin", fallback: "Robin")
	}

	static var brandMist: Image {
		bundledPNG(named: "brand-mist", fallback: "brand-mist")
	}

	static var voiceMist: Image {
		bundledPNG(named: "voice-mist", fallback: "voice-mist")
	}

	private static func bundledPNG(named name: String, fallback: String) -> Image {
		guard let path = Bundle.main.path(forResource: name, ofType: "png"),
		      let image = UIImage(contentsOfFile: path)
		else { return Image(fallback) }
		return Image(uiImage: image)
	}
}

enum Brand {
	static let name = "知更"
	static let tagline = "知你所言，更懂你意。"
	static let taglineFoot = "知更，越用越懂你。"
	static let valueLine = "说得更自然 → 写得更清楚 → 越用越像你"
	static let primary = Color(red: 0.404, green: 0.361, blue: 0.945)
	static let primaryDark = Color(red: 0.337, green: 0.294, blue: 0.839)
	static let canvas = Color(
		UIColor { traits in
			traits.userInterfaceStyle == .dark
				? .systemGroupedBackground
				: UIColor(red: 247 / 255, green: 248 / 255, blue: 252 / 255, alpha: 1)
		}
	)
	static let surface = Color(.secondarySystemGroupedBackground)
	static let cloudWhite = Color(red: 0.984, green: 0.988, blue: 1)
	static let stroke = Color(
		UIColor { traits in
			traits.userInterfaceStyle == .dark
				? .separator
				: UIColor(red: 229 / 255, green: 232 / 255, blue: 239 / 255, alpha: 1)
		}
	)
	static let lavender = Color(red: 0.886, green: 0.867, blue: 1)
	static let iceBlue = Color(red: 0.835, green: 0.945, blue: 1)
	static let mistPink = Color(red: 1, green: 0.886, blue: 0.941)
	static let success = Color(red: 0.157, green: 0.435, blue: 0.271)
	static let reply = Color(red: 0.192, green: 0.467, blue: 0.545)
	static let execute = Color(red: 0.604, green: 0.353, blue: 0.075)
}

struct ZhigengCard<Content: View>: View {
	@ViewBuilder var content: () -> Content

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			content()
		}
		.padding(16)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Brand.surface)
		.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.stroke(Brand.stroke, lineWidth: 1)
		}
	}
}

struct MistBackdrop: View {
	var active = false

	var body: some View {
		GeometryReader { proxy in
			ZStack {
				LinearGradient(
					colors: [
						Color(red: 0.961, green: 0.953, blue: 1),
						Color(red: 0.929, green: 0.965, blue: 1),
						Brand.cloudWhite,
					],
					startPoint: .topLeading,
					endPoint: .bottomTrailing
				)
				Image.brandMist
					.resizable()
					.scaledToFill()
					.frame(width: proxy.size.width, height: proxy.size.height)
					.clipped()
					.opacity(0.58)
				if active {
					Color.green.opacity(0.035)
					}
			}
		}
	}
}

struct BrandHeroMist: View {
	var ready = false

	var body: some View {
		GeometryReader { proxy in
			ZStack(alignment: .top) {
				Brand.cloudWhite
				Image.brandMist
					.resizable()
					.scaledToFill()
					.frame(width: proxy.size.width * 1.36, height: 408)
					.offset(y: -18)
					.hueRotation(.degrees(ready ? -12 : 0))
					.saturation(ready ? 1.05 : 1)
			}
			.frame(width: proxy.size.width, height: 360, alignment: .top)
			.clipped()
			.overlay(alignment: .bottom) {
				LinearGradient(
					colors: [.clear, Brand.cloudWhite],
					startPoint: .top,
					endPoint: .bottom
				)
				.frame(height: 88)
			}
			.frame(maxHeight: .infinity, alignment: .top)
		}
		.allowsHitTesting(false)
	}
}

struct VoiceMistBackdrop: View {
	var body: some View {
		Image.voiceMist
			.resizable()
			.scaledToFill()
			.frame(width: 320, height: 320)
			.opacity(0.95)
			.mask {
				RadialGradient(
					stops: [
						.init(color: .black, location: 0.34),
						.init(color: .clear, location: 0.72),
					],
					center: .center,
					startRadius: 0,
					endRadius: 160
				)
			}
	}
}

struct StatusPill: View {
	let text: String
	var color: Color = Brand.primary

	var body: some View {
		HStack(spacing: 7) {
			Circle()
				.fill(color)
				.frame(width: 7, height: 7)
			Text(text)
				.font(.caption.weight(.semibold))
		}
		.foregroundStyle(color)
		.padding(.horizontal, 11)
		.padding(.vertical, 7)
		.background(Brand.surface.opacity(0.82), in: Capsule())
	}
}

struct PrimaryButton: View {
	var title: String
	var enabled: Bool = true
	var action: () -> Void

	var body: some View {
		Button(action: action) {
			Text(title)
				.font(.body.weight(.semibold))
				.frame(maxWidth: .infinity, minHeight: 50)
				.foregroundStyle(.white)
				.background(Brand.primary, in: Capsule())
		}
		.buttonStyle(.plain)
		.disabled(!enabled)
		.opacity(enabled ? 1 : 0.45)
	}
}

struct SecondaryButton: View {
	var title: String
	var action: () -> Void

	var body: some View {
		Button(action: action) {
			Text(title)
				.font(.body.weight(.medium))
				.frame(maxWidth: .infinity, minHeight: 44)
				.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.foregroundStyle(Brand.primaryDark)
		.overlay {
			Capsule().stroke(Brand.stroke, lineWidth: 1)
		}
	}
}

struct CapabilityChip: View {
	var text: String

	var body: some View {
		Text(text)
			.font(.caption.weight(.medium))
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
			.background(Brand.primary.opacity(0.12))
			.foregroundStyle(Brand.primaryDark)
			.clipShape(Capsule())
	}
}
