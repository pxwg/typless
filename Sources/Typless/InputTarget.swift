import AppKit
import ApplicationServices

struct InputTarget {
  let element: AXUIElement
  let processIdentifier: pid_t
  let isSecure: Bool
  let isEditable: Bool
  let screen: NSScreen?
}

enum InputTargetLocator {
  static func focusedTarget() -> InputTarget? {
    let system = AXUIElementCreateSystemWide()
    var focusedValue: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
      system,
      kAXFocusedUIElementAttribute as CFString,
      &focusedValue
    )
    guard error == .success, let focusedValue else {
      return nil
    }

    let element = focusedValue as! AXUIElement
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else {
      return nil
    }

    let role = stringAttribute(kAXRoleAttribute, of: element) ?? ""
    let subrole = stringAttribute(kAXSubroleAttribute, of: element) ?? ""
    let secure = subrole == (kAXSecureTextFieldSubrole as String)

    var selectedTextSettable = DarwinBoolean(false)
    let settableError = AXUIElementIsAttributeSettable(
      element,
      kAXSelectedTextAttribute as CFString,
      &selectedTextSettable
    )
    let knownEditableRoles: Set<String> = [
      kAXTextFieldRole as String,
      kAXTextAreaRole as String,
      kAXComboBoxRole as String,
    ]
    let editable =
      secure
      || knownEditableRoles.contains(role)
      || (settableError == .success && selectedTextSettable.boolValue)

    return InputTarget(
      element: element,
      processIdentifier: pid,
      isSecure: secure,
      isEditable: editable,
      screen: screenContaining(element: element)
    )
  }

  static func isStillFocused(_ target: InputTarget) -> Bool {
    guard let current = focusedTarget(), current.isEditable, !current.isSecure else {
      return false
    }
    return current.processIdentifier == target.processIdentifier
      && CFEqual(current.element, target.element)
  }

  static func fallbackScreen() -> NSScreen? {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
  }

  private static func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
      return nil
    }
    return value as? String
  }

  private static func screenContaining(element: AXUIElement) -> NSScreen? {
    var windowValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        kAXWindowAttribute as CFString,
        &windowValue
      ) == .success,
      let windowValue
    else {
      return nil
    }

    let window = windowValue as! AXUIElement
    guard
      let position = pointAttribute(kAXPositionAttribute, of: window),
      let size = sizeAttribute(kAXSizeAttribute, of: window),
      let primary = NSScreen.screens.first
    else {
      return nil
    }

    let cocoaPoint = CGPoint(
      x: position.x + size.width / 2,
      y: primary.frame.maxY - (position.y + size.height / 2)
    )
    return NSScreen.screens.first(where: { $0.frame.contains(cocoaPoint) })
  }

  private static func pointAttribute(_ attribute: String, of element: AXUIElement) -> CGPoint? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else {
      return nil
    }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    guard
      AXValueGetType(axValue) == .cgPoint
    else {
      return nil
    }
    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else {
      return nil
    }
    return point
  }

  private static func sizeAttribute(_ attribute: String, of element: AXUIElement) -> CGSize? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else {
      return nil
    }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    guard
      AXValueGetType(axValue) == .cgSize
    else {
      return nil
    }
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else {
      return nil
    }
    return size
  }
}
