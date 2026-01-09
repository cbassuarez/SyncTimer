import Foundation

struct Room: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
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

struct ChildSavedRoom: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var preferredTransport: SyncSettings.SyncConnectionMethod
    var hostUUID: UUID?
    var peerIP: String?
    var peerPort: String?
    let createdAt: Date
    var lastUsedAt: Date?

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
    }
}

@MainActor
final class ChildRoomsStore: ObservableObject {
    @Published var rooms: [ChildSavedRoom] = []

    private let key = "child_rooms_v1"

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ChildSavedRoom].self, from: data) else { return }
        rooms = decoded
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(rooms) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    func add(_ room: ChildSavedRoom) {
        rooms.append(room)
        save()
    }

    func upsert(_ room: ChildSavedRoom) {
        let now = Date()
        if let idx = rooms.firstIndex(where: { matches($0, room) }) {
            rooms[idx].label = room.label
            rooms[idx].preferredTransport = room.preferredTransport
            rooms[idx].hostUUID = room.hostUUID
            rooms[idx].peerIP = room.peerIP
            rooms[idx].peerPort = room.peerPort
            rooms[idx].lastUsedAt = now
            save()
            return
        }
        var newRoom = room
        newRoom.lastUsedAt = now
        rooms.append(newRoom)
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

    private func matches(_ lhs: ChildSavedRoom, _ rhs: ChildSavedRoom) -> Bool {
        if let lhsHost = lhs.hostUUID, let rhsHost = rhs.hostUUID {
            return lhsHost == rhsHost && lhs.preferredTransport == rhs.preferredTransport
        }
        if lhs.hostUUID != nil || rhs.hostUUID != nil {
            return false
        }
        guard let lhsIP = lhs.peerIP,
              let lhsPort = lhs.peerPort,
              let rhsIP = rhs.peerIP,
              let rhsPort = rhs.peerPort else {
            return false
        }
        return lhsIP == rhsIP
            && lhsPort == rhsPort
            && lhs.preferredTransport == rhs.preferredTransport
    }
}
