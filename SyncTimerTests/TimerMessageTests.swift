import XCTest
@testable import SyncTimer

final class TimerMessageTests: XCTestCase {
    func testResetTokenCodableRoundTrip() throws {
        let msg = TimerMessage(
            action: .reset,
            timestamp: 123,
            phase: "idle",
            remaining: 0,
            stopEvents: [],
            resetToken: 42,
            clearLoadedSheet: true
        )
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(TimerMessage.self, from: data)
        XCTAssertEqual(decoded.resetToken, 42)
        XCTAssertEqual(decoded.clearLoadedSheet, true)
    }

    func testResetTokenDecodesWhenMissing() throws {
        let json = """
        {
          "action": "reset",
          "timestamp": 0,
          "phase": "idle",
          "remaining": 0,
          "stopEvents": []
        }
        """
        let decoded = try JSONDecoder().decode(TimerMessage.self, from: Data(json.utf8))
        XCTAssertNil(decoded.resetToken)
        XCTAssertNil(decoded.clearLoadedSheet)
    }
}
