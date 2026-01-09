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

    private static func currentBuildNumber() -> Int {
        let bundle = Bundle.main
        if let raw = bundle.infoDictionary?["CFBundleVersion"] as? String,
           let build = Int(raw) {
            return build
        }
        return 0
    }
}
