import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum InputEditability: Equatable {
  case editable, unavailable, nonEditable, secure

  init(role: String?, subrole: String? = nil, enabled: Bool? = nil,
    explicitlyEditable: Bool? = nil, selectedTextSettable: Bool = false,
    secureInputEnabled: Bool = false)
  {
    if secureInputEnabled || subrole == (kAXSecureTextFieldSubrole as String) {
      self = .secure
    } else if enabled == false || explicitlyEditable == false {
      self = .nonEditable
    } else if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? "")
      || explicitlyEditable == true || selectedTextSettable {
      self = .editable
    } else if [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole,
      kAXSliderRole, kAXMenuItemRole, kAXMenuBarItemRole].contains(role ?? "") {
      self = .nonEditable
    } else {
      // Missing AX information is not evidence that the keyboard cannot type.
      self = .unavailable
    }
  }
}

struct InputTarget {
  let element: AXUIElement?
  let window: AXUIElement?
  let processIdentifier: pid_t
  let editability: InputEditability
  let screen: NSScreen?

  var isSecure: Bool { editability == .secure }

  var allowsDictation: Bool {
    switch editability {
    case .editable: return element != nil
    case .unavailable: return window != nil
    case .nonEditable, .secure: return false
    }
  }

  func matches(_ current: InputTarget) -> Bool {
    guard allowsDictation, current.allowsDictation,
      current.processIdentifier == processIdentifier
    else { return false }

    if let window {
      guard let currentWindow = current.window, CFEqual(window, currentWindow) else { return false }
    }
    if editability == .editable {
      // Never weaken a precise target if its AX information disappears later.
      guard current.editability == .editable, let element, let currentElement = current.element else { return false }
      return CFEqual(element, currentElement)
    }
    return true
  }
}

@MainActor
enum InputTargetLocator {
  static func focusedTarget() -> InputTarget? {
    guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let pid = app.processIdentifier
    let application = AXUIElementCreateApplication(pid)
    let element = elementAttribute(kAXFocusedUIElementAttribute, of: application)
    let window = element.flatMap { elementAttribute(kAXWindowAttribute, of: $0) }
      ?? elementAttribute(kAXFocusedWindowAttribute, of: application)

    var selectedTextSettable = DarwinBoolean(false)
    if let element {
      var elementPID: pid_t = 0
      guard AXUIElementGetPid(element, &elementPID) == .success, elementPID == pid else { return nil }
      _ = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selectedTextSettable)
    }
    let editability = InputEditability(
      role: element.flatMap { stringAttribute(kAXRoleAttribute, of: $0) },
      subrole: element.flatMap { stringAttribute(kAXSubroleAttribute, of: $0) },
      enabled: element.flatMap { boolAttribute(kAXEnabledAttribute, of: $0) },
      explicitlyEditable: element.flatMap { boolAttribute("AXEditable", of: $0) },
      selectedTextSettable: selectedTextSettable.boolValue,
      secureInputEnabled: IsSecureEventInputEnabled()
    )
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }

    return InputTarget(
      element: element,
      window: window,
      processIdentifier: pid,
      editability: editability,
      screen: window.flatMap { screenContaining(window: $0) }
    )
  }

  static func isStillFocused(_ target: InputTarget) -> Bool {
    guard let current = focusedTarget() else { return false }
    return target.matches(current)
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

  private static func boolAttribute(_ attribute: String, of element: AXUIElement) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? Bool
  }

  private static func elementAttribute(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
      let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return (value as! AXUIElement)
  }

  private static func screenContaining(window: AXUIElement) -> NSScreen? {
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
