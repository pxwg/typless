import AppKit
import ApplicationServices

enum TextInjectionResult: Equatable {
  case accessibility
  /// Cmd+V was posted; this is not an acknowledgement from the target editor.
  case pastePosted
  case empty, noTarget, secureField, targetChanged, permissionDenied, failed
  /// A write was attempted, but may or may not have been applied. Never retry it.
  case uncertain
}

@MainActor
protocol SelectedTextAccessibility {
  func isSettable(_ element: AXUIElement) async -> (error: AXError, settable: Bool)
  func replaceSelection(_ text: String, in element: AXUIElement) async -> AXError
}

@MainActor
protocol ClipboardPasting {
  func inject(_ text: String, isValidTarget: @escaping () -> Bool, completion: @escaping (Bool) -> Void)
}

extension PasteInjector: ClipboardPasting {}

/// AX messaging can wait on another application. Keep it off the main run loop
/// so Fn/Esc and cancellation remain responsive, and bound each request's wait.
@MainActor
final class SystemSelectedTextAccessibility: SelectedTextAccessibility {
  private let queue = DispatchQueue(label: "com.typless.accessibility-write", qos: .userInitiated)

  // A retained AX proxy, not an AppKit view. Our messaging operations are
  // serialized on queue; no mutable Swift state crosses the queue boundary.
  private struct ElementReference: @unchecked Sendable {
    let value: AXUIElement
  }

  func isSettable(_ element: AXUIElement) async -> (error: AXError, settable: Bool) {
    let reference = ElementReference(value: element)
    return await withCheckedContinuation { continuation in
      queue.async {
        let timeoutError = AXUIElementSetMessagingTimeout(reference.value, 1)
        guard timeoutError == .success else {
          continuation.resume(returning: (timeoutError, false))
          return
        }
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(reference.value, kAXSelectedTextAttribute as CFString, &settable)
        continuation.resume(returning: (error, settable.boolValue))
      }
    }
  }

  func replaceSelection(_ text: String, in element: AXUIElement) async -> AXError {
    let reference = ElementReference(value: element)
    return await withCheckedContinuation { continuation in
      queue.async {
        let timeoutError = AXUIElementSetMessagingTimeout(reference.value, 1)
        guard timeoutError == .success else {
          continuation.resume(returning: timeoutError)
          return
        }
        // Do not set AXValue: that can replace the entire field, losing content
        // or formatting. The target owns insertion/replacement of its selection.
        continuation.resume(returning: AXUIElementSetAttributeValue(
          reference.value, kAXSelectedTextAttribute as CFString, text as CFString
        ))
      }
    }
  }
}

@MainActor
final class TextInjector {
  private let accessibility: any SelectedTextAccessibility
  private let paste: any ClipboardPasting

  init() {
    accessibility = SystemSelectedTextAccessibility()
    paste = PasteInjector()
  }

  init(accessibility: any SelectedTextAccessibility, paste: any ClipboardPasting) {
    self.accessibility = accessibility
    self.paste = paste
  }

  func inject(_ text: String, into target: InputTarget, isValidTarget: @escaping () -> Bool) async -> TextInjectionResult {
    // Empty output must never delete the target's selected text.
    guard !text.isEmpty else { return .empty }
    guard !target.isSecure else { return .secureField }
    guard target.isEditable else { return .noTarget }
    guard isValidTarget() else { return .targetChanged }

    let availability = await accessibility.isSettable(target.element)
    guard isValidTarget() else { return .targetChanged }
    switch availability.error {
    case .success, .attributeUnsupported, .notImplemented: break
    case .invalidUIElement: return .targetChanged
    case .apiDisabled: return .permissionDenied
    default: return .failed // A failed probe isn't evidence that AX is unsupported.
    }

    if availability.error == .success, availability.settable {
      let error = await accessibility.replaceSelection(text, in: target.element)
      switch error {
      case .success: return .accessibility
      case .attributeUnsupported, .notImplemented: break // Explicit refusal: safe to fall back.
      case .invalidUIElement: return .targetChanged
      case .apiDisabled: return .permissionDenied
      case .illegalArgument: return .failed
      default: return .uncertain // Includes timeout/cannotComplete and generic failure.
      }
    }

    // The user may cancel or move focus while AX is probing/writing. Never paste
    // into a different field, and never fall back after a successful/uncertain write.
    guard isValidTarget() else { return .targetChanged }
    let posted = await withCheckedContinuation { continuation in
      paste.inject(text, isValidTarget: isValidTarget) { continuation.resume(returning: $0) }
    }
    return posted ? .pastePosted : (isValidTarget() ? .failed : .targetChanged)
  }
}
