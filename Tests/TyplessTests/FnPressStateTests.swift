import XCTest
@testable import Typless

final class FnPressStateTests: XCTestCase {
  func testFirstPressStartsAndSecondPressFinishesWithoutReleaseToggling() {
    var state = FnPressState()
    var recording = false
    for (isDown, expectedRecording) in [(true, true), (false, true), (true, false), (false, false)] {
      if state.update(isDown: isDown) { recording.toggle() }
      XCTAssertEqual(recording, expectedRecording)
    }
  }

  func testHeldKeyAndRepeatedDownEventsDoNotToggleAgain() {
    var state = FnPressState()
    XCTAssertTrue(state.update(isDown: true))
    for _ in 0..<100 {
      XCTAssertFalse(state.update(isDown: true))
    }
    XCTAssertTrue(state.isDown)
    XCTAssertFalse(state.update(isDown: false))
    XCTAssertFalse(state.isDown)
    XCTAssertTrue(state.update(isDown: true))
  }

  func testUnmatchedAndRepeatedReleaseEventsAreIgnored() {
    var state = FnPressState()
    XCTAssertFalse(state.update(isDown: false))
    XCTAssertFalse(state.update(isDown: false))
    XCTAssertTrue(state.update(isDown: true))
    XCTAssertFalse(state.update(isDown: false))
    XCTAssertFalse(state.update(isDown: false))
  }

  func testResetAllowsNextPressAfterListenerStopsOrLosesEvents() {
    var state = FnPressState()
    XCTAssertTrue(state.update(isDown: true))
    state.reset()
    XCTAssertFalse(state.isDown)
    XCTAssertFalse(state.update(isDown: false))
    XCTAssertTrue(state.update(isDown: true))
  }
}
