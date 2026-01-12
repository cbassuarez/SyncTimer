import XCTest
@testable import SyncTimer

final class TimerMessageWireTests: XCTestCase {
    func testTimerMessageRoundTripWithDisplayState() throws {
        let displayState = TimerMessage.DisplayState(
            displayID: 7,
            kind: .cueFlash,
            text: nil,
            assetID: nil,
            rehearsalMark: "A",
            flashStartUptimeNs: 123_000,
            flashDurationMs: 250
        )
        let stamps = [
            TimerMessage.EventStamp(id: 100, kind: .cue, time: 3.0),
            TimerMessage.EventStamp(id: 101, kind: .message, time: 1234.0)
        ]
        let message = TimerMessage(
            action: .update,
            stateSeq: 42,
            timestamp: 1234.0,
            phase: "running",
            remaining: 12.3,
            stopEvents: [StopEventWire(eventTime: 1.0, duration: 2.0)],
            cueEvents: [CueEventWire(cueTime: 3.0)],
            restartEvents: [RestartEventWire(restartTime: 4.0)],
            showHours: true,
            recentEventStamps: stamps,
            displayState: displayState
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(TimerMessage.self, from: data)

        XCTAssertEqual(decoded, message)
        XCTAssertEqual(decoded.displayState?.flashDurationMs, 250)
        XCTAssertEqual(decoded.recentEventStamps?.count, 2)
    }

    func testTimerMessageDecodesWithoutNewFields() throws {
        let json = """
        {"action":"update","timestamp":1234,"phase":"running","remaining":9.5,"stopEvents":[{"eventTime":1,"duration":2}],"anchorElapsed":1.5}
        """
        let decoded = try JSONDecoder().decode(TimerMessage.self, from: Data(json.utf8))
        XCTAssertNil(decoded.displayState)
        XCTAssertNil(decoded.recentEventStamps)
        XCTAssertNil(decoded.showHours)
    }

    func testTimerMessageDecodesUnknownKindsSafely() throws {
        let json = """
        {"action":"update","timestamp":1000,"phase":"running","remaining":5,"stopEvents":[{"eventTime":1,"duration":2}],"displayState":{"displayID":1,"kind":"glow"},"recentEventStamps":[{"id":99,"kind":"mystery","time":3.0}]}
        """
        let decoded = try JSONDecoder().decode(TimerMessage.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.displayState?.kind, .unknown)
        XCTAssertEqual(decoded.recentEventStamps?.first?.kind, .unknown)
    }
}
