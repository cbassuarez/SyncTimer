import Foundation
import Testing
@testable import SyncTimer

struct JoinHandoffStoreTests {
    @Test func saveAndLoadPending() async throws {
        JoinHandoffStore.clearAll()
        let host = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let request = JoinRequestV1(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1000).timeIntervalSince1970,
            requestId: "req-1",
            mode: "wifi",
            transportHint: "bonjour",
            hostUUIDs: [host],
            roomLabel: "Test Room",
            deviceNames: ["Host 1"],
            selectedHostUUID: nil,
            minBuild: nil,
            sourceURL: "https://synctimerapp.com/join"
        )

        JoinHandoffStore.savePending(request)
        let loaded = JoinHandoffStore.loadPending(now: Date(timeIntervalSince1970: 1000))
        #expect(loaded == request)
    }

    @Test func pruneExpiredPending() async throws {
        JoinHandoffStore.clearAll()
        let host = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let request = JoinRequestV1(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 0).timeIntervalSince1970,
            requestId: "req-expired",
            mode: "wifi",
            transportHint: nil,
            hostUUIDs: [host],
            roomLabel: nil,
            deviceNames: ["Host 1"],
            selectedHostUUID: nil,
            minBuild: nil,
            sourceURL: "https://synctimerapp.com/join"
        )

        JoinHandoffStore.savePending(request)
        let now = Date(timeIntervalSince1970: 60 * 60 * 2 + 1)
        let loaded = JoinHandoffStore.loadPending(now: now)
        #expect(loaded == nil)
    }

    @Test func consumeIsIdempotent() async throws {
        JoinHandoffStore.clearAll()
        let host = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let request = JoinRequestV1(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 2000).timeIntervalSince1970,
            requestId: "req-consume",
            mode: "nearby",
            transportHint: nil,
            hostUUIDs: [host],
            roomLabel: nil,
            deviceNames: ["Host 1"],
            selectedHostUUID: nil,
            minBuild: nil,
            sourceURL: "https://synctimerapp.com/join"
        )

        JoinHandoffStore.savePending(request)
        JoinHandoffStore.consume(requestId: request.requestId)
        JoinHandoffStore.consume(requestId: request.requestId)
        let loaded = JoinHandoffStore.loadPending(now: Date(timeIntervalSince1970: 2000))
        #expect(loaded == nil)
    }

    @Test func consumedRingBufferLimitsToTen() async throws {
        JoinHandoffStore.clearAll()
        for index in 1...12 {
            JoinHandoffStore.consume(requestId: "req-\(index)")
        }
        let defaults = JoinHandoffStore.defaultsStore()
        let consumed = defaults.stringArray(forKey: "synctimer.join.consumed_requestIds") ?? []
        #expect(consumed.count == 10)
        #expect(consumed.first == "req-3")
        #expect(consumed.last == "req-12")
    }
}
