import AppKit
import SwiftUI
import XCTest
@testable import Typless

final class VoiceBarTests: XCTestCase {
  @MainActor func testPanelPreservesTheInputTargetsKeyboardFocus() {
    let panel = RecordingOverlayController.makePanel()
    defer { panel.close() }
    XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    XCTAssertFalse(panel.canBecomeKey)
    XCTAssertFalse(panel.canBecomeMain)
    XCTAssertFalse(panel.isOpaque)
    XCTAssertEqual(panel.backgroundColor, .clear)
    XCTAssertFalse(panel.hasShadow, "The system glass surface supplies its own visual treatment")
    XCTAssertFalse(panel.hidesOnDeactivate)
    XCTAssertEqual(panel.level, .statusBar)
    XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
    XCTAssertFalse(panel.isVisible)
  }

  @MainActor func testCapsuleStatesAndActionsAcrossAppearances() throws {
    // Isolated production views only: no coordinator, microphone, real input
    // target, clipboard, network connection, or visible/activated test window.
    for dark in [false, true] {
      let model = VoiceBarModel()
      var cancels = 0
      var finishes = 0
      let view = VoiceBar(model: model, cancel: { cancels += 1 }, finish: { finishes += 1 })
        // Invisible windows do not drive compositor-backed removal animations.
        .transaction { $0.disablesAnimations = true }
      let host = NSHostingView(rootView: view)
      let panel = RecordingOverlayController.makePanel()
      defer { panel.close() }
      panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      panel.contentView = host

      for recording in [true, false, true] {
        model.recording = recording
        let text = recording
          ? String(repeating: "这是一段很长的转录文字 mixed language transcript。", count: 10)
          : "正在整理…"
        model.transcript.update(text, isStatus: !recording, animated: false)
        model.level = recording ? 0.8 : 0
        model.startedAt = Date().addingTimeInterval(-3_665)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, VoiceBar.panelSize.width, accuracy: 1)
        XCTAssertEqual(host.fittingSize.height, VoiceBar.panelSize.height, accuracy: 1)
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)

        // SwiftUI's virtual AX tree is unavailable in an invisible window.
        // Exercise the real AppKit buttons, ordered by their on-panel position.
        let buttons = descendants(of: NSButton.self, in: host).sorted {
          $0.convert($0.bounds, to: host).minX < $1.convert($1.bounds, to: host).minX
        }
        XCTAssertEqual(buttons.count, recording ? 2 : 1)
        try XCTUnwrap(buttons.first).performClick(nil)
        XCTAssertGreaterThan(cancels, 0)
        let finish = buttons.dropFirst().first
        if recording {
          try XCTUnwrap(finish).performClick(nil)
          XCTAssertGreaterThan(finishes, 0)
        } else {
          XCTAssertNil(finish, "Finishing must not be offered while processing")
        }

        for button in buttons {
          let frame = button.convert(button.bounds, to: host)
          XCTAssertGreaterThanOrEqual(frame.width, 28)
          XCTAssertGreaterThanOrEqual(frame.height, 28)
          XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1).contains(frame),
            "Button hit areas must remain inside the floating panel")
        }
      }
      XCTAssertEqual(cancels, 3)
      XCTAssertEqual(finishes, 2)
    }
  }

  @MainActor func testStreamingFramesKeepTheCapsuleAndControlsInsideThePanel() async throws {
    for dark in [false, true] {
      let model = VoiceBarModel()
      let host = NSHostingView(rootView: VoiceBar(model: model, cancel: {}, finish: {})
        .transaction { $0.disablesAnimations = true })
      let panel = RecordingOverlayController.makePanel()
      defer {
        model.transcript.finishImmediately()
        panel.close()
      }
      panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      panel.contentView = host
      model.transcript.update("正在聆听…", isStatus: true)
      for chunk in ["让文字", "让文字更流畅地展开。Mixed text 👩🏽‍💻",
        String(repeating: "这是一段很长的文字。", count: 40)] {
        model.transcript.update(chunk, isStatus: false)
        for _ in 0..<8 {
          try await Task.sleep(for: .milliseconds(32))
          host.layoutSubtreeIfNeeded()
          XCTAssertEqual(host.fittingSize.width, VoiceBar.panelSize.width, accuracy: 1)
          XCTAssertEqual(host.fittingSize.height, VoiceBar.panelSize.height, accuracy: 1)
          XCTAssertFalse(panel.isVisible)
          let buttons = descendants(of: NSButton.self, in: host)
          XCTAssertEqual(buttons.count, 2)
          for button in buttons {
            XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1)
              .contains(button.convert(button.bounds, to: host)))
          }
        }
      }
    }
  }

  @MainActor private func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
  }
}
