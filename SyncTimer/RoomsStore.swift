import Foundation

struct Room: Identifiable, Codable, Equatable {
    let id: UUID
    var createdAt: Date
    var lastUsed: Date
    var name: String
    var hostUUID: String
    var connectionMethod: SyncSettings.SyncConnectionMethod
    var role: SyncSettings.Role
    var listenPort: String

    init(name: String,
         hostUUID: String,
         connectionMethod: SyncSettings.SyncConnectionMethod,
         role: SyncSettings.Role,
         listenPort: String) {
        self.id = UUID()
        self.createdAt = Date()
        self.lastUsed = Date()
        self.name = name
        self.hostUUID = hostUUID
        self.connectionMethod = connectionMethod
        self.role = role
        self.listenPort = listenPort
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case lastUsed
        case name
        case hostUUID
        case connectionMethod
        case role
        case listenPort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsed = try container.decode(Date.self, forKey: .lastUsed)
        name = try container.decode(String.self, forKey: .name)
        hostUUID = try container.decode(String.self, forKey: .hostUUID)
        listenPort = try container.decode(String.self, forKey: .listenPort)

        let connectionRaw = try container.decode(String.self, forKey: .connectionMethod)
        connectionMethod = SyncSettings.SyncConnectionMethod(rawValue: connectionRaw) ?? .network

        let roleRaw = try container.decode(String.self, forKey: .role)
        role = roleRaw == "child" ? .child : .parent
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastUsed, forKey: .lastUsed)
        try container.encode(name, forKey: .name)
        try container.encode(hostUUID, forKey: .hostUUID)
        try container.encode(listenPort, forKey: .listenPort)
        try container.encode(connectionMethod.rawValue, forKey: .connectionMethod)
        try container.encode(role == .child ? "child" : "parent", forKey: .role)
    }
}

@MainActor
final class RoomsStore: ObservableObject {
    @Published var rooms: [Room] = []

    private let key = "saved_rooms_v1"

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Room].self, from: data) else { return }
        rooms = decoded
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(rooms) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    func add(_ room: Room) {
        rooms.append(room)
        save()
    }

    func delete(_ room: Room) {
        rooms.removeAll { $0.id == room.id }
        save()
    }

    func updateLastUsed(_ room: Room) {
        if let idx = rooms.firstIndex(of: room) {
            rooms[idx].lastUsed = Date()
            save()
        }
    }
}

enum RoomTransport: String, Codable, Hashable {
    case wifi
    case nearby

    init(connectionMethod: SyncSettings.SyncConnectionMethod) {
        switch connectionMethod {
        case .network, .bonjour:
            self = .wifi
        case .bluetooth:
            self = .nearby
        }
    }

    init(joinMode: String) {
        switch joinMode {
        case "wifi":
            self = .wifi
        case "nearby", "bluetooth":
            self = .nearby
        default:
            self = .nearby
        }
    }
}

enum RoomLabelRenamedSource: String, Codable, Hashable {
    case user
    case remote
    case merge
}

struct RoomKey: Codable, Hashable, Equatable {
    enum Kind: Hashable, Codable {
        case host(UUID)
        case direct(peerIP: String, peerPort: UInt16)
    }

    let transport: RoomTransport
    let kind: Kind

    static func host(transport: RoomTransport, hostUUID: UUID) -> RoomKey {
        RoomKey(transport: transport, kind: .host(hostUUID))
    }

    static func direct(transport: RoomTransport, peerIP: String, peerPort: UInt16) -> RoomKey {
        RoomKey(transport: transport, kind: .direct(peerIP: peerIP, peerPort: peerPort))
    }

    private enum CodingKeys: String, CodingKey {
        case transport
        case kind
        case hostUUID
        case peerIP
        case peerPort
    }

    private enum KindType: String, Codable {
        case host
        case direct
    }

    init(transport: RoomTransport, kind: Kind) {
        self.transport = transport
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transport = try container.decode(RoomTransport.self, forKey: .transport)
        let kindType = try container.decode(KindType.self, forKey: .kind)
        switch kindType {
        case .host:
            let hostUUID = try container.decode(UUID.self, forKey: .hostUUID)
            kind = .host(hostUUID)
        case .direct:
            let peerIP = try container.decode(String.self, forKey: .peerIP)
            let peerPort = try container.decode(UInt16.self, forKey: .peerPort)
            kind = .direct(peerIP: peerIP, peerPort: peerPort)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transport, forKey: .transport)
        switch kind {
        case .host(let hostUUID):
            try container.encode(KindType.host, forKey: .kind)
            try container.encode(hostUUID, forKey: .hostUUID)
        case .direct(let peerIP, let peerPort):
            try container.encode(KindType.direct, forKey: .kind)
            try container.encode(peerIP, forKey: .peerIP)
            try container.encode(peerPort, forKey: .peerPort)
        }
    }
}

