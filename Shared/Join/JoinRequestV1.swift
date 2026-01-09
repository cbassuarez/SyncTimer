import Foundation

struct JoinRequestV1: Codable, Equatable {
    let schemaVersion: Int
    let createdAt: TimeInterval
    let requestId: String
    let mode: String
    let transportHint: String?
    let hostUUIDs: [UUID]
    let roomLabel: String?
    let deviceNames: [String]
    let peerIP: String?
    let peerPort: UInt16?
    var selectedHostUUID: UUID?
    let minBuild: Int?
    let sourceURL: String

    var needsHostSelection: Bool {
        hostUUIDs.count > 1 && selectedHostUUID == nil
    }
}

extension JoinRequestV1 {
    static func parse(url: URL, currentBuild: Int? = nil) -> Result<JoinRequestV1, JoinLinkParser.JoinLinkError> {
        let build = currentBuild ?? currentBuildNumber()
        return JoinLinkParser.parse(url: url, currentBuild: build)
    }

    func withMode(_ mode: String) -> JoinRequestV1 {
        JoinRequestV1(
            schemaVersion: schemaVersion,
            createdAt: Date().timeIntervalSince1970,
            requestId: UUID().uuidString,
            mode: mode,
            transportHint: mode == "wifi" ? transportHint : nil,
            hostUUIDs: hostUUIDs,
            roomLabel: roomLabel,
            deviceNames: deviceNames,
            peerIP: peerIP,
            peerPort: peerPort,
            selectedHostUUID: selectedHostUUID,
            minBuild: minBuild,
            sourceURL: sourceURL
        )
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
