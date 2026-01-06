import XCTest
@testable import SyncTimer

final class JoinHandoffStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearDefaults()
    }

    override func tearDown() {
        clearDefaults()
        super.tearDown()
    }

    func testSaveLoadRoundTrip() {
        let request = makeRequest()
        JoinHandoffStore.savePending(request)

        let loaded = JoinHandoffStore.loadPending(now: Date())
        XCTAssertEqual(loaded, request)
    }

    func testTTLExpiryClearsPending() {
        let request = makeRequest()
        JoinHandoffStore.savePending(request)

        let future = Date(timeIntervalSince1970: request.createdAt + (3 * 60 * 60))
        let loaded = JoinHandoffStore.loadPending(now: future)
        XCTAssertNil(loaded)
    }

    func testConsumePreventsReload() {
        let request = makeRequest()
        JoinHandoffStore.savePending(request)

        JoinHandoffStore.consume(requestId: request.requestId)
        let loaded = JoinHandoffStore.loadPending(now: Date())
        XCTAssertNil(loaded)
    }

    private func makeRequest() -> JoinRequestV1 {
        JoinRequestV1(
            schemaVersion: 1,
            createdAt: Date().timeIntervalSince1970,
            requestId: UUID().uuidString,
            mode: "wifi",
            transportHint: "bonjour",
            hostUUIDs: [UUID()],
            roomLabel: "Room",
            deviceNames: ["Host"],
            selectedHostUUID: nil,
            minBuild: nil,
            sourceURL: "https://synctimerapp.com/join"
        )
    }

    private func clearDefaults() {
        if let defaults = UserDefaults(suiteName: JoinHandoffStore.appGroupID) {
            defaults.removePersistentDomain(forName: JoinHandoffStore.appGroupID)
        }
    }
}