extension RoomKey {
    var hostUUID: UUID? {
        if case .host(let hostUUID) = kind {
            return hostUUID
        }
        return nil
    }

    var peerIP: String? {
        if case .direct(let peerIP, _) = kind {
            return peerIP
        }
        return nil
    }

    var peerPort: UInt16? {
        if case .direct(_, let peerPort) = kind {
            return peerPort
        }
        return nil
    }

    var peerPortString: String? {
        peerPort.map { String($0) }
    }
}

struct ChildSavedRoom: Identifiable, Codable, Equatable {
    let id: UUID
    var userLabel: String?
    var observedLabel: String?
    var preferredTransport: SyncSettings.SyncConnectionMethod
    var hostUUID: UUID?
    var peerIP: String?
    var peerPort: String?
    var createdAt: Date
    var lastUsedAt: Date?
    var lastObservedLabelChangeAt: Date?
    var lastRenamedSource: RoomLabelRenamedSource?
    var showRenamedBadgeUntil: Date?

    init(userLabel: String? = nil,
         observedLabel: String? = nil,
         preferredTransport: SyncSettings.SyncConnectionMethod,
         hostUUID: UUID? = nil,
         peerIP: String? = nil,
         peerPort: String? = nil,
         createdAt: Date = Date(),
         lastUsedAt: Date? = Date(),
         lastObservedLabelChangeAt: Date? = nil,
         lastRenamedSource: RoomLabelRenamedSource? = nil,
         showRenamedBadgeUntil: Date? = nil) {
        self.id = UUID()
        self.userLabel = userLabel
        self.observedLabel = observedLabel
        self.preferredTransport = preferredTransport
        self.hostUUID = hostUUID
        self.peerIP = peerIP
        self.peerPort = peerPort
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.lastObservedLabelChangeAt = lastObservedLabelChangeAt
        self.lastRenamedSource = lastRenamedSource
        self.showRenamedBadgeUntil = showRenamedBadgeUntil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case userLabel
        case observedLabel
        case preferredTransport
        case hostUUID
        case peerIP
        case peerPort
        case createdAt
        case lastUsedAt
        case lastObservedLabelChangeAt
        case lastRenamedSource
        case showRenamedBadgeUntil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let legacyLabel = try container.decodeIfPresent(String.self, forKey: .label)
        userLabel = try container.decodeIfPresent(String.self, forKey: .userLabel) ?? legacyLabel
        observedLabel = try container.decodeIfPresent(String.self, forKey: .observedLabel)
        hostUUID = try container.decodeIfPresent(UUID.self, forKey: .hostUUID)
        peerIP = try container.decodeIfPresent(String.self, forKey: .peerIP)
        peerPort = try container.decodeIfPresent(String.self, forKey: .peerPort)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        lastObservedLabelChangeAt = try container.decodeIfPresent(Date.self, forKey: .lastObservedLabelChangeAt)
        lastRenamedSource = try container.decodeIfPresent(RoomLabelRenamedSource.self, forKey: .lastRenamedSource)
        showRenamedBadgeUntil = try container.decodeIfPresent(Date.self, forKey: .showRenamedBadgeUntil)

        let transportRaw = try container.decode(String.self, forKey: .preferredTransport)
        let decoded = SyncSettings.SyncConnectionMethod(rawValue: transportRaw) ?? .bluetooth
        preferredTransport = (decoded == .bonjour) ? .network : decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(userLabel, forKey: .userLabel)
        try container.encodeIfPresent(observedLabel, forKey: .observedLabel)
        try container.encode(preferredTransport.rawValue, forKey: .preferredTransport)
        try container.encodeIfPresent(hostUUID, forKey: .hostUUID)
        try container.encodeIfPresent(peerIP, forKey: .peerIP)
        try container.encodeIfPresent(peerPort, forKey: .peerPort)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encodeIfPresent(lastObservedLabelChangeAt, forKey: .lastObservedLabelChangeAt)
        try container.encodeIfPresent(lastRenamedSource, forKey: .lastRenamedSource)
        try container.encodeIfPresent(showRenamedBadgeUntil, forKey: .showRenamedBadgeUntil)
    }
}

