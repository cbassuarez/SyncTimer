import Foundation
import SwiftUI

final class JoinRouter: ObservableObject {
    @Published private(set) var pending: JoinRequestV1?
    @Published var needsHostPicker: Bool = false
    @Published var updateRequiredMinBuild: Int?

    func ingestUniversalLink(_ url: URL) {
        let currentBuild = Self.currentBuildNumber()
        switch JoinLinkParser.parse(url: url, currentBuild: currentBuild) {
        case .success(let request):
            pending = request
            needsHostPicker = request.needsHostSelection
            updateRequiredMinBuild = nil
            JoinHandoffStore.savePending(request)
        case .failure(let error):
            updateRequiredMinBuild = nil
            switch error {
            case .updateRequired(let minBuild):
                updateRequiredMinBuild = minBuild
                JoinHandoffStore.recordLastError("update_required_\(minBuild)")
            default:
                JoinHandoffStore.recordLastError("parse_error_\(error)")
            }
        }
    }

    func ingestAppGroupPendingIfAny() {
        guard pending == nil else { return }
        JoinHandoffStore.pruneIfExpired()
        if let loaded = JoinHandoffStore.loadPending() {
            pending = loaded
            needsHostPicker = loaded.needsHostSelection
        }
    }

    func selectHost(_ hostUUID: UUID) {
        guard var current = pending else { return }
        current.selectedHostUUID = hostUUID
        pending = current
        needsHostPicker = false
        JoinHandoffStore.updateSelectedHost(hostUUID, requestId: current.requestId)
    }

    func markConsumed() {
        guard let request = pending else { return }
        JoinHandoffStore.consume(requestId: request.requestId)
        pending = nil
        needsHostPicker = false
    }

    private static func currentBuildNumber() -> Int {
        let bundle = Bundle.main
        if let raw = bundle.infoDictionary?["CFBundleVersion"] as? String,
           let build = Int(raw) {
            return build
        }
        return 0
    }
}
