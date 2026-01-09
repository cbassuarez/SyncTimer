import Foundation
import SwiftUI
import Combine

final class JoinRouter: ObservableObject {
    @Published private(set) var pending: JoinRequestV1?
    @Published var needsHostPicker: Bool = false
    @Published var updateRequiredMinBuild: Int?

    func ingestUniversalLink(_ url: URL) {
        switch JoinRequestV1.parse(url: url) {
        case .success(let request):
            ingestParsed(request)
        case .failure(let error):
            handleParseFailure(error)
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

    func ingestParsed(_ request: JoinRequestV1) {
        pending = request
        needsHostPicker = request.needsHostSelection
        updateRequiredMinBuild = nil
        JoinHandoffStore.savePending(request)
    }

    func handleParseFailure(_ error: JoinLinkParser.JoinLinkError) {
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
