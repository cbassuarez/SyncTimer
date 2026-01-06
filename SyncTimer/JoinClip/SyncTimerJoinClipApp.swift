import SwiftUI
import StoreKit

@main
struct SyncTimerJoinClipApp: App {
    @StateObject private var viewModel = JoinClipViewModel()

    var body: some Scene {
        WindowGroup {
            JoinClipRootView(viewModel: viewModel)
                .onOpenURL { url in
                    viewModel.handleIncomingURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        viewModel.handleIncomingURL(url)
                    }
                }
        }
    }
}

final class JoinClipViewModel: ObservableObject {
    @Published var request: JoinRequestV1?

    func handleIncomingURL(_ url: URL) {
        switch JoinLinkParser.parse(url: url, currentBuild: currentBuild()) {
        case .success(let req):
            DispatchQueue.main.async {
                self.request = req
            }
        case .failure:
            break
        }
    }

    func persistAndShowOverlay(selectedHost: UUID?) {
        guard var req = request else { return }
        req.selectedHostUUID = selectedHost
        JoinHandoffStore.savePending(req)
        Task { await showOverlay() }
    }

    @MainActor
    private func showOverlay() async {
        let config = SKOverlay.AppClipConfiguration(position: .bottom)
        await SKOverlay.present(in: .currentScene, configuration: config)
    }

    private func currentBuild() -> Int {
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return Int(version) ?? 0
    }
}
