import SwiftUI

@MainActor
final class VoiceBarModel: ObservableObject {
  let transcript = TranscriptPresentation()
  @Published var level = 0.0
  @Published var recording = true
  @Published var startedAt = Date()
}

struct VoiceBar: View {
  static let panelSize = CGSize(width: 620, height: 120)

  @ObservedObject var model: VoiceBarModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let cancel: () -> Void
  let finish: () -> Void

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        // Keep the two surfaces distinct at rest, sharing one native glass pass.
        GlassEffectContainer(spacing: 8) { capsules }
      } else {
        capsules
      }
    }
    .frame(width: Self.panelSize.width, height: Self.panelSize.height)
  }

  private var capsules: some View {
    VStack(spacing: 10) {
      TranscriptCapsule(presentation: model.transcript)

      controls
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(VoiceCapsuleSurface())
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.recording)
    }
  }

  private var controls: some View {
    HStack(spacing: 12) {
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

      if model.recording {
        VoiceWaveform(level: model.level)
        Divider().frame(height: 20)
        Text(model.startedAt, style: .timer)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(minWidth: 40)
          .fixedSize()
          .accessibilityLabel("录音时长")
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
      } else {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("整理中").font(.callout)
        }
        .frame(height: 32)
        .accessibilityElement(children: .combine)
      }
    }
  }
}

private struct TranscriptCapsule: View {
  @ObservedObject var presentation: TranscriptPresentation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var text: Text {
    presentation.frame.fading.reduce(Text(verbatim: presentation.frame.stableText)) { result, character in
      // A single native Text preserves normal shaping/truncation. Only the
      // arriving tail fades; never crossfade the entire existing sentence.
      Text("\(result)\(Text(verbatim: character.text).foregroundStyle(.primary.opacity(character.opacity)))")
    }
  }

  var body: some View {
    text
      .font(.callout)
      .foregroundStyle(presentation.isStatus ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
      .lineLimit(1)
      .truncationMode(.head)
      .contentTransition(.identity)
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .modifier(VoiceCapsuleSurface())
      .frame(maxWidth: 570)
      .animation(reduceMotion || !presentation.animatesChanges ? nil : .smooth(duration: 0.10),
        value: presentation.frame.text)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(presentation.isStatus ? "录音状态" : "转录文字")
      .accessibilityValue(presentation.text)
  }
}

private struct VoiceCapsuleSurface: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.glassEffect(.regular, in: Capsule())
    } else {
      content.background(.regularMaterial, in: Capsule())
    }
  }
}

private struct VoiceWaveform: View {
  let level: Double
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.08, paused: reduceMotion || level == 0)) { timeline in
      HStack(spacing: 3) {
        ForEach(0..<13) { index in
          let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 9
          let motion = 0.55 + 0.45 * sin(phase + Double(index) * 1.2)
          Capsule().fill(Color.accentColor)
            .frame(width: 3, height: 4 + level * 23 * motion)
        }
      }
      .frame(width: 76, height: 32)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("正在录音")
  }
}
