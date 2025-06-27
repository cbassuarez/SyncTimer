// SyncTimerAppTests/TimeIntervalFormattingTests.swift

import XCTest
@testable import SyncTimer   // make sure your app target’s “Product Module Name” is SyncTimerApp

final class TimeIntervalFormattingTests: XCTestCase {

    func testFormattedCS_zeroSeconds() {
        let t = TimeInterval(0)
        XCTAssertEqual(t.formattedCS, "00:00:00.00")
    }

    func testFormattedCS_subSecondRounding() {
        // 1.234s → 123 centiseconds → "00:00:01.23"
        let t = TimeInterval(1.234)
        XCTAssertEqual(t.formattedCS, "00:00:01.23")
    }

    func testFormattedCS_minutesAndHours() {
        // 62.5s → 1m 2s 50c
        XCTAssertEqual(TimeInterval(62.5).formattedCS,  "00:01:02.50")
        // 3661.07s → 1h 1m 1s 07c
        XCTAssertEqual(TimeInterval(3661.07).formattedCS,"01:01:01.07")
    }

    func testFormattedCS_roundsCorrectly() {
        // 0.005s rounds to 1c
        XCTAssertEqual(TimeInterval(0.005).formattedCS, "00:00:00.01")
    }
}
