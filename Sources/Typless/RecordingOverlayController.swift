import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingOverlayController {
  var onCancel: (() -> Void)?
  var onFinish: (() -> Void)?
  private let model: VoiceBarModel
  private let panel: NSPanel
  private var hideGeneration = 0
  private var controlsCancellable: AnyCancellable?

  private var appearanceAnimation: Animation? {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.14)
  }

  private var dismissalAnimation: Animation? {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeIn(duration: 0.18)
  }

  init(model: VoiceBarModel? = nil, panel: NSPanel? = nil, preferences: AppPreferences? = nil) {
    self.model = model ?? VoiceBarModel()
    self.panel = panel ?? Self.makePanel()
    let root = VoiceBar(model: self.model, cancel: { [weak self] in self?.onCancel?() },
      finish: { [weak self] in self?.onFinish?() })
    self.panel.contentView = NSHostingView(rootView: root)
    self.panel.ignoresMouseEvents = !self.model.showsControls
    controlsCancellable = preferences?.$showRecordingControls
      .removeDuplicates()
      .sink { [weak self] enabled in
        self?.model.showsControls = enabled
        self?.panel.ignoresMouseEvents = !enabled
      }
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

  func show(on screen: NSScreen?, appearance: AppAppearance, initialStatus: String, phase: VoiceBarModel.Phase = .recording) {
    hideGeneration += 1
    model.transcript.update(initialStatus, isStatus: true, animated: false)
    model.phase = phase
    model.showsGlow = phase != .status
    model.level = 0
    model.startedAt = Date()
    panel.appearance = appearance.nsAppearance
    guard let screen = screen ?? NSScreen.main else { return }
    model.isVisible = true
    panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - panel.frame.width / 2,
      y: screen.visibleFrame.minY + 18))
    panel.alphaValue = 1
    panel.orderFrontRegardless()
    withAnimation(appearanceAnimation) {
      model.isPresented = true
    }
  }

  func updateText(_ text: String, isStatus: Bool, animated: Bool = true) {
    model.transcript.update(text, isStatus: isStatus, animated: animated)
  }
  func updateLevel(_ level: Double) {
    guard model.isPresented else { return }
    model.level = max(0, min(1, level))
  }
  func setPhase(_ phase: VoiceBarModel.Phase) { model.phase = phase }
  func hide(completion: (() -> Void)? = nil) {
    hideGeneration += 1
    let generation = hideGeneration
    // Let SwiftUI finish the glass/material and border removal together.
    // Ordering the panel out or resetting the level first cuts that short.
    withAnimation(dismissalAnimation, completionCriteria: .removed) {
      model.isPresented = false
    } completion: { [weak self] in
      guard let self, generation == self.hideGeneration else { return }
      self.panel.orderOut(nil)
      self.model.isVisible = false
      self.model.showsGlow = false
      self.model.level = 0
      self.model.transcript.finishImmediately()
      completion?()
    }
  }
}

/// Native buttons must never take keyboard focus away from the insertion target.
private final class RecordingPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
