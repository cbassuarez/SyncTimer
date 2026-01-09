import Foundation
import Testing
@testable import SyncTimer

struct ChildRoomsStoreTests {
    @Test func testChildRoomsStorePersistsAcrossInit() async throws {
        let suiteName = "ChildRoomsStoreTests.persist.\(UUID().uuidString)"
        let key = "test_child_rooms"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(false, "Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let hostUUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let room = ChildSavedRoom(
            label: "Persisted Room",
            preferredTransport: .network,
            hostUUID: hostUUID,
            peerIP: "10.0.0.1",
            peerPort: "5000"
        )

        let store = await MainActor.run { ChildRoomsStore(defaults: defaults, key: key) }
        await MainActor.run { store.upsert(room) }

        let reloaded = await MainActor.run { ChildRoomsStore(defaults: defaults, key: key) }
        let rooms = await MainActor.run { reloaded.rooms }

        #expect(rooms.count == 1)
        #expect(rooms.first?.label == "Persisted Room")
        #expect(rooms.first?.hostUUID == hostUUID)
        #expect(rooms.first?.peerIP == "10.0.0.1")
        #expect(rooms.first?.peerPort == "5000")
    }

    @Test func testChildRoomsStoreUpsertDedupes() async throws {
        let suiteName = "ChildRoomsStoreTests.dedupe.\(UUID().uuidString)"
        let key = "test_child_rooms"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(false, "Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let hostUUID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let store = await MainActor.run { ChildRoomsStore(defaults: defaults, key: key) }
        let initialRoom = ChildSavedRoom(label: "Room", preferredTransport: .bluetooth, hostUUID: hostUUID)
        await MainActor.run { store.upsert(initialRoom) }
        let firstUsedAt = await MainActor.run { store.rooms.first?.lastUsedAt }

        try await Task.sleep(nanoseconds: 1_000_000)

        let updatedRoom = ChildSavedRoom(label: "Room Updated", preferredTransport: .bluetooth, hostUUID: hostUUID)
        await MainActor.run { store.upsert(updatedRoom) }
        let rooms = await MainActor.run { store.rooms }
        let secondUsedAt = await MainActor.run { store.rooms.first?.lastUsedAt }

        #expect(rooms.count == 1)
        #expect(rooms.first?.label == "Room Updated")
        if let firstUsedAt, let secondUsedAt {
            #expect(secondUsedAt > firstUsedAt)
        } else {
            #expect(false, "Expected lastUsedAt to be set")
        }
    }
}
