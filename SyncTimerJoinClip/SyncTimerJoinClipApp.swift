import Foundation
import SwiftUI

@main
struct SyncTimerJoinClipApp: App {
    @State private var joinRequest: JoinRequestV1? = nil

    var body: some Scene {
        WindowGroup {
            JoinClipRootView(
                joinRequest: joinRequest,
                onInstall: { selectedHost in
                    guard var request = joinRequest else { return }
                    if let selectedHost {
                        request.selectedHostUUID = selectedHost
                    }
                    JoinHandoffStore.savePending(request)
                    JoinClipRootView.presentInstallOverlay()
                },
                onSelectHost: { hostUUID in
                    joinRequest?.selectedHostUUID = hostUUID
                }
            )
            .onOpenURL { url in
                ingest(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                ingest(url)
            }
        }
    }

    private func ingest(_ url: URL) {
        let build = currentBuildNumber()
        switch JoinLinkParser.parse(url: url, currentBuild: build) {
        case .success(let request):
            joinRequest = request
        case .failure:
            break
        }
    }

    private func currentBuildNumber() -> Int {
        let bundle = Bundle.main
        if let raw = bundle.infoDictionary?["CFBundleVersion"] as? String,
           let build = Int(raw) {
            return build
        }
        return 0
    }
}
