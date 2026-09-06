import AppKit
import SwiftUI

@MainActor
final class PermissionsWindowController: NSWindowController {
  private let manager: PermissionManager

  init(manager: PermissionManager) {
    self.manager = manager
    let contentView = PermissionsView(manager: manager)
    let hostingController = NSHostingController(rootView: contentView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = L10n.text("permissions.title")
    window.styleMask = [.titled, .closable]
    window.setContentSize(CGSize(width: 520, height: 440))
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    manager.refresh()
    NSApp.activate(ignoringOtherApps: true)
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }
}

private struct PermissionsView: View {
  @ObservedObject var manager: PermissionManager

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Image(systemName: "waveform.circle.fill")
        .font(.system(size: 42)).foregroundStyle(.indigo)
      VStack(alignment: .leading, spacing: 10) {
        Text("让声音，成为文字。")
          .font(.system(size: 26, weight: .semibold))
        Text("开启两项权限，即可在任何应用自然表达。")
          .font(.system(size: 13)).foregroundStyle(.secondary)
      }

      permissionRow(
        "辅助功能 · 使用 Fn 快捷键与粘贴文字",
        granted: manager.accessibilityGranted
      )
      permissionRow(
        "麦克风 · 录下你想说的话",
        granted: manager.microphoneGranted
      )

      Text("语音由你配置的 Qwen 服务识别。你可以随时在系统设置中关闭权限。")
        .font(.system(size: 11)).foregroundStyle(.tertiary)
      HStack {
        Button(L10n.text("permissions.open_settings")) {
          manager.openSystemSettings()
        }
        Spacer()
        Button(L10n.text("permissions.recheck")) {
          manager.refresh()
        }
        Button(L10n.text("permissions.request")) {
          manager.requestAll()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(30)
    .frame(minWidth: 520, minHeight: 440)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in manager.refresh() }
  }

  @ViewBuilder
  private func permissionRow(_ title: String, granted: Bool) -> some View {
    HStack {
      Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
        .foregroundStyle(granted ? Color.green : Color.orange)
        .font(.title3)
      Text(title)
      Spacer()
      Text(
        granted
          ? L10n.text("permissions.granted")
          : L10n.text("permissions.not_granted")
      )
      .foregroundStyle(.secondary)
    }
    .font(.system(size: 12))
    .padding(14)
    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
  }
}
