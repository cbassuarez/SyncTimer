import Foundation

struct Room: Identifiable, Codable, Equatable {
    var id: UUID { hostUUID }
    let createdAt: Date
    var lastUsed: Date
    var label: String
    var hostUUID: UUID
    var connectionMethod: SyncSettings.SyncConnectionMethod
    var role: SyncSettings.Role
    var listenPort: String
    var labelUpdatedAt: Date?
    var isLabelBroadcastEnabled: Bool

    init(label: String,
         hostUUID: UUID,
         connectionMethod: SyncSettings.SyncConnectionMethod,
         role: SyncSettings.Role,
         listenPort: String,
         labelUpdatedAt: Date? = nil,
         isLabelBroadcastEnabled: Bool = true) {
        self.createdAt = Date()
        self.lastUsed = Date()
        self.label = label
        self.hostUUID = hostUUID
        self.connectionMethod = connectionMethod
        self.role = role
        self.listenPort = listenPort
        self.labelUpdatedAt = labelUpdatedAt
        self.isLabelBroadcastEnabled = isLabelBroadcastEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case lastUsed
        case label
        case name
        case hostUUID
        case connectionMethod
        case role
        case listenPort
        case labelUpdatedAt
        case isLabelBroadcastEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsed = try container.decode(Date.self, forKey: .lastUsed)
        if let labelValue = try container.decodeIfPresent(String.self, forKey: .label) {
            label = labelValue
        } else {
            label = try container.decode(String.self, forKey: .name)
        }
        if let uuid = try container.decodeIfPresent(UUID.self, forKey: .hostUUID) {
            hostUUID = uuid
        } else if let raw = try container.decodeIfPresent(String.self, forKey: .hostUUID),
                  let uuid = UUID(uuidString: raw) {
            hostUUID = uuid
        } else if let legacyId = try container.decodeIfPresent(UUID.self, forKey: .id) {
            hostUUID = legacyId
        } else {
            hostUUID = UUID()
        }
        listenPort = try container.decode(String.self, forKey: .listenPort)

        let connectionRaw = try container.decode(String.self, forKey: .connectionMethod)
        connectionMethod = SyncSettings.SyncConnectionMethod(rawValue: connectionRaw) ?? .network

        let roleRaw = try container.decode(String.self, forKey: .role)
        role = roleRaw == "child" ? .child : .parent
        labelUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .labelUpdatedAt)
        isLabelBroadcastEnabled = try container.decodeIfPresent(Bool.self, forKey: .isLabelBroadcastEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastUsed, forKey: .lastUsed)
        try container.encode(label, forKey: .label)
        try container.encode(label, forKey: .name)
        try container.encode(hostUUID, forKey: .hostUUID)
        try container.encode(listenPort, forKey: .listenPort)
        try container.encode(connectionMethod.rawValue, forKey: .connectionMethod)
        try container.encode(role == .child ? "child" : "parent", forKey: .role)
        try container.encodeIfPresent(labelUpdatedAt, forKey: .labelUpdatedAt)
        try container.encode(isLabelBroadcastEnabled, forKey: .isLabelBroadcastEnabled)
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
        rooms = dedupedRooms(from: decoded)
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

    func upsert(hostUUID: UUID,
                label: String,
                connectionMethod: SyncSettings.SyncConnectionMethod,
                role: SyncSettings.Role,
                listenPort: String,
                labelUpdatedAt: Date? = nil,
                isLabelBroadcastEnabled: Bool? = nil) {
        if let idx = rooms.firstIndex(where: { $0.hostUUID == hostUUID }) {
            rooms[idx].label = label
            rooms[idx].connectionMethod = connectionMethod
            rooms[idx].role = role
            rooms[idx].listenPort = listenPort
            if let labelUpdatedAt {
                rooms[idx].labelUpdatedAt = labelUpdatedAt
            }
            if let isLabelBroadcastEnabled {
                rooms[idx].isLabelBroadcastEnabled = isLabelBroadcastEnabled
            }
            save()
            return
        }

        let room = Room(
            label: label,
            hostUUID: hostUUID,
            connectionMethod: connectionMethod,
            role: role,
            listenPort: listenPort,
            labelUpdatedAt: labelUpdatedAt,
            isLabelBroadcastEnabled: isLabelBroadcastEnabled ?? true
        )
        rooms.append(room)
        save()
    }

    func rename(hostUUID: UUID, newLabel: String, updatedAt: Date = Date()) {
        let trimmed = RoomsStore.normalizeLabel(newLabel)
        guard !trimmed.isEmpty else { return }
        if let idx = rooms.firstIndex(where: { $0.hostUUID == hostUUID }) {
            rooms[idx].label = trimmed
            rooms[idx].labelUpdatedAt = updatedAt
            save()
        }
    }

    func delete(_ room: Room) {
        rooms.removeAll { $0.hostUUID == room.hostUUID }
        save()
    }

