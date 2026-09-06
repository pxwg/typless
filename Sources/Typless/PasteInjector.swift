import AppKit
import Carbon.HIToolbox
import CoreGraphics

final class PasteInjector {
  private struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
      items = (pasteboard.pasteboardItems ?? []).map { item in
        Dictionary(
          uniqueKeysWithValues: item.types.compactMap { type in
            item.data(forType: type).map { (type, $0) }
          }
        )
      }
    }

    func restore(to pasteboard: NSPasteboard) {
      pasteboard.clearContents()
      let pasteboardItems = items.map { stored -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, data) in stored {
          item.setData(data, forType: type)
        }
        return item
      }
      if !pasteboardItems.isEmpty {
        pasteboard.writeObjects(pasteboardItems)
      }
    }
  }

  func inject(_ text: String, isValidTarget: @escaping () -> Bool = { true }, completion: @escaping (Bool) -> Void) {
    let pasteboard = NSPasteboard.general
    let snapshot = ClipboardSnapshot(pasteboard: pasteboard)
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
      snapshot.restore(to: pasteboard)
      completion(false)
      return
    }
    let ownedChangeCount = pasteboard.changeCount

    // Keep the user's input method selected. Paste the completed text as-is,
    // retaining the last-moment focus check and clipboard ownership guard.
    let posted = isValidTarget() && postCommandV()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      if pasteboard.changeCount == ownedChangeCount {
        snapshot.restore(to: pasteboard)
      }
      completion(posted)
    }
  }

  private func postCommandV() -> Bool {
    guard
      let source = CGEventSource(stateID: .combinedSessionState),
      let keyDown = CGEvent(
        keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
      let keyUp = CGEvent(
        keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
    else {
      return false
    }
    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    return true
  }
}
