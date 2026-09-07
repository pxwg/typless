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
    for (dark, showsControls) in [(false, false), (false, true), (true, false), (true, true)] {
      let model = VoiceBarModel()
      model.isPresented = true
      model.showsGlow = true
      model.showsControls = showsControls
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

      for phase: VoiceBarModel.Phase in [.recording, .processing, .status, .recording] {
        model.phase = phase
        let text: String
        switch phase {
        case .recording: text = String(repeating: "这是一段很长的转录文字 mixed language transcript。", count: 10)
        case .processing: text = "正在整理…"
        case .status: text = "没有聚焦的可编辑字段"
        }
        model.transcript.update(text, isStatus: phase != .recording, animated: false)
        model.level = phase == .recording ? 0.8 : 0
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
        XCTAssertEqual(buttons.count, showsControls ? (phase == .recording ? 2 : (phase == .processing ? 1 : 0)) : 0)
        if showsControls && phase != .status {
          try XCTUnwrap(buttons.first).performClick(nil)
          XCTAssertGreaterThan(cancels, 0)
        }
        let finish = buttons.dropFirst().first
        if showsControls && phase == .recording {
          try XCTUnwrap(finish).performClick(nil)
          XCTAssertGreaterThan(finishes, 0)
        } else {
          XCTAssertNil(finish, "Finish is only offered when recording controls are enabled")
        }

        for button in buttons {
          let frame = button.convert(button.bounds, to: host)
          XCTAssertGreaterThanOrEqual(frame.width, 28)
          XCTAssertGreaterThanOrEqual(frame.height, 28)
          XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1).contains(frame),
            "Button hit areas must remain inside the floating panel")
        }
        if phase == .status {
          XCTAssertTrue(descendants(of: NSProgressIndicator.self, in: host).isEmpty,
            "An error must not appear to be recording or processing")
        }
      }
      XCTAssertEqual(cancels, showsControls ? 3 : 0)
      XCTAssertEqual(finishes, showsControls ? 2 : 0)
    }
  }

  @MainActor func testStreamingFramesKeepTheCapsuleAndControlsInsideThePanel() async throws {
    for dark in [false, true] {
      let model = VoiceBarModel()
      model.isPresented = true
      model.showsGlow = true
      model.showsControls = true
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

  @MainActor func testRecordingPresentationSurvivesFinalStatusAndCleansUpAfterDismissal() async throws {
    let screen = try XCTUnwrap(NSScreen.main)
    let model = VoiceBarModel()
    let panel = SilentOverlayPanel()
    let controller = RecordingOverlayController(model: model, panel: panel)
    defer { panel.close() }

    controller.show(on: screen, appearance: .system, initialStatus: "正在聆听")
    controller.updateLevel(0.7)
    controller.setPhase(.processing)
    controller.updateText("正在整理", isStatus: true)
    controller.setPhase(.status)
    controller.updateText("转写完成", isStatus: false, animated: false)
    XCTAssertTrue(model.isPresented)
    XCTAssertTrue(model.showsGlow, "Final status must not remove the border before the capsule exits")
    XCTAssertTrue(model.isVisible)

    let dismissed = expectation(description: "Presentation removed")
    controller.hide { dismissed.fulfill() }
    controller.updateLevel(1)
    XCTAssertFalse(model.isPresented)
    XCTAssertNotEqual(model.level, 1, "Late audio callbacks cannot disturb the exit")
    await fulfillment(of: [dismissed], timeout: 2)
    XCTAssertFalse(model.isVisible)
    XCTAssertFalse(model.showsGlow)
    XCTAssertEqual(model.level, 0)
    XCTAssertEqual(panel.orderOutCount, 1)
    XCTAssertFalse(panel.isVisible)

    controller.show(on: screen, appearance: .system, initialStatus: "没有聚焦的输入框", phase: .status)
    XCTAssertFalse(model.showsGlow, "A standalone error must not acquire a recording border")
    controller.hide()
  }

  @MainActor func testShowingAgainInvalidatesAnEarlierDismissal() async throws {
    let screen = try XCTUnwrap(NSScreen.main)
    let model = VoiceBarModel()
    let panel = SilentOverlayPanel()
    let controller = RecordingOverlayController(model: model, panel: panel)
    defer { panel.close() }

    controller.show(on: screen, appearance: .system, initialStatus: "第一段")
    var oldCompletionCount = 0
    controller.hide { oldCompletionCount += 1 }
    // A nonanimated removal may already have completed. Any completion that
    // is still pending must not tear down the replacement presentation.
    let completedBeforeReshow = oldCompletionCount
    let orderedOutBeforeReshow = panel.orderOutCount
    controller.show(on: screen, appearance: .system, initialStatus: "新一段")
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertTrue(model.isPresented)
    XCTAssertTrue(model.isVisible)
    XCTAssertTrue(model.showsGlow)
    XCTAssertEqual(model.transcript.text, "新一段")
    XCTAssertEqual(oldCompletionCount, completedBeforeReshow)
    XCTAssertEqual(panel.orderOutCount, orderedOutBeforeReshow)
    XCTAssertFalse(panel.isVisible)
    controller.hide()
  }

  @MainActor func testControlPreferenceDefaultsOffPersistsAndUpdatesThePresentedPanel() throws {
    let domain = "typless-overlay-controls-test-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults)
    XCTAssertFalse(preferences.showRecordingControls)

    let model = VoiceBarModel()
    let panel = SilentOverlayPanel()
    let controller = RecordingOverlayController(model: model, panel: panel, preferences: preferences)
    defer { panel.close() }
    controller.show(on: try XCTUnwrap(NSScreen.main), appearance: .system, initialStatus: "正在聆听")
    controller.updateText("保留当前转写", isStatus: false, animated: false)
    XCTAssertFalse(model.showsControls)
    XCTAssertTrue(panel.ignoresMouseEvents)

    preferences.showRecordingControls = true
    XCTAssertTrue(model.showsControls)
    XCTAssertFalse(panel.ignoresMouseEvents)
    XCTAssertTrue(AppPreferences(defaults: defaults).showRecordingControls)

    preferences.showRecordingControls = false
    XCTAssertFalse(model.showsControls)
    XCTAssertTrue(panel.ignoresMouseEvents)
    XCTAssertFalse(AppPreferences(defaults: defaults).showRecordingControls)
    XCTAssertTrue(model.isPresented)
    XCTAssertTrue(model.showsGlow)
    XCTAssertEqual(model.phase, .recording)
    XCTAssertEqual(model.transcript.text, "保留当前转写")
    XCTAssertFalse(panel.isVisible)
    controller.hide()
  }

  @MainActor private func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
  }
}

/// Exercise the production lifecycle without showing UI or changing focus.
@MainActor private final class SilentOverlayPanel: NSPanel {
  var orderOutCount = 0

  init() {
    super.init(contentRect: CGRect(origin: .zero, size: VoiceBar.panelSize),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    isReleasedWhenClosed = false
  }

  override func orderFrontRegardless() {}
  override func orderOut(_ sender: Any?) {
    orderOutCount += 1
    super.orderOut(sender)
  }
}