    func updateLastUsed(_ room: Room) {
        if let idx = rooms.firstIndex(where: { $0.hostUUID == room.hostUUID }) {
            rooms[idx].lastUsed = Date()
            save()
        }
    }

    func room(for hostUUID: UUID) -> Room? {
        rooms.first { $0.hostUUID == hostUUID }
    }

    static func loadRoomLabel(hostUUID: UUID,
                              defaults: UserDefaults = .standard,
                              key: String = "saved_rooms_v1") -> (label: String, isBroadcastEnabled: Bool)? {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Room].self, from: data) else { return nil }
        guard let room = decoded.first(where: { $0.hostUUID == hostUUID }) else { return nil }
        return (room.label, room.isLabelBroadcastEnabled)
    }

    private static func normalizeLabel(_ raw: String) -> String {
        let parts = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dedupedRooms(from rooms: [Room]) -> [Room] {
        var merged: [UUID: Room] = [:]
        for room in rooms {
            if var existing = merged[room.hostUUID] {
                if room.lastUsed > existing.lastUsed {
                    existing = room
                }
                merged[room.hostUUID] = existing
            } else {
                merged[room.hostUUID] = room
            }
        }
        return Array(merged.values)
    }
}

struct ChildSavedRoom: Identifiable, Codable, Equatable {
    enum LabelSource: String, Codable {
        case parent
        case joinLink
        case bonjour
        case legacy
        case unknown
    }

    let id: UUID
    var label: String
    var preferredTransport: SyncSettings.SyncConnectionMethod
    var hostUUID: UUID?
    var peerIP: String?
    var peerPort: String?
    let createdAt: Date
    var lastUsedAt: Date?
    var labelSource: LabelSource
    var previousLabel: String?
    var renamedAt: Date?
    var lastSeenLabelRevision: Int?

    init(label: String,
         preferredTransport: SyncSettings.SyncConnectionMethod,
         hostUUID: UUID? = nil,
         peerIP: String? = nil,
         peerPort: String? = nil) {
        self.id = UUID()
        self.label = label
        self.preferredTransport = preferredTransport
        self.hostUUID = hostUUID
        self.peerIP = peerIP
        self.peerPort = peerPort
        self.createdAt = Date()
        self.lastUsedAt = Date()
        self.labelSource = .unknown
        self.previousLabel = nil
        self.renamedAt = nil
        self.lastSeenLabelRevision = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case preferredTransport
        case hostUUID
        case peerIP
        case peerPort
        case createdAt
        case lastUsedAt
        case labelSource
        case previousLabel
        case renamedAt
        case lastSeenLabelRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        hostUUID = try container.decodeIfPresent(UUID.self, forKey: .hostUUID)
        peerIP = try container.decodeIfPresent(String.self, forKey: .peerIP)
        peerPort = try container.decodeIfPresent(String.self, forKey: .peerPort)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        labelSource = try container.decodeIfPresent(LabelSource.self, forKey: .labelSource) ?? .unknown
        previousLabel = try container.decodeIfPresent(String.self, forKey: .previousLabel)
        renamedAt = try container.decodeIfPresent(Date.self, forKey: .renamedAt)
        lastSeenLabelRevision = try container.decodeIfPresent(Int.self, forKey: .lastSeenLabelRevision)

        let transportRaw = try container.decode(String.self, forKey: .preferredTransport)
        preferredTransport = SyncSettings.SyncConnectionMethod(rawValue: transportRaw) ?? .bluetooth
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(preferredTransport.rawValue, forKey: .preferredTransport)
        try container.encodeIfPresent(hostUUID, forKey: .hostUUID)
        try container.encodeIfPresent(peerIP, forKey: .peerIP)
        try container.encodeIfPresent(peerPort, forKey: .peerPort)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encode(labelSource, forKey: .labelSource)
        try container.encodeIfPresent(previousLabel, forKey: .previousLabel)
        try container.encodeIfPresent(renamedAt, forKey: .renamedAt)
        try container.encodeIfPresent(lastSeenLabelRevision, forKey: .lastSeenLabelRevision)
    }
}

@MainActor
final class ChildRoomsStore: ObservableObject {
    @Published var rooms: [ChildSavedRoom] = []

