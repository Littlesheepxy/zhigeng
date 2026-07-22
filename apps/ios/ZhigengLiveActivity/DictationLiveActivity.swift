import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ZhigengLiveActivityBundle: WidgetBundle {
	var body: some Widget {
		DictationLiveActivity()
	}
}

struct DictationLiveActivity: Widget {
	var body: some WidgetConfiguration {
		ActivityConfiguration(for: DictationAttributes.self) { context in
			HStack(spacing: 12) {
				robinLogo(size: 36)
				VStack(alignment: .leading, spacing: 4) {
					Text(context.state.status)
						.font(.headline)
					if !context.state.partial.isEmpty {
						Text(context.state.partial)
							.font(.caption)
							.lineLimit(2)
					} else if context.state.remainingSeconds > 0 {
						countdown(context)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				Spacer()
			}
			.padding()
			.activityBackgroundTint(Color(red: 0.404, green: 0.361, blue: 0.945).opacity(0.15))
		} dynamicIsland: { context in
			DynamicIsland {
				DynamicIslandExpandedRegion(.leading) {
					robinLogo(size: 28)
				}
				DynamicIslandExpandedRegion(.center) {
					Text(context.state.status)
				}
				DynamicIslandExpandedRegion(.bottom) {
					if !context.state.partial.isEmpty {
						Text(context.state.partial).lineLimit(2)
					} else if context.state.remainingSeconds > 0 {
						countdown(context)
					}
				}
			} compactLeading: {
				robinLogo(size: 20)
			} compactTrailing: {
				Text(context.state.status).font(.caption2)
			} minimal: {
				robinLogo(size: 18)
			}
		}
	}

	private func countdown(_ context: ActivityViewContext<DictationAttributes>) -> some View {
		let endsAt = context.attributes.endsAt
			?? context.attributes.startedAt.addingTimeInterval(TimeInterval(context.state.remainingSeconds))
		return Text(timerInterval: context.attributes.startedAt...endsAt, countsDown: true)
			.monospacedDigit()
	}

	private func robinLogo(size: CGFloat) -> some View {
		Image("robin")
			.resizable()
			.scaledToFit()
			.frame(width: size, height: size)
			.accessibilityLabel("知更")
	}
}
