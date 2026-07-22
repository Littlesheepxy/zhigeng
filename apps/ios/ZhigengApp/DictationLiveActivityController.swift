import ActivityKit
import Foundation

/// ActivityKit updates are async/nonisolated; keep the handle off the main actor.
final class DictationLiveActivityController: @unchecked Sendable {
	private var activity: Activity<DictationAttributes>?
	private let lock = NSLock()
	private var generation = UUID()

	func start(modeLabel: String, remainingSeconds: Int) {
		guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
		let token = UUID()
		lock.lock()
		generation = token
		let current = activity
		activity = nil
		lock.unlock()

		let attributes = DictationAttributes(
			endsAt: Date().addingTimeInterval(TimeInterval(remainingSeconds)),
			modeLabel: modeLabel
		)
		let state = DictationAttributes.ContentState(
			status: "待命中",
			remainingSeconds: remainingSeconds
		)
		Task {
			if let current {
				await current.end(nil, dismissalPolicy: .immediate)
			}
			// End orphaned cards left by a previous app process.
			for existing in Activity<DictationAttributes>.activities {
				await existing.end(nil, dismissalPolicy: .immediate)
			}
			do {
				let created = try Activity.request(
					attributes: attributes,
					content: .init(state: state, staleDate: attributes.endsAt),
					pushType: nil
				)
				let stillCurrent = lock.withLock {
					guard generation == token else { return false }
					activity = created
					return true
				}
				if !stillCurrent {
					await created.end(nil, dismissalPolicy: .immediate)
				}
			} catch {
				// Live Activity optional — session still works without it.
			}
		}
	}

	func update(status: String, partial: String = "", remainingSeconds: Int) {
		lock.lock()
		let current = activity
		lock.unlock()
		guard let current else { return }
		let state = DictationAttributes.ContentState(
			status: status,
			partial: partial,
			remainingSeconds: remainingSeconds
		)
		Task {
			await current.update(.init(state: state, staleDate: nil))
		}
	}

	func end() {
		lock.lock()
		let current = activity
		activity = nil
		generation = UUID()
		lock.unlock()
		guard let current else { return }
		Task {
			await current.end(nil, dismissalPolicy: .immediate)
		}
	}

	func endOrphanedActivities() {
		Task {
			for existing in Activity<DictationAttributes>.activities {
				await existing.end(nil, dismissalPolicy: .immediate)
			}
		}
	}
}
