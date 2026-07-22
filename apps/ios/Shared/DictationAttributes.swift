import ActivityKit
import Foundation

struct DictationAttributes: ActivityAttributes {
	public struct ContentState: Codable, Hashable, Sendable {
		var status: String
		var partial: String
		var remainingSeconds: Int

		init(status: String, partial: String = "", remainingSeconds: Int = 0) {
			self.status = status
			self.partial = partial
			self.remainingSeconds = remainingSeconds
		}
	}

	var startedAt: Date
	var endsAt: Date?
	var modeLabel: String

	init(startedAt: Date = Date(), endsAt: Date, modeLabel: String = "待命") {
		self.startedAt = startedAt
		self.endsAt = endsAt
		self.modeLabel = modeLabel
	}
}
