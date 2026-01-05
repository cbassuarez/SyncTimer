import XCTest
@testable import SyncTimer

@MainActor
final class CueDisplayControllerTests: XCTestCase {
    private func sheet(message: String = "Hello", hold: TimeInterval?) -> CueSheet {
        var s = CueSheet(title: "Test")
        s.events = [
            CueSheet.Event(
                kind: .message,
                at: 0,
                holdSeconds: hold,
                payload: .message(.init(text: message))
            )
        ]
        return s
    }

    func testHoldSecondsSchedulesClear() {
        let controller = CueDisplayController(durationConfig: .init(base: 0.1, perChar: 0.0, max: 0.1))
        controller.buildTimeline(from: sheet(hold: 0.1))
        controller.apply(elapsed: 0)
        XCTAssertNotEqual(controller.slot, .none)

        let exp = expectation(description: "clears after hold")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(controller.slot, .none)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testHoldZeroIsSticky() {
        let controller = CueDisplayController(durationConfig: .init(base: 0.1, perChar: 0.1, max: 0.2))
        controller.buildTimeline(from: sheet(hold: 0))
        controller.apply(elapsed: 0)
        XCTAssertNotEqual(controller.slot, .none)

        let exp = expectation(description: "remains visible")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertNotEqual(controller.slot, .none)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testDefaultDurationUsesCharacterCountAndCap() {
        let controller = CueDisplayController(durationConfig: .init(base: 0.1, perChar: 0.1, max: 0.25))
        controller.buildTimeline(from: sheet(message: "1234567890", hold: nil))
        controller.apply(elapsed: 0)
        XCTAssertNotEqual(controller.slot, .none)

        let exp = expectation(description: "clears after computed default")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(controller.slot, .none)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testDismissCancelsPendingClear() {
        let controller = CueDisplayController(durationConfig: .init(base: 0.5, perChar: 0.1, max: 1.0))
        controller.buildTimeline(from: sheet(hold: 0.5))
        controller.apply(elapsed: 0)
        XCTAssertNotEqual(controller.slot, .none)
        controller.dismiss()

        let exp = expectation(description: "dismiss stays cleared")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(controller.slot, .none)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }
}
