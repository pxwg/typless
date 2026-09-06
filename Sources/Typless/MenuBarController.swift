import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
  private let coordinator: AppCoordinator
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let menu = NSMenu()

  init(coordinator: AppCoordinator) {
    self.coordinator = coordinator
    super.init()
    let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Typless")
    image?.isTemplate = true
    statusItem.button?.image = image
    statusItem.button?.toolTip = "Typless · Fn 开始语音输入"
    menu.delegate = self
    statusItem.menu = menu
    coordinator.onMenuStateChanged = { [weak self] in
      self?.statusItem.button?.appearsDisabled = self?.coordinator.isPaused ?? false
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let status = NSMenuItem(title: "Typless · " + coordinator.statusTitle, action: nil, keyEquivalent: "")
    status.isEnabled = false
    menu.addItem(status)
    if let message = coordinator.recentStatus {
      let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    }
    menu.addItem(.separator())
    add("打开 Typless", action: #selector(home))
    add("历史记录", action: #selector(history))
    add("设置…", action: #selector(settings), key: ",")
    menu.addItem(.separator())
    let copy = add("复制上次转写", action: #selector(copyTranscript))
    copy.isEnabled = coordinator.lastTranscript != nil
    add(coordinator.isPaused ? "恢复监听" : "暂停监听", action: #selector(pause))
    menu.addItem(.separator())
    add("退出 Typless", action: #selector(quit), key: "q")
  }

  @discardableResult private func add(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = self
    menu.addItem(item)
    return item
  }
  @objc private func home() { coordinator.presentHome() }
  @objc private func history() { coordinator.presentHome(); coordinator.selectedPage = .history }
  @objc private func settings() { coordinator.presentSettings() }
  @objc private func copyTranscript() { coordinator.copyLastTranscript() }
  @objc private func pause() { coordinator.setPaused(!coordinator.isPaused) }
  @objc private func quit() { NSApp.terminate(nil) }
}
