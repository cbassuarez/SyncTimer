import Foundation

enum JoinHandoffStore {
    static let appGroupID = "group.com.stagedevices.synctimer"

    private static let pendingJSONKey = "synctimer.join.pending_json"
    private static let pendingCreatedAtKey = "synctimer.join.pending_createdAt"
    private static let pendingRequestIdKey = "synctimer.join.pending_requestId"
    private static let pendingSelectedHostKey = "synctimer.join.pending_selectedHostUUID"
    private static let pendingSourceURLKey = "synctimer.join.pending_sourceURL"
    private static let consumedRequestIdsKey = "synctimer.join.consumed_requestIds"
    private static let lastErrorKey = "synctimer.join.last_error"
    private static let lastErrorAtKey = "synctimer.join.last_error_at"

    private static let ttl: TimeInterval = 2 * 60 * 60
    private static let consumedLimit = 10

    private static func store() -> UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func pruneIfExpired(now: Date = .init()) {
        guard let defaults = store() else { return }
        guard let created = defaults.object(forKey: pendingCreatedAtKey) as? TimeInterval else { return }
        if now.timeIntervalSince1970 - created > ttl {
            clearPending(defaults: defaults)
        }
    }

    static func savePending(_ req: JoinRequestV1) {
        guard let defaults = store() else { return }
        guard let data = try? JSONEncoder().encode(req) else { return }
        defaults.set(data, forKey: pendingJSONKey)
        defaults.set(req.createdAt, forKey: pendingCreatedAtKey)
        defaults.set(req.requestId, forKey: pendingRequestIdKey)
        defaults.set(req.selectedHostUUID?.uuidString, forKey: pendingSelectedHostKey)
        defaults.set(req.sourceURL, forKey: pendingSourceURLKey)
    }

    static func loadPending(now: Date = .init()) -> JoinRequestV1? {
        guard let defaults = store() else { return nil }
        guard let data = defaults.data(forKey: pendingJSONKey) else { return nil }
        guard let created = defaults.object(forKey: pendingCreatedAtKey) as? TimeInterval else { return nil }
        guard let requestId = defaults.string(forKey: pendingRequestIdKey) else { return nil }

        if now.timeIntervalSince1970 - created > ttl {
            clearPending(defaults: defaults)
            return nil
        }

        if let consumed = defaults.stringArray(forKey: consumedRequestIdsKey), consumed.contains(requestId) {
            return nil
        }

        guard var req = try? JSONDecoder().decode(JoinRequestV1.self, from: data) else { return nil }
        req.selectedHostUUID = defaults.string(forKey: pendingSelectedHostKey).flatMap { UUID(uuidString: $0) }
        return req
    }

    static func consume(requestId: String) {
        guard let defaults = store() else { return }
        var consumed = defaults.stringArray(forKey: consumedRequestIdsKey) ?? []
        if !consumed.contains(requestId) {
            consumed.append(requestId)
            if consumed.count > consumedLimit {
                consumed = Array(consumed.suffix(consumedLimit))
            }
        }
        defaults.set(consumed, forKey: consumedRequestIdsKey)
        clearPending(defaults: defaults)
    }

    static func updateSelectedHost(_ uuid: UUID, requestId: String) {
        guard let defaults = store() else { return }
        guard defaults.string(forKey: pendingRequestIdKey) == requestId else { return }
        defaults.set(uuid.uuidString, forKey: pendingSelectedHostKey)
        guard let data = defaults.data(forKey: pendingJSONKey), var req = try? JSONDecoder().decode(JoinRequestV1.self, from: data) else { return }
        req.selectedHostUUID = uuid
        if let updated = try? JSONEncoder().encode(req) {
            defaults.set(updated, forKey: pendingJSONKey)
        }
    }

    static func logError(_ message: String) {
        guard let defaults = store() else { return }
        defaults.set(message, forKey: lastErrorKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastErrorAtKey)
    }

    private static func clearPending(defaults: UserDefaults) {
        defaults.removeObject(forKey: pendingJSONKey)
        defaults.removeObject(forKey: pendingCreatedAtKey)
        defaults.removeObject(forKey: pendingRequestIdKey)
        defaults.removeObject(forKey: pendingSelectedHostKey)
        defaults.removeObject(forKey: pendingSourceURLKey)
    }
}
