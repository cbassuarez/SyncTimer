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

    @Test func testChildRoomsStoreMigrationDefaults() async throws {
        let suiteName = "ChildRoomsStoreTests.migration.\(UUID().uuidString)"
        let key = "test_child_rooms"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(false, "Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let hostUUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let now = Date().timeIntervalSinceReferenceDate
        let payload: [[String: Any]] = [
            [
                "id": id.uuidString,
                "label": "Legacy Room",
                "preferredTransport": SyncSettings.SyncConnectionMethod.network.rawValue,
                "hostUUID": hostUUID.uuidString,
                "peerIP": "10.0.0.9",
                "peerPort": "5001",
                "createdAt": now,
                "lastUsedAt": now
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        defaults.set(data, forKey: key)

        let store = await MainActor.run { ChildRoomsStore(defaults: defaults, key: key) }
        let rooms = await MainActor.run { store.rooms }

        #expect(rooms.count == 1)
        #expect(rooms.first?.label == "Legacy Room")
        #expect(rooms.first?.labelSource == .unknown)
        #expect(rooms.first?.previousLabel == nil)
        #expect(rooms.first?.renamedAt == nil)
    }

    @Test func testChildRoomsStoreDedupeMergeKeepsNewest() async throws {
        let suiteName = "ChildRoomsStoreTests.merge.\(UUID().uuidString)"
        let key = "test_child_rooms"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(false, "Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let hostUUID = UUID(uuidString: "99999999-AAAA-BBBB-CCCC-DDDDDDDDDDDD")!
        let store = await MainActor.run { ChildRoomsStore(defaults: defaults, key: key) }
        var older = ChildSavedRoom(label: "Old", preferredTransport: .network, hostUUID: hostUUID)
        older.lastUsedAt = Date(timeIntervalSince1970: 100)
        var newer = ChildSavedRoom(label: "New", preferredTransport: .bluetooth, hostUUID: hostUUID)
        newer.lastUsedAt = Date(timeIntervalSince1970: 200)
        newer.previousLabel = "Prev"
        newer.renamedAt = Date()

        await MainActor.run {
            store.rooms = [older, newer]
            store.dedupe()
        }

        let rooms = await MainActor.run { store.rooms }
        #expect(rooms.count == 1)
        #expect(rooms.first?.label == "New")
        #expect(rooms.first?.previousLabel == "Prev")
    }

    @Test func testChildRoomsStoreRenameRule() async throws {
        let suiteName = "ChildRoomsStoreTests.rename.\(UUID().uuidString)"
        let key = "test_child_rooms"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(false, "Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let hostUUID = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!
        let store = await MainActor.run { ChildRoomsStore(defaults: defaults, key: key) }
        let initial = ChildSavedRoom(label: "Room A", preferredTransport: .network, hostUUID: hostUUID)
        await MainActor.run { store.upsert(initial) }

        await MainActor.run {
            store.upsertConnected(
                hostUUID: hostUUID,
                authoritativeLabel: "Room B",
                labelSource: .joinLink,
                preferredTransport: .network,
                peerIP: nil,
                peerPort: nil
            )
        }
        let renamed = await MainActor.run { store.rooms.first }
        #expect(renamed?.label == "Room B")
        #expect(renamed?.previousLabel == "Room A")
        #expect(renamed?.renamedAt != nil)

        await MainActor.run {
            store.upsertConnected(
                hostUUID: hostUUID,
                authoritativeLabel: "   ",
                labelSource: .joinLink,
                preferredTransport: .network,
                peerIP: nil,
                peerPort: nil
            )
        }
        let unchanged = await MainActor.run { store.rooms.first }
        #expect(unchanged?.label == "Room B")
        #expect(unchanged?.previousLabel == "Room A")
    }
}
