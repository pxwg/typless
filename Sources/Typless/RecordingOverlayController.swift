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
    panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 620, height: 108),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .statusBar
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.isReleasedWhenClosed = false
    let root = VoiceBar(model: model, cancel: { [weak self] in self?.onCancel?() },
      finish: { [weak self] in self?.onFinish?() })
    panel.contentView = NSHostingView(rootView: root)
  }

  func show(on screen: NSScreen?, appearance: AppAppearance, initialStatus: String) {
    hideGeneration += 1
    model.text = initialStatus
    model.recording = true
    model.level = 0
    model.startedAt = Date()
    guard let screen = screen ?? NSScreen.main else { return }
    panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - 310, y: screen.visibleFrame.minY + 18))
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      panel.animator().alphaValue = 1
    }
  }

  func updateText(_ text: String, isStatus: Bool, animated: Bool = true) { model.text = text }
  func updateLevel(_ level: Double) { model.level = max(0, min(1, level)) }
  func setRecording(_ recording: Bool) { model.recording = recording }
  func hide(completion: (() -> Void)? = nil) {
    hideGeneration += 1
    let generation = hideGeneration
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
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

@MainActor
private final class VoiceBarModel: ObservableObject {
  @Published var text = ""
  @Published var level = 0.0
  @Published var recording = true
  @Published var startedAt = Date()
}

private struct VoiceBar: View {
  @ObservedObject var model: VoiceBarModel
  let cancel: () -> Void
  let finish: () -> Void

  var body: some View {
    VStack(spacing: 9) {
      Text(model.text)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(1).truncationMode(.head)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(.black.opacity(0.8), in: Capsule())
        .frame(maxWidth: 570)
      HStack(spacing: 16) {
        Button(action: cancel) {
          Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6)).frame(width: 24, height: 28)
        }.buttonStyle(.plain).help("取消 · Esc").accessibilityLabel("取消录音")
        if model.recording {
          TimelineView(.animation(minimumInterval: 0.08)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
              ForEach(0..<13) { i in
                let motion = 0.55 + 0.45 * sin(phase * 9 + Double(i) * 1.2)
                Capsule().fill(Color(red: 0.55, green: 0.68, blue: 1))
                  .frame(width: 3, height: 4 + model.level * 23 * motion)
              }
            }.frame(width: 76, height: 28)
          }
        } else {
          HStack(spacing: 8) {
            ProgressView().controlSize(.small).colorScheme(.dark)
            Text("整理中").font(.system(size: 12))
          }.frame(width: 76, height: 28)
        }
        Rectangle().fill(.white.opacity(0.16)).frame(width: 1, height: 18)
        if model.recording {
          Text(model.startedAt, style: .timer).font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.65)).frame(width: 35)
          Button(action: finish) {
            Image(systemName: "stop.fill").font(.system(size: 9)).foregroundStyle(.black)
              .frame(width: 25, height: 25).background(.white, in: Circle())
          }.buttonStyle(.plain).help("完成录音").accessibilityLabel("完成录音")
        } else {
          Text("Qwen").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
        }
      }
      .padding(.horizontal, 15).padding(.vertical, 10)
      .background(Color(white: 0.09), in: Capsule())
      .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
      .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }.frame(width: 620, height: 108).colorScheme(.dark)
  }
}
