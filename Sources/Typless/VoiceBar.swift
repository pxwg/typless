import SwiftUI

@MainActor
final class VoiceBarModel: ObservableObject {
  enum Phase { case recording, processing, status }
  let transcript = TranscriptPresentation()
  @Published var level = 0.0
  @Published var phase: Phase = .recording
  @Published var startedAt = Date()
  @Published var isVisible = false
  @Published var isPresented = false
  @Published var showsControls = false
  // Retain the recording border through final/status messages and dismissal.
  @Published var showsGlow = false
}

struct VoiceBar: View {
  static let compactCapsuleWidth: CGFloat = 220
  static let controlsCapsuleWidth: CGFloat = 300
  // Keep the transparent hosting panel stable while the glass changes width.
  static let panelSize = CGSize(width: controlsCapsuleWidth + 32, height: 80)

  @ObservedObject var model: VoiceBarModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var glassNamespace
  let cancel: () -> Void
  let finish: () -> Void

  private var capsuleWidth: CGFloat {
    model.showsControls ? Self.controlsCapsuleWidth : Self.compactCapsuleWidth
  }

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        GlassEffectContainer {
          if model.isPresented {
            capsule
              .glassEffectID("recording-capsule", in: glassNamespace)
              .glassEffectTransition(reduceMotion ? .identity : .materialize)
          }
        }
      } else {
        if model.isPresented {
          capsule.transition(.opacity)
        }
      }
    }
    .frame(width: Self.panelSize.width, height: Self.panelSize.height)
    .overlay {
      // Render after the glass pass to preserve the border's colors. Its
      // lifetime follows the same presentation transaction as the material,
      // independent of the current recording/processing/status contents.
      if model.isPresented && model.showsGlow {
        VoiceRecordingGlow(level: model.phase == .recording ? model.level : 0,
          startedAt: model.startedAt, isVisible: model.isVisible)
          .frame(width: capsuleWidth, height: 48)
          .transition(.opacity)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
    // Resize the native glass and the externally rendered border together.
    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: model.showsControls)
  }

  private var capsule: some View {
    contents
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      // A stable width keeps the buttons still as speech arrives or is revised.
      .frame(width: capsuleWidth)
      .modifier(VoiceCapsuleSurface())
      .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.phase)
  }

  private var contents: some View {
    HStack(spacing: 12) {
      if model.showsControls && model.phase != .status {
        Button(action: cancel) {
          Label("取消录音", systemImage: "xmark")
            .labelStyle(.iconOnly)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("取消 · Esc")
      }

      TranscriptText(presentation: model.transcript,
        centersShortText: !model.showsControls || model.phase == .status)

      if model.showsControls && model.phase == .recording {
        Button(action: finish) {
          Label("完成录音", systemImage: "stop.circle.fill")
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(Color.accentColor)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("完成录音")
      } else if model.phase == .processing {
        ProgressView()
          .controlSize(.small)
          .frame(width: 32, height: 32)
          .accessibilityHidden(true)
      }
    }
  }
}

private struct TranscriptText: View {
  @ObservedObject var presentation: TranscriptPresentation
  let centersShortText: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var text: Text {
    presentation.frame.fading.reduce(Text(verbatim: singleLine(presentation.frame.stableText))) { result, character in
      // A single native Text preserves normal shaping. Only the
      // arriving tail fades; never crossfade the entire existing sentence.
      Text("\(result)\(Text(verbatim: singleLine(character.text)).foregroundStyle(.primary.opacity(character.opacity)))")
    }
  }

  private func singleLine(_ value: String) -> String {
    // Hard line breaks must not trigger native one-line ellipsis either.
    String(value.map { $0.isNewline ? " " : $0 })
  }

  var body: some View {
    GeometryReader { geometry in
      let fadeWidth: CGFloat = 12
      text
        .font(.callout)
        .foregroundStyle(presentation.isStatus ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .contentTransition(.identity)
        .padding(.horizontal, fadeWidth)
        // Short phrases start naturally; overflowing text follows its tail.
        // The viewport owns the mask so text never overlaps either button.
        .frame(minWidth: geometry.size.width, alignment: centersShortText ? .center : .leading)
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
        .mask {
          let edge = min(0.5, fadeWidth / max(1, geometry.size.width))
          LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: edge),
            .init(color: .black, location: 1 - edge),
            .init(color: .clear, location: 1),
          ], startPoint: .leading, endPoint: .trailing)
        }
        .animation(reduceMotion || !presentation.animatesChanges ? nil : .linear(duration: 0.10),
          value: presentation.frame.text)
    }
    .frame(height: 32)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(presentation.isStatus ? "录音状态" : "转录文字")
    .accessibilityValue(presentation.text)
  }
}

private struct VoiceCapsuleSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme

  @ViewBuilder func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.glassEffect(reduceTransparency ? .regular : .clear, in: Capsule())
        // A light scrim supports text over busy windows while retaining the
        // translucency of the clear glass variant.
        .background((colorScheme == .dark ? Color.black : Color.white)
          .opacity(reduceTransparency ? 0 : (colorScheme == .dark ? 0.18 : 0.28)), in: Capsule())
    } else {
      content.background(reduceTransparency ? .regularMaterial : .ultraThinMaterial, in: Capsule())
    }
  }
}

private struct VoiceRecordingGlow: View {
  let level: Double
  let startedAt: Date
  let isVisible: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    // NSPanel.orderOut does not destroy its SwiftUI view. Visibility must
    // explicitly pause the clock; scenePhase is not supplied by NSHostingView.
    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || !isVisible)) { timeline in
      IntelligenceGlowBorder(time: reduceMotion ? 0 : max(0, timeline.date.timeIntervalSince(startedAt)),
        level: reduceMotion ? 0 : level, cornerRadius: 24)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
