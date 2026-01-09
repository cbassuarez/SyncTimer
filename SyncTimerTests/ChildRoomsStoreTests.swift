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

        let store = await MainActor.run { ChildRoomsStore(defaults: defaults, key: key) }
        let keyRoom = RoomKey.host(transport: .wifi, hostUUID: hostUUID)
        await MainActor.run { store.upsertObservedRoom(key: keyRoom, observedLabel: "Persisted Room", source: .remote) }

        let reloaded = await MainActor.run { ChildRoomsStore(defaults: defaults, key: key) }
        let rooms = await MainActor.run { reloaded.rooms }

        #expect(rooms.count == 1)
        #expect(rooms.first?.effectiveLabel == "Persisted Room")
        #expect(rooms.first?.hostUUID == hostUUID)
    }

    @Test func testRoomKeyEqualityAndHash() async throws {
        let hostUUID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let keyA = RoomKey.host(transport: .nearby, hostUUID: hostUUID)
        let keyB = RoomKey.host(transport: .nearby, hostUUID: hostUUID)
        let keyC = RoomKey.direct(transport: .wifi, peerIP: "10.0.0.5", peerPort: 5000)
        let keyD = RoomKey.direct(transport: .wifi, peerIP: "10.0.0.5", peerPort: 5000)

        #expect(keyA == keyB)
        #expect(keyC == keyD)
        #expect(Set([keyA, keyB]).count == 1)
        #expect(Set([keyC, keyD]).count == 1)
    }

    @Test func testLegacyLabelMigration() async throws {
        let id = UUID()
        let hostUUID = UUID()
        let createdAt = Date()
        let legacyPayload: [[String: Any]] = [[
            "id": id.uuidString,
            "label": "Legacy Name",
            "preferredTransport": SyncSettings.SyncConnectionMethod.network.rawValue,
            "hostUUID": hostUUID.uuidString,
            "createdAt": createdAt.timeIntervalSinceReferenceDate,
            "lastUsedAt": createdAt.timeIntervalSinceReferenceDate
        ]]
        let data = try JSONSerialization.data(withJSONObject: legacyPayload)
        let decoded = try JSONDecoder().decode([ChildSavedRoom].self, from: data)

        #expect(decoded.count == 1)
        #expect(decoded.first?.userLabel == "Legacy Name")
    }

    @Test func testDedupeAndMergePrefersUserLabel() async throws {
        let suiteName = "ChildRoomsStoreTests.merge.\(UUID().uuidString)"
        let key = "test_child_rooms"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(false, "Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let hostUUID = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
        let keyRoom = RoomKey.host(transport: .nearby, hostUUID: hostUUID)
        let now = Date()
        let roomA = ChildSavedRoom(
            userLabel: "Custom",
            observedLabel: "Observed A",
            preferredTransport: .bluetooth,
            hostUUID: hostUUID,
            createdAt: now.addingTimeInterval(-100),
            lastUsedAt: now.addingTimeInterval(-50),
            lastObservedLabelChangeAt: now.addingTimeInterval(-80)
        )
        let roomB = ChildSavedRoom(
            userLabel: nil,
            observedLabel: "Observed B",
            preferredTransport: .bluetooth,
            hostUUID: hostUUID,
            createdAt: now.addingTimeInterval(-200),
            lastUsedAt: now.addingTimeInterval(-10),
            lastObservedLabelChangeAt: now.addingTimeInterval(-5)
        )

        let store = await MainActor.run { ChildRoomsStore(defaults: defaults, key: key) }
        await MainActor.run {
            store.rooms = [roomA, roomB]
            store.dedupeAndMerge()
        }
        let rooms = await MainActor.run { store.rooms }

        #expect(rooms.count == 1)
        #expect(rooms.first?.roomKey == keyRoom)
        #expect(rooms.first?.userLabel == "Custom")
        #expect(rooms.first?.observedLabel == "Observed B")
        #expect(rooms.first?.createdAt == roomB.createdAt)
        #expect(rooms.first?.lastRenamedSource == .merge)
    }

    @Test func testRenamedBadgeTTLAndUserRenameClears() async throws {
        let suiteName = "ChildRoomsStoreTests.rename.\(UUID().uuidString)"
        let key = "test_child_rooms"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(false, "Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let hostUUID = UUID()
        let keyRoom = RoomKey.host(transport: .wifi, hostUUID: hostUUID)
        let store = await MainActor.run { ChildRoomsStore(defaults: defaults, key: key) }
        await MainActor.run { store.upsertObservedRoom(key: keyRoom, observedLabel: "Initial", source: .remote) }
        await MainActor.run { store.upsertObservedRoom(key: keyRoom, observedLabel: "Updated", source: .remote) }

        let updatedRoom = await MainActor.run { store.rooms.first }
        #expect(updatedRoom?.shouldShowRenamedBadge() == true)

        await MainActor.run { store.renameRoom(key: keyRoom, to: "Custom") }
        let renamedRoom = await MainActor.run { store.rooms.first }
        #expect(renamedRoom?.shouldShowRenamedBadge() == false)
    }

    @Test func testPersistenceRoundtrip() async throws {
        let suiteName = "ChildRoomsStoreTests.roundtrip.\(UUID().uuidString)"
        let key = "test_child_rooms"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(false, "Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let hostUUID = UUID()
        let keyRoom = RoomKey.host(transport: .nearby, hostUUID: hostUUID)
        let store = await MainActor.run { ChildRoomsStore(defaults: defaults, key: key) }
        await MainActor.run { store.upsertObservedRoom(key: keyRoom, observedLabel: "Roundtrip", source: .remote) }

        let reloaded = await MainActor.run { ChildRoomsStore(defaults: defaults, key: key) }
        let rooms = await MainActor.run { reloaded.rooms }

        #expect(rooms.count == 1)
        #expect(rooms.first?.effectiveLabel == "Roundtrip")
    }
}
