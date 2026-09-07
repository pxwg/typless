import AppKit
import SwiftUI

// Standalone visual comparison. No microphone, network, or Typless coordinator.
@main
@MainActor
enum VoiceRibbonDemo {
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = DemoAppDelegate()
    app.delegate = delegate
    let menu = NSMenu()
    let item = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "退出 Siri 视觉对照", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    item.submenu = appMenu
    menu.addItem(item)
    app.mainMenu = menu
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 750),
      styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.title = "Typless · 三种 Siri 视觉"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: SiriComparisonView())
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    withExtendedLifetime(delegate) { app.run() }
  }
}

@MainActor
private final class DemoAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private struct SiriComparisonView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var dark = true
  @State private var simulated = false
  @State private var playing = true
  @State private var strength = 1.0
  @State private var focused = -1
  @State private var showSources = false
  @State private var epoch = Date()
  @State private var heldTime = 0.0
  @State private var waveEngine = ClassicWaveEngine()

  private var background: Color {
    dark ? Color(red: 0.035, green: 0.04, blue: 0.055) : Color(red: 0.945, green: 0.95, blue: 0.965)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        VStack(alignment: .leading, spacing: 7) {
          Text("三种 Siri 视觉").font(.system(size: 26, weight: .semibold))
          Text("横向波形、球体与屏幕边缘，直接对照。")
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        Spacer()
        Picker("预览布局", selection: $focused) {
          Text("并排").tag(-1)
          Text("横向").tag(0)
          Text("球体").tag(1)
          Text("边缘").tag(2)
        }.pickerStyle(.segmented).labelsHidden().frame(width: 252)
        Button { dark.toggle() } label: {
          Label(dark ? "浅色" : "深色", systemImage: dark ? "sun.max" : "moon")
            .font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 8)
            .background(.primary.opacity(0.06), in: Capsule())
        }.buttonStyle(.plain)
      }

      TimelineView(.animation(minimumInterval: 1.0 / 60,
        paused: !playing || reduceMotion)) { timeline in
        let time = reduceMotion ? 1.2 : heldTime + (playing ? timeline.date.timeIntervalSince(epoch) : 0)
        let level = strength * (simulated ? speechLevel(at: time) : 1)
        let snapshot = waveEngine.snapshot(at: time, level: level)
        VStack(spacing: 18) {
          HStack(spacing: 16) {
            ForEach(0..<3) { index in
              if focused == -1 || focused == index {
                effectCard(index: index, time: time, level: level, snapshot: snapshot, enlarged: focused != -1)
              }
            }
          }.frame(height: 390)
          HStack(spacing: 16) {
            ForEach(0..<3) { index in
              miniature(index: index, time: time, level: level, snapshot: snapshot)
            }
          }.frame(height: 88)
        }
      }

      HStack(spacing: 20) {
        Picker("电平来源", selection: $simulated) {
          Text("持续电平").tag(false)
          Text("模拟说话").tag(true)
        }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
        Text("电平").font(.system(size: 12)).foregroundStyle(.secondary)
        Slider(value: $strength, in: 0...1).accessibilityLabel("电平强度")
        Text(strength, format: .percent.precision(.fractionLength(0)))
          .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary).frame(width: 40)
        Button {
          if playing { heldTime += Date().timeIntervalSince(epoch) }
          else { epoch = Date() }
          playing.toggle()
        } label: {
          Label(playing ? "暂停" : "播放", systemImage: playing ? "pause.fill" : "play.fill")
            .frame(width: 62)
        }.buttonStyle(.bordered)
      }
      HStack {
        Text(reduceMotion ? "已遵循系统的“减少动态效果”设置。" : "下方为录音条尺寸适配 · 使用模拟电平")
        Spacer()
        Button("参考来源与复现说明") { showSources = true }.buttonStyle(.plain)
          .popover(isPresented: $showSources) { sources.padding(24).frame(width: 430) }
      }.font(.system(size: 11)).foregroundStyle(.secondary)
    }
    .padding(.horizontal, 30).padding(.top, 48).padding(.bottom, 26)
    .frame(width: 1040, height: 750)
    .background(background)
    .preferredColorScheme(dark ? .dark : .light)
  }

  private func effectCard(index: Int, time: Double, level: Double, snapshot: ClassicWaveSnapshot,
    enlarged: Bool) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 9) {
        Text("0\(index + 1)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
        Text(["经典横向波形", "Siri 球体", "Apple Intelligence"][index])
          .font(.system(size: 14, weight: .semibold))
        Spacer()
      }.padding(20)
      ZStack {
        if index == 0 {
          ClassicSiriWave(snapshot: snapshot, level: level, dark: dark)
            .frame(width: enlarged ? 820 : 288, height: enlarged ? 245 : 200)
        } else if index == 1 {
          SiriOrb(time: time, level: level).frame(width: enlarged ? 258 : 190, height: enlarged ? 258 : 190)
        } else {
          phonePreview(time: time, level: level)
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      Text(["独立波峰 · 上下镜像 · RGB 叠色", "球壳内的光瓣交叠与旋转", "沿屏幕边缘流动，向内扩散"][index])
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity).padding(.vertical, 19)
    }
    .frame(maxWidth: .infinity)
    .background(dark ? Color.black.opacity(0.45) : Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22))
    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.07)))
  }

  private func phonePreview(time: Double, level: Double) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 29).fill(Color(red: 0.035, green: 0.045, blue: 0.075))
      VStack(spacing: 17) {
        Capsule().fill(.black).frame(width: 57, height: 16).padding(.top, 11)
        Spacer()
        Text("9:41").font(.system(size: 36, weight: .light)).foregroundStyle(.white.opacity(0.85))
        Text("星期一 · 9 月 7 日").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
        Spacer()
        Text("正在聆听").font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
        Capsule().fill(.white.opacity(0.7)).frame(width: 63, height: 3).padding(.bottom, 9)
      }
      SiriEdgeGlow(time: time, level: level, cornerRadius: 29)
    }.frame(width: 160, height: 286)
      .clipShape(RoundedRectangle(cornerRadius: 29))
      .overlay(RoundedRectangle(cornerRadius: 29).strokeBorder(.white.opacity(0.13), lineWidth: 0.5))
  }

  private func miniature(index: Int, time: Double, level: Double, snapshot: ClassicWaveSnapshot) -> some View {
    VStack(spacing: 9) {
      HStack(spacing: 10) {
        Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 24)
        if index == 0 {
          ClassicSiriWave(snapshot: snapshot, level: level, dark: dark).frame(width: 92, height: 32)
        } else if index == 1 {
          SiriOrb(time: time, level: level).frame(width: 32, height: 32)
        } else {
          Text("正在聆听…").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 92, height: 32)
        }
        Text("00:12").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        Image(systemName: "stop.circle.fill").font(.system(size: 21)).foregroundStyle(Color.accentColor)
      }
      .padding(.horizontal, 12).padding(.vertical, 7)
      .background(.regularMaterial, in: Capsule())
      .overlay {
        if index == 2 { SiriEdgeGlow(time: time, level: level, cornerRadius: 24).clipShape(Capsule()) }
      }
      Text(["电平区域 · 92 × 32 pt", "状态图标 · 32 × 32 pt", "录音胶囊边缘"][index])
        .font(.system(size: 10)).foregroundStyle(.tertiary)
    }.frame(maxWidth: .infinity)
  }

  private var sources: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("参考来源").font(.headline)
      Text("这是公开算法与画面的复现，不是 Apple 的系统 Siri 控件或源码。")
        .font(.callout).fixedSize(horizontal: false, vertical: true)
      Link("横向：SiriWave · iOS 9 算法", destination: URL(string: "https://github.com/kopiro/siriwave")!)
      Link("球体：Apple 的 iOS 14 官方画面", destination: URL(string: "https://www.apple.com/newsroom/2020/06/apple-reimagines-the-iphone-experience-with-ios-14/")!)
      Link("球体：Orb 的原生 SwiftUI 分层实现", destination: URL(string: "https://github.com/metasidd/Orb")!)
      Link("边缘：Apple Intelligence 官方演示", destination: URL(string: "https://www.apple.com/newsroom/2024/06/introducing-apple-intelligence-for-iphone-ipad-and-mac/")!)
      Link("边缘：AppleIntelligenceGlowEffect", destination: URL(string: "https://github.com/jacobamobin/AppleIntelligenceGlowEffect")!)
    }
  }

  private func speechLevel(at time: Double) -> Double {
    let t = time.truncatingRemainder(dividingBy: 8)
    let syllables: [(Double, Double, Double)] = [
      (0.45, 0.7, 0.2), (0.95, 1, 0.24), (1.55, 0.85, 0.28), (2.25, 1, 0.2),
      (2.8, 0.7, 0.32), (4.6, 0.65, 0.3), (5.2, 1, 0.22), (5.8, 0.8, 0.3), (6.5, 0.5, 0.3)
    ]
    return min(1, syllables.reduce(0) { sum, s in sum + s.1 * exp(-0.5 * pow((t - s.0) / s.2, 2)) })
  }
}
