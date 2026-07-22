import SwiftUI
import ZhigengCore

@main
struct ZhigengApp: App {
	@State private var store = AppStore()

	init() {
		VolcAsrEngine.prepareEnvironment()
	}

	var body: some Scene {
		WindowGroup {
			RootView(store: store)
				.onOpenURL { url in
					handleDeepLink(url)
				}
		}
	}

	private func handleDeepLink(_ url: URL) {
		guard url.scheme == "zhigeng" else { return }
		store.reloadSharedState()
		switch url.host {
		case "dictate":
			if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
			   let requestId = components.queryItems?.first(where: { $0.name == "requestId" })?.value {
				store.pendingDictationRequestId = requestId
			}
			store.showDictation = true
		case "activate":
			let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
			let requestId = queryItems?.first(where: { $0.name == "requestId" })?.value
			let returnBundleId = queryItems?
				.first(where: { $0.name == "returnBundleID" })?
				.value
			store.activateSessionFromKeyboard(
				requestId: requestId,
				returnBundleId: returnBundleId
			)
		case "history":
			store.selectedTab = .activity
		case "settings":
			store.selectedTab = .me
		case "pair":
			store.remote.preparePairing(url: url)
		default:
			break
		}
	}
}

struct RootView: View {
	@Bindable var store: AppStore
	@Environment(\.scenePhase) private var scenePhase

	var body: some View {
		Group {
			if store.onboardingCompleted {
				MainTabView(store: store)
			} else {
				OnboardingFlow(store: store)
			}
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .active {
				store.reloadSharedState()
			}
		}
		.sheet(
			isPresented: Binding(
				get: { store.remote.pairing != nil },
				set: { if !$0 { store.remote.pairing = nil } }
			)
		) {
			RemotePairingView(remote: store.remote)
		}
	}
}