    private let defaults: UserDefaults
    private let key: String

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
            dedupe()
            print("[ChildRoomsStore] load: decoded \(decoded.count) rooms (bytes \(data.count))")
        } catch {
            print("[ChildRoomsStore] load: decode failed (\(data.count) bytes) error=\(error)")
        }
        #else
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ChildSavedRoom].self, from: data) else { return }
        rooms = decoded
        dedupe()
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
        save()
    }

    func upsert(_ room: ChildSavedRoom) {
        let now = Date()
        if let hostUUID = room.hostUUID {
            if let idx = rooms.firstIndex(where: { $0.hostUUID == hostUUID }) {
                rooms[idx].label = room.label
                rooms[idx].preferredTransport = room.preferredTransport
                rooms[idx].hostUUID = room.hostUUID
                rooms[idx].peerIP = room.peerIP ?? rooms[idx].peerIP
                rooms[idx].peerPort = room.peerPort ?? rooms[idx].peerPort
                rooms[idx].lastUsedAt = now
                save()
                return
            }
        } else if let peerIP = room.peerIP, let peerPort = room.peerPort {
            if let idx = rooms.firstIndex(where: {
                $0.peerIP == peerIP &&
                $0.peerPort == peerPort &&
                $0.preferredTransport == room.preferredTransport
            }) {
                rooms[idx].label = room.label
                rooms[idx].preferredTransport = room.preferredTransport
                rooms[idx].hostUUID = room.hostUUID
                rooms[idx].peerIP = room.peerIP
                rooms[idx].peerPort = room.peerPort
                rooms[idx].lastUsedAt = now
                save()
                return
            }
        }

        var newRoom = room
        newRoom.lastUsedAt = now
        rooms.append(newRoom)
        dedupe()
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

    func upsertConnected(hostUUID: UUID,
                         authoritativeLabel: String?,
                         labelSource: ChildSavedRoom.LabelSource,
                         labelRevision: Int? = nil,
                         preferredTransport: SyncSettings.SyncConnectionMethod,
                         peerIP: String?,
                         peerPort: String?) {
        let now = Date()
        let cleanedLabel = ChildRoomsStore.cleanedLabel(authoritativeLabel)
        if let idx = rooms.firstIndex(where: { $0.hostUUID == hostUUID }) {
            rooms[idx].preferredTransport = preferredTransport
            rooms[idx].peerIP = ChildRoomsStore.cleanedHint(peerIP) ?? rooms[idx].peerIP
            rooms[idx].peerPort = ChildRoomsStore.cleanedHint(peerPort) ?? rooms[idx].peerPort
            rooms[idx].lastUsedAt = now
            if let cleanedLabel {
                let existingNorm = ChildRoomsStore.normalizedLabel(rooms[idx].label)
                let newNorm = ChildRoomsStore.normalizedLabel(cleanedLabel)
                if !newNorm.isEmpty && existingNorm != newNorm {
                    rooms[idx].previousLabel = rooms[idx].label
                    rooms[idx].label = cleanedLabel
                    rooms[idx].renamedAt = now
                    rooms[idx].labelSource = labelSource
                }
            }
            if let labelRevision {
                rooms[idx].lastSeenLabelRevision = labelRevision
            }
            save()
            return
        }

        var room = ChildSavedRoom(
            label: cleanedLabel ?? "Room \(hostUUID.uuidString.suffix(4))",
            preferredTransport: preferredTransport,
            hostUUID: hostUUID,
            peerIP: ChildRoomsStore.cleanedHint(peerIP),
            peerPort: ChildRoomsStore.cleanedHint(peerPort)
        )
        room.labelSource = labelSource
        room.lastSeenLabelRevision = labelRevision
        room.lastUsedAt = now
        rooms.append(room)
        dedupe()
    }

    func dedupe() {
        guard !rooms.isEmpty else { return }
        var merged: [UUID: ChildSavedRoom] = [:]
        var passthrough: [ChildSavedRoom] = []

        for room in rooms {
            guard let hostUUID = room.hostUUID else {
                passthrough.append(room)
                continue
            }
            if let existing = merged[hostUUID] {
                merged[hostUUID] = merge(existing, room)
            } else {
                merged[hostUUID] = room
            }
        }

        let deduped = Array(merged.values) + passthrough
        if deduped != rooms {
            rooms = deduped
            save()
        }
    }

    private func merge(_ lhs: ChildSavedRoom, _ rhs: ChildSavedRoom) -> ChildSavedRoom {
        let lhsDate = lhs.lastUsedAt ?? lhs.createdAt
        let rhsDate = rhs.lastUsedAt ?? rhs.createdAt
        let primary = lhsDate >= rhsDate ? lhs : rhs
        let secondary = lhsDate >= rhsDate ? rhs : lhs
        var merged = primary
        if merged.peerIP == nil || merged.peerIP?.isEmpty == true {
            merged.peerIP = secondary.peerIP
        }
        if merged.peerPort == nil || merged.peerPort?.isEmpty == true {
            merged.peerPort = secondary.peerPort
        }
        if merged.previousLabel == nil {
            merged.previousLabel = secondary.previousLabel
        }
        if merged.renamedAt == nil {
            merged.renamedAt = secondary.renamedAt
        }
        if merged.lastSeenLabelRevision == nil {
            merged.lastSeenLabelRevision = secondary.lastSeenLabelRevision
        }
        if merged.labelSource == .unknown {
            merged.labelSource = secondary.labelSource
        }
        if merged.label.isEmpty {
            merged.label = secondary.label
        }
        return merged
    }

    private static func normalizedLabel(_ raw: String) -> String {
        let parts = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = normalizedLabel(raw)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cleanedHint(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
