import Foundation
import Combine

final class JoinRouter: ObservableObject {
    @Published private(set) var pending: JoinRequestV1?
    @Published var needsHostPicker: Bool = false
    @Published var updateRequiredMinBuild: Int? = nil

    private let currentBuild: Int = {
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return Int(version) ?? 0
    }()

    func ingestUniversalLink(_ url: URL) {
        switch JoinLinkParser.parse(url: url, currentBuild: currentBuild) {
        case .success(let req):
            DispatchQueue.main.async {
                self.pending = req
                self.needsHostPicker = req.needsHostSelection
                self.updateRequiredMinBuild = nil
            }
        case .failure(let err):
            DispatchQueue.main.async {
                if case let .updateRequired(minBuild) = err {
                    self.updateRequiredMinBuild = minBuild
                    self.pending = nil
                    self.needsHostPicker = false
                } else {
                    self.pending = nil
                    self.needsHostPicker = false
                    self.updateRequiredMinBuild = nil
                    JoinHandoffStore.logError("Parse failed: \(err)")
                }
            }
        }
    }

    func ingestAppGroupPendingIfAny() {
        JoinHandoffStore.pruneIfExpired()
        guard pending == nil, let loaded = JoinHandoffStore.loadPending() else { return }
        DispatchQueue.main.async {
            self.pending = loaded
            self.needsHostPicker = loaded.needsHostSelection
        }
    }

    func selectHost(_ uuid: UUID) {
        guard var req = pending else { return }
        req.selectedHostUUID = uuid
        pending = req
        needsHostPicker = false
        JoinHandoffStore.updateSelectedHost(uuid, requestId: req.requestId)
    }

    func markConsumed() {
        guard let req = pending else { return }
        JoinHandoffStore.consume(requestId: req.requestId)
        pending = nil
        needsHostPicker = false
    }
}
