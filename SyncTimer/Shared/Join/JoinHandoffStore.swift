import Foundation

enum JoinHandoffStore {
    private static let appGroupID = "group.com.stagedevices.synctimer"
    private static let pendingTTL: TimeInterval = 60 * 60 * 2

    private enum Key {
        static let pendingJSON = "synctimer.join.pending_json"
        static let pendingCreatedAt = "synctimer.join.pending_createdAt"
        static let pendingRequestId = "synctimer.join.pending_requestId"
        static let pendingSelectedHostUUID = "synctimer.join.pending_selectedHostUUID"
        static let pendingSourceURL = "synctimer.join.pending_sourceURL"
        static let consumedRequestIds = "synctimer.join.consumed_requestIds"
        static let lastError = "synctimer.join.last_error"
        static let lastErrorAt = "synctimer.join.last_error_at"
    }

    static func pruneIfExpired(now: Date = .init()) {
        let defaults = defaultsStore()
        guard let createdAt = defaults.object(forKey: Key.pendingCreatedAt) as? Double else {
            return
        }
        if now.timeIntervalSince1970 - createdAt > pendingTTL {
            clearPending(defaults)
        }
    }

    static func savePending(_ request: JoinRequestV1) {
        let defaults = defaultsStore()
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(request) else { return }
        defaults.set(data, forKey: Key.pendingJSON)
        defaults.set(request.createdAt, forKey: Key.pendingCreatedAt)
        defaults.set(request.requestId, forKey: Key.pendingRequestId)
        if let selected = request.selectedHostUUID {
            defaults.set(selected.uuidString, forKey: Key.pendingSelectedHostUUID)
        } else {
            defaults.removeObject(forKey: Key.pendingSelectedHostUUID)
        }
        defaults.set(request.sourceURL, forKey: Key.pendingSourceURL)
    }

    static func loadPending(now: Date = .init()) -> JoinRequestV1? {
        let defaults = defaultsStore()
        pruneIfExpired(now: now)
        guard let data = defaults.data(forKey: Key.pendingJSON),
              let requestId = defaults.string(forKey: Key.pendingRequestId) else {
            return nil
        }
        let decoder = JSONDecoder()
        guard var request = try? decoder.decode(JoinRequestV1.self, from: data) else {
            return nil
        }
        if isConsumed(requestId: requestId) {
            return nil
        }
        if let selected = defaults.string(forKey: Key.pendingSelectedHostUUID),
           let selectedUUID = UUID(uuidString: selected) {
            request.selectedHostUUID = selectedUUID
        }
        return request
    }

    static func consume(requestId: String) {
        let defaults = defaultsStore()
        var consumed = defaults.stringArray(forKey: Key.consumedRequestIds) ?? []
        if !consumed.contains(requestId) {
            consumed.append(requestId)
        }
        if consumed.count > 10 {
            consumed = Array(consumed.suffix(10))
        }
        defaults.set(consumed, forKey: Key.consumedRequestIds)
        clearPending(defaults)
    }

    static func updateSelectedHost(_ selectedHost: UUID, requestId: String) {
        let defaults = defaultsStore()
        guard defaults.string(forKey: Key.pendingRequestId) == requestId,
              let data = defaults.data(forKey: Key.pendingJSON),
              var request = try? JSONDecoder().decode(JoinRequestV1.self, from: data) else {
            return
        }
        request.selectedHostUUID = selectedHost
        if let updated = try? JSONEncoder().encode(request) {
            defaults.set(updated, forKey: Key.pendingJSON)
        }
        defaults.set(selectedHost.uuidString, forKey: Key.pendingSelectedHostUUID)
    }

    static func recordLastError(_ message: String, now: Date = .init()) {
        let defaults = defaultsStore()
        defaults.set(message, forKey: Key.lastError)
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastErrorAt)
    }

    static func defaultsStore() -> UserDefaults {
        return UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func clearAll() {
        let defaults = defaultsStore()
        clearPending(defaults)
        defaults.removeObject(forKey: Key.consumedRequestIds)
        defaults.removeObject(forKey: Key.lastError)
        defaults.removeObject(forKey: Key.lastErrorAt)
    }

    private static func isConsumed(requestId: String) -> Bool {
        let defaults = defaultsStore()
        let consumed = defaults.stringArray(forKey: Key.consumedRequestIds) ?? []
        return consumed.contains(requestId)
    }

    private static func clearPending(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: Key.pendingJSON)
        defaults.removeObject(forKey: Key.pendingCreatedAt)
        defaults.removeObject(forKey: Key.pendingRequestId)
        defaults.removeObject(forKey: Key.pendingSelectedHostUUID)
        defaults.removeObject(forKey: Key.pendingSourceURL)
    }
}
