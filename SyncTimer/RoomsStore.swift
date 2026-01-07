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