extension ChildSavedRoom {
    var effectiveLabel: String {
        if let userLabel, !userLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return userLabel
        }
        if let observedLabel, !observedLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return observedLabel
        }
        return fallbackLabel
    }

    var fallbackLabel: String {
        if let hostUUID {
            return "Room \(hostUUID.uuidString.suffix(4))"
        }
        if let peerIP, let peerPort {
            return "Wi-Fi \(peerIP):\(peerPort)"
        }
        return "Room"
    }

    var roomKey: RoomKey? {
        RoomKey.fromSavedRoom(self)
    }

    func shouldShowRenamedBadge(now: Date = Date()) -> Bool {
        guard userLabel == nil,
              lastRenamedSource == .remote,
              let showUntil = showRenamedBadgeUntil else {
            return false
        }
        return now < showUntil
    }
}

extension RoomKey {
    static func fromJoinRequest(_ request: JoinRequestV1) -> RoomKey? {
        if request.needsHostSelection {
            return nil
        }
        let transport = RoomTransport(joinMode: request.mode)
        if let hostUUID = request.selectedHostUUID ?? (request.hostUUIDs.count == 1 ? request.hostUUIDs.first : nil) {
            return .host(transport: transport, hostUUID: hostUUID)
        }
        if let peerIP = request.peerIP, let peerPort = request.peerPort {
            return .direct(transport: transport, peerIP: peerIP, peerPort: peerPort)
        }
        return nil
    }

    static func fromLegacyRequest(_ request: HostJoinRequestV1,
                                  transport: SyncSettings.SyncConnectionMethod) -> RoomKey {
        .host(transport: RoomTransport(connectionMethod: transport), hostUUID: request.hostUUID)
    }

    static func fromSavedRoom(_ room: ChildSavedRoom) -> RoomKey? {
        let transport = RoomTransport(connectionMethod: room.preferredTransport)
        if let hostUUID = room.hostUUID {
            return .host(transport: transport, hostUUID: hostUUID)
        }
        if let peerIP = room.peerIP,
           let peerPortString = room.peerPort,
           let peerPort = UInt16(peerPortString) {
            return .direct(transport: transport, peerIP: peerIP, peerPort: peerPort)
        }
        return nil
    }
}

@MainActor
final class ChildRoomsStore: ObservableObject {
    @Published var rooms: [ChildSavedRoom] = []

    private let defaults: UserDefaults
    private let key: String
    private let renamedBadgeTTL: TimeInterval = 60 * 60 * 24

    init(defaults: UserDefaults = .standard, key: String = "child_rooms_v1") {
        self.defaults = defaults
        self.key = key
        load()
    }

