import XCTest
@testable import SyncTimer

final class MainScreenTests: XCTestCase {
  
  func makeScreen() -> MainScreen {
    // parentMode and showSettings are just bindings; we don't care
    return MainScreen(
      parentMode: .constant(.sync),
      showSettings: .constant(false)
    )
  }

  func testChildAppliesStartCountdown() {
    var screen = makeScreen()
    // simulate child role
    screen.syncSettings.role = .child

    // before any message, phase should be .idle
    XCTAssertEqual(screen.phase, .idle)

    // now simulate a “start countdown” message from parent
    let countdownMsg = TimerMessage(
      action: .start,
      timestamp: 0,
      phase: "countdown",
      remaining: 12.34,
      stopEvents: []
    )
    screen.applyIncomingTimerMessage(countdownMsg)

    XCTAssertEqual(screen.phase, .countdown)
    XCTAssertEqual(screen.countdownRemaining, 12.34, accuracy: 1e-6)
  }

  func testChildAppliesStartRunning() {
    var screen = makeScreen()
    screen.syncSettings.role = .child

    let runMsg = TimerMessage(
      action: .start,
      timestamp: 0,
      phase: "running",
      remaining: 3.21,
      stopEvents: []
    )
    screen.applyIncomingTimerMessage(runMsg)

    XCTAssertEqual(screen.phase, .running)
    XCTAssertEqual(screen.elapsed, 3.21, accuracy: 1e-6)
    // and that it set startDate so future ticks would work…
    XCTAssertNotNil(screen.startDate)
  }

  func testChildAppliesPause() {
    var screen = makeScreen()
    screen.syncSettings.role = .child

    let pauseMsg = TimerMessage(
      action: .pause,
      timestamp: 0,
      phase: "paused",
      remaining: 5.0,
      stopEvents: []
    )
    screen.applyIncomingTimerMessage(pauseMsg)

    XCTAssertEqual(screen.phase, .paused)
    XCTAssertEqual(screen.countdownRemaining, 5.0, accuracy: 1e-6)
    XCTAssertEqual(screen.elapsed, 5.0, accuracy: 1e-6)
  }

  func testChildAppliesReset() {
    var screen = makeScreen()
    screen.syncSettings.role = .child

    let resetMsg = TimerMessage(
      action: .reset,
      timestamp: 0,
      phase: "idle",
      remaining: 0,
      stopEvents: []
    )
    // seed some garbage state
    screen.phase = .running
    screen.countdownDigits = [1,2,3]
    screen.elapsed = 9.99

    screen.applyIncomingTimerMessage(resetMsg)

    XCTAssertEqual(screen.phase, .idle)
    XCTAssertTrue(screen.countdownDigits.isEmpty)
    XCTAssertEqual(screen.elapsed, 0, accuracy: 1e-6)
  }

  // …and so on for .update and .addEvent if you want…
}
