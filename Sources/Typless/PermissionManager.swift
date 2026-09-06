import AVFoundation
import AppKit
import ApplicationServices
import Combine

@MainActor
final class PermissionManager: ObservableObject {
  @Published private(set) var accessibilityGranted = false
  @Published private(set) var microphoneGranted = false

  var allGranted: Bool {
    accessibilityGranted && microphoneGranted
  }

  init() {
    refresh()
  }

  func refresh() {
    accessibilityGranted = AXIsProcessTrusted()
    microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
  }

  func requestAll() {
    let options =
      [
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
      ] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)

    Task {
      if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
      }
      refresh()
    }
  }

  func openSystemSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
