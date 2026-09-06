import AppKit
import SwiftUI

@MainActor
final class RecordingOverlayController {
  var onCancel: (() -> Void)?
  var onFinish: (() -> Void)?
  private let model = VoiceBarModel()
  private let panel: NSPanel
  private var hideGeneration = 0

  init() {
    panel = Self.makePanel()
    let root = VoiceBar(model: model, cancel: { [weak self] in self?.onCancel?() },
      finish: { [weak self] in self?.onFinish?() })
    panel.contentView = NSHostingView(rootView: root)
  }

  static func makePanel() -> NSPanel {
    let panel = RecordingPanel(contentRect: CGRect(origin: .zero, size: VoiceBar.panelSize),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .statusBar
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.isReleasedWhenClosed = false
    return panel
  }

  func show(on screen: NSScreen?, appearance: AppAppearance, initialStatus: String) {
    hideGeneration += 1
    model.transcript.update(initialStatus, isStatus: true, animated: false)
    model.recording = true
    model.level = 0
    model.startedAt = Date()
    panel.appearance = appearance.nsAppearance
    guard let screen = screen ?? NSScreen.main else { return }
    panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - panel.frame.width / 2,
      y: screen.visibleFrame.minY + 18))
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
      panel.animator().alphaValue = 1
    }
  }

  func updateText(_ text: String, isStatus: Bool, animated: Bool = true) {
    model.transcript.update(text, isStatus: isStatus, animated: animated)
  }
  func updateLevel(_ level: Double) { model.level = max(0, min(1, level)) }
  func setRecording(_ recording: Bool) { model.recording = recording }
  func hide(completion: (() -> Void)? = nil) {
    model.transcript.finishImmediately()
    hideGeneration += 1
    let generation = hideGeneration
    NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
      panel.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        guard let self, generation == self.hideGeneration else { return }
        self.panel.orderOut(nil)
        completion?()
      }
    }
  }
}

/// Native buttons must never take keyboard focus away from the insertion target.
private final class RecordingPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
