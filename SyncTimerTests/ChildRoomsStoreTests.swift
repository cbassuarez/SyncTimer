import Foundation
import Testing
@testable import SyncTimer

struct ChildRoomsStoreTests {
    @Test @MainActor func upsertPersistsAndUpdatesLastUsed() async throws {
        let key = "child_rooms_v1"
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            UserDefaults.standard.removeObject(forKey: key)
        }

        let hostUUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let store = ChildRoomsStore()
        let room = ChildSavedRoom(
            label: "Test Room",
            preferredTransport: .bluetooth,
            hostUUID: hostUUID
        )
        store.upsert(room)
        #expect(store.rooms.count == 1)

        let reloaded = ChildRoomsStore()
        #expect(reloaded.rooms.count == 1)
        #expect(reloaded.rooms[0].label == "Test Room")

        let before = reloaded.rooms[0].lastUsedAt
        try await Task.sleep(nanoseconds: 1_000_000)
        let updatedRoom = ChildSavedRoom(
            label: "Updated Room",
            preferredTransport: .bluetooth,
            hostUUID: hostUUID
        )
        reloaded.upsert(updatedRoom)
        #expect(reloaded.rooms.count == 1)
        #expect(reloaded.rooms[0].label == "Updated Room")
        #expect(reloaded.rooms[0].lastUsedAt != before)
    }
}
