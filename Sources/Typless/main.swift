import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var coordinator: AppCoordinator?
  private var menuBarController: MenuBarController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    configureMenus()
    let coordinator = AppCoordinator(
      preferences: AppPreferences(),
      permissionManager: PermissionManager()
    )
    self.coordinator = coordinator
    menuBarController = MenuBarController(coordinator: coordinator)

    DispatchQueue.main.async {
      let arguments = Set(CommandLine.arguments)
      if arguments.contains("--show-settings") {
        coordinator.presentSettings()
      } else if arguments.contains("--preview-overlay") {
        coordinator.previewOverlay()
      } else {
        coordinator.showOnboardingIfNeeded()
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    coordinator?.shutdown()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    coordinator?.presentHome()
    return true
  }

  @objc private func showSettings() { coordinator?.presentSettings() }

  private func configureMenus() {
    let main = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu(title: "Typless")
    let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
    settings.target = self
    appMenu.addItem(settings)
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "退出 Typless", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    main.addItem(appItem)
    let edit = NSMenuItem()
    let editMenu = NSMenu(title: "编辑")
    for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
      editMenu.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
    }
    edit.submenu = editMenu
    main.addItem(edit)
    NSApp.mainMenu = main
  }
}

MainActor.assumeIsolated {
  let application = NSApplication.shared
  let delegate = AppDelegate()
  application.delegate = delegate
  withExtendedLifetime(delegate) {
    application.run()
  }
}
