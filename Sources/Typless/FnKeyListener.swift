import Carbon.HIToolbox
import CoreGraphics

private func fnEventTapCallback(
  proxy _: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else {
    return Unmanaged.passUnretained(event)
  }
  let listener = Unmanaged<FnKeyListener>.fromOpaque(userInfo).takeUnretainedValue()
  return listener.handle(type: type, event: event)
}

final class FnKeyListener {
  var onFnDown: (() -> Void)?
  var onFnUp: (() -> Void)?
  var onCancel: (() -> Void)?
  var isSessionActive = false

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var fnIsDown = false
  private var shouldListen = false

  var isRunning: Bool {
    eventTap.map(CGEvent.tapIsEnabled(tap:)) ?? false
  }

  @discardableResult
  func start() -> Bool {
    shouldListen = true
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: true)
      return true
    }

    let eventTypes: [CGEventType] = [.flagsChanged, .keyDown, .keyUp]
    let mask = eventTypes.reduce(CGEventMask(0)) {
      $0 | (CGEventMask(1) << $1.rawValue)
    }
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: fnEventTapCallback,
        userInfo: pointer
      )
    else {
      return false
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    eventTap = tap
    runLoopSource = source
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }

  func stop() {
    shouldListen = false
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
    }
    fnIsDown = false
  }

  fileprivate func handle(
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if fnIsDown && isSessionActive {
        DispatchQueue.main.async { [weak self] in self?.onCancel?() }
      }
      fnIsDown = false
      if shouldListen, let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    if type == .flagsChanged, keyCode == CGKeyCode(kVK_Function) {
      let isDown = event.flags.contains(.maskSecondaryFn)
      if isDown, !fnIsDown {
        fnIsDown = true
        DispatchQueue.main.async { [weak self] in self?.onFnDown?() }
      } else if !isDown, fnIsDown {
        fnIsDown = false
        DispatchQueue.main.async { [weak self] in self?.onFnUp?() }
      }
      return nil
    }

    if isSessionActive, type == .keyDown, keyCode == CGKeyCode(kVK_Escape) {
      DispatchQueue.main.async { [weak self] in self?.onCancel?() }
      return nil
    }

    return Unmanaged.passUnretained(event)
  }
}
