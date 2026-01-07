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
