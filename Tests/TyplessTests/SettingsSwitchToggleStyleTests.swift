import AppKit
import SwiftUI
import XCTest
@testable import Typless

final class SettingsSwitchToggleStyleTests: XCTestCase {
  @MainActor func testSwitchesStayAtTheTrailingEdgeAcrossWidthsAndAppearances() throws {
    // Render isolated views, not the user's settings window. Constant bindings
    // ensure these checks cannot change preferences or login-item registration.
    for width: CGFloat in [480, 760] {
      for dark in [false, true] {
        let fixture = VStack(spacing: 20) {
          row("交互声音", "开始和结束录音时播放轻提示。", enabled: true)
          Divider()
          row("保存历史记录", "关闭后不保存新记录，已有记录可在历史页清空。", enabled: true)
          Divider()
          row("登录时启动", "开机后，Typless 随时待命。", enabled: false)
        }
        .toggleStyle(SettingsSwitchToggleStyle())
        .padding(24)
        .frame(width: width)
        .background(dark ? Color(white: 0.155) : .white)
        .tint(dark ? Color(red: 0.52, green: 0.61, blue: 1) : Color(red: 0.28, green: 0.38, blue: 0.91))
        .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: fixture)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.setFrameSize(NSSize(width: width, height: host.fittingSize.height))
        host.layoutSubtreeIfNeeded()

        let switches = nativeSwitches(in: host)
        XCTAssertEqual(switches.count, 3)
        for control in switches {
          let rect = control.convert(control.bounds, to: host)
          XCTAssertEqual(rect.maxX, width - 24, accuracy: 2)
          XCTAssertGreaterThan(rect.width, 20)
          XCTAssertLessThan(rect.width, 70, "The native capsule must not stretch to fill the row")
        }
        if let directory = ProcessInfo.processInfo.environment["TYPLESS_LAYOUT_SNAPSHOT_DIR"] {
          let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
          host.cacheDisplay(in: host.bounds, to: bitmap)
          let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
          let url = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("settings-switches-\(Int(width))-\(dark ? "dark" : "light").png")
          try png.write(to: url)
          print("Settings layout snapshot: \(url.path)")
        }
      }
    }
  }

  @MainActor private func row(_ title: String, _ subtitle: String, enabled: Bool) -> some View {
    Toggle(isOn: .constant(enabled)) {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(size: 13, weight: .medium))
        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @MainActor private func nativeSwitches(in view: NSView) -> [NSSwitch] {
    (view as? NSSwitch).map { [$0] } ?? view.subviews.flatMap { nativeSwitches(in: $0) }
  }
}