    func load() {
        #if DEBUG
        guard let data = defaults.data(forKey: key) else {
            print("[ChildRoomsStore] load: no data for key '\(key)'")
            return
        }
        do {
            let decoded = try JSONDecoder().decode([ChildSavedRoom].self, from: data)
            rooms = decoded
            dedupeAndMerge()
            save()
            print("[ChildRoomsStore] load: decoded \(decoded.count) rooms (bytes \(data.count))")
        } catch {
            print("[ChildRoomsStore] load: decode failed (\(data.count) bytes) error=\(error)")
        }
        #else
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ChildSavedRoom].self, from: data) else { return }
        rooms = decoded
        dedupeAndMerge()
        save()
        #endif
    }

    func save() {
        #if DEBUG
        do {
            let encoded = try JSONEncoder().encode(rooms)
            defaults.set(encoded, forKey: key)
            print("[ChildRoomsStore] save: saved \(rooms.count) rooms (bytes \(encoded.count)) to key '\(key)'")
        } catch {
            print("[ChildRoomsStore] save: encode failed error=\(error)")
        }
        #else
        if let encoded = try? JSONEncoder().encode(rooms) {
            defaults.set(encoded, forKey: key)
        }
        #endif
    }

    func add(_ room: ChildSavedRoom) {
        rooms.append(room)
        dedupeAndMerge()
        save()
    }

    func renameRoom(key: RoomKey, to newLabel: String) {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dedupeAndMerge()
        guard let idx = firstIndex(for: key) else { return }
        rooms[idx].userLabel = trimmed
        rooms[idx].lastRenamedSource = .user
        rooms[idx].showRenamedBadgeUntil = nil
        rooms[idx].lastUsedAt = Date()
        save()
    }

    func clearUserLabel(key: RoomKey) {
        dedupeAndMerge()
        guard let idx = firstIndex(for: key) else { return }
        rooms[idx].userLabel = nil
        rooms[idx].lastRenamedSource = .user
        rooms[idx].showRenamedBadgeUntil = nil
        save()
    }

    func upsertObservedRoom(key: RoomKey, observedLabel: String?, source: RoomLabelRenamedSource = .remote) {
        let now = Date()
        let normalizedLabel = observedLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedLabel = (normalizedLabel?.isEmpty == true) ? nil : normalizedLabel

        dedupeAndMerge()
        if let idx = firstIndex(for: key) {
            let existingLabel = rooms[idx].observedLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            if existingLabel != cleanedLabel {
                rooms[idx].observedLabel = cleanedLabel
                rooms[idx].lastObservedLabelChangeAt = now
                if rooms[idx].userLabel == nil {
                    rooms[idx].lastRenamedSource = source
                    rooms[idx].showRenamedBadgeUntil = now.addingTimeInterval(renamedBadgeTTL)
                }
            }
            rooms[idx].lastUsedAt = now
            dedupeAndMerge()
            save()
            return
        }

        let newRoom = ChildSavedRoom(
            userLabel: nil,
            observedLabel: cleanedLabel,
            preferredTransport: key.transport == .wifi ? .network : .bluetooth,
            hostUUID: key.hostUUID,
            peerIP: key.peerIP,
            peerPort: key.peerPortString,
            createdAt: now,
            lastUsedAt: now,
            lastObservedLabelChangeAt: cleanedLabel == nil ? nil : now
        )
        rooms.append(newRoom)
        dedupeAndMerge()
        save()
    }

    func delete(_ room: ChildSavedRoom) {
        rooms.removeAll { $0.id == room.id }
        save()
    }

    func updateLastUsed(_ room: ChildSavedRoom) {
        if let idx = rooms.firstIndex(of: room) {
            rooms[idx].lastUsedAt = Date()
            save()
        }
    }

    func dedupeAndMerge() {
        var grouped: [RoomKey: [ChildSavedRoom]] = [:]
        var unkeyed: [ChildSavedRoom] = []
        for room in rooms {
            guard let key = room.roomKey else {
                unkeyed.append(room)
                continue
            }
            grouped[key, default: []].append(room)
        }

        var merged: [ChildSavedRoom] = []
        for (key, candidates) in grouped {
            if candidates.count == 1, let room = candidates.first {
                merged.append(room)
                continue
            }
            let winner = selectMergeWinner(candidates)
            let mergedRoom = mergeRooms(candidates, winner: winner, key: key)
            merged.append(mergedRoom)
        }

        rooms = merged + unkeyed
    }

    private func selectMergeWinner(_ rooms: [ChildSavedRoom]) -> ChildSavedRoom {
        return rooms.sorted { lhs, rhs in
            let lhsHasUser = lhs.userLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let rhsHasUser = rhs.userLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            if lhsHasUser != rhsHasUser {
                return lhsHasUser && !rhsHasUser
            }
            let lhsUsed = lhs.lastUsedAt ?? .distantPast
            let rhsUsed = rhs.lastUsedAt ?? .distantPast
            if lhsUsed != rhsUsed {
                return lhsUsed > rhsUsed
            }
            return lhs.createdAt > rhs.createdAt
        }.first!
    }

    private func mergeRooms(_ rooms: [ChildSavedRoom], winner: ChildSavedRoom, key: RoomKey) -> ChildSavedRoom {
        let now = Date()
        var merged = winner
        let mostRecentObserved = rooms
            .filter { $0.observedLabel != nil }
            .sorted {
                let lhsDate = $0.lastObservedLabelChangeAt ?? .distantPast
                let rhsDate = $1.lastObservedLabelChangeAt ?? .distantPast
                return lhsDate > rhsDate
            }
            .first

        if let observed = mostRecentObserved {
            merged.observedLabel = observed.observedLabel
            merged.lastObservedLabelChangeAt = observed.lastObservedLabelChangeAt
        }

        merged.lastUsedAt = rooms.map { $0.lastUsedAt ?? .distantPast }.max()
        merged.createdAt = rooms.map(\.createdAt).min() ?? merged.createdAt

        if merged.userLabel == nil {
            let futureBadge = rooms
                .compactMap { $0.showRenamedBadgeUntil }
                .filter { $0 > now }
                .max()
            merged.showRenamedBadgeUntil = futureBadge
        } else {
            merged.showRenamedBadgeUntil = nil
        }

        if rooms.count > 1 {
            merged.lastRenamedSource = .merge
            merged.showRenamedBadgeUntil = nil
        }

        merged.preferredTransport = key.transport == .wifi ? .network : .bluetooth
        merged.hostUUID = key.hostUUID
        merged.peerIP = key.peerIP
        merged.peerPort = key.peerPortString
        return merged
    }

    private func firstIndex(for key: RoomKey) -> Int? {
        rooms.firstIndex(where: { $0.roomKey == key })
    }
}
