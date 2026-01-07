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
