import AppKit
import ApplicationServices
import XCTest
@testable import Typless

@MainActor
private final class FakeSelectedTextAccessibility: SelectedTextAccessibility {
  var queryResult: (error: AXError, settable: Bool) = (.success, true)
  var writeResult: AXError = .success
  var queryCount = 0
  var writes: [String] = []
  var elements: [AXUIElement] = []
  var onQuery: (() -> Void)?
  var onWrite: (() -> Void)?

  func isSettable(_ element: AXUIElement) async -> (error: AXError, settable: Bool) {
    queryCount += 1
    onQuery?()
    return queryResult
  }

  func replaceSelection(_ text: String, in element: AXUIElement) async -> AXError {
    writes.append(text)
    elements.append(element)
    onWrite?()
    return writeResult
  }
}

@MainActor
private final class FakeClipboardPaste: ClipboardPasting {
  var calls: [String] = []
  var posted = true
  var beforePosting: (() -> Void)?

  func inject(_ text: String, isValidTarget: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
    calls.append(text)
    beforePosting?()
    completion(isValidTarget() && posted)
  }
}

final class TextInjectorTests: XCTestCase {
  @MainActor private func target(secure: Bool = false, editable: Bool = true) -> InputTarget {
    // Tests never query or write another app: this handle is consumed only by fakes.
    InputTarget(element: AXUIElementCreateApplication(getpid()), processIdentifier: getpid(),
      isSecure: secure, isEditable: editable, screen: nil)
  }

  @MainActor func testAccessibilitySuccessNeverCallsPasteAndKeepsExactUnicodeText() async {
    let access = FakeSelectedTextAccessibility()
    let paste = FakeClipboardPaste()
    let injector = TextInjector(accessibility: access, paste: paste)
    let target = target()
    let text = "你好 👩🏽‍💻，Qwen！\n第二段。"
    let result = await injector.inject(text, into: target, isValidTarget: { true })
    XCTAssertEqual(result, .accessibility)
    XCTAssertEqual(access.writes, [text])
    XCTAssertTrue(CFEqual(access.elements.first, target.element))
    XCTAssertTrue(paste.calls.isEmpty, "Successful AX writes must not touch the paste/clipboard path")
  }

  @MainActor func testReadOnlySelectionUsesPasteWithoutAttemptingAXWrite() async {
    let access = FakeSelectedTextAccessibility()
    access.queryResult = (.success, false)
    let paste = FakeClipboardPaste()
    let result = await TextInjector(accessibility: access, paste: paste).inject("Hello", into: target(), isValidTarget: { true })
    XCTAssertEqual(result, .pastePosted)
    XCTAssertTrue(access.writes.isEmpty)
    XCTAssertEqual(paste.calls, ["Hello"])
  }

  @MainActor func testUnsupportedAttributeAndUnimplementedProbeFallBackOnce() async {
    for error: AXError in [.attributeUnsupported, .notImplemented] {
      let access = FakeSelectedTextAccessibility()
      access.queryResult = (error, false)
      let paste = FakeClipboardPaste()
      let result = await TextInjector(accessibility: access, paste: paste).inject("Hello", into: target(), isValidTarget: { true })
      XCTAssertEqual(result, .pastePosted)
      XCTAssertTrue(access.writes.isEmpty)
      XCTAssertEqual(paste.calls.count, 1)
    }
  }

  @MainActor func testExplicitSetterRefusalFallsBackOnce() async {
    for error: AXError in [.attributeUnsupported, .notImplemented] {
      let access = FakeSelectedTextAccessibility()
      access.writeResult = error
      let paste = FakeClipboardPaste()
      let result = await TextInjector(accessibility: access, paste: paste).inject("Hello", into: target(), isValidTarget: { true })
      XCTAssertEqual(result, .pastePosted)
      XCTAssertEqual(access.writes.count, 1)
      XCTAssertEqual(paste.calls.count, 1)
    }
  }

  @MainActor func testUncertainWriteIsNeverRetriedOrPasted() async {
    for error: AXError in [.cannotComplete, .failure, .noValue] {
      let access = FakeSelectedTextAccessibility()
      access.writeResult = error
      let paste = FakeClipboardPaste()
      let result = await TextInjector(accessibility: access, paste: paste).inject("Hello", into: target(), isValidTarget: { true })
      XCTAssertEqual(result, .uncertain)
      XCTAssertEqual(access.writes.count, 1)
      XCTAssertTrue(paste.calls.isEmpty)
    }
  }

  @MainActor func testFailedProbeDoesNotPretendTheAttributeIsUnsupported() async {
    let access = FakeSelectedTextAccessibility()
    access.queryResult = (.cannotComplete, false)
    let paste = FakeClipboardPaste()
    let result = await TextInjector(accessibility: access, paste: paste).inject("Hello", into: target(), isValidTarget: { true })
    XCTAssertEqual(result, .failed)
    XCTAssertTrue(access.writes.isEmpty)
    XCTAssertTrue(paste.calls.isEmpty)
  }

  @MainActor func testInvalidWriteArgumentsFailWithoutPaste() async {
    let access = FakeSelectedTextAccessibility()
    access.writeResult = .illegalArgument
    let paste = FakeClipboardPaste()
    let result = await TextInjector(accessibility: access, paste: paste).inject("Hello", into: target(), isValidTarget: { true })
    XCTAssertEqual(result, .failed)
    XCTAssertEqual(access.writes.count, 1)
    XCTAssertTrue(paste.calls.isEmpty)
  }

  @MainActor func testPermissionAndInvalidTargetErrorsDoNotPaste() async {
    for (error, expected): (AXError, TextInjectionResult) in [(.apiDisabled, .permissionDenied), (.invalidUIElement, .targetChanged)] {
      for failAtProbe in [true, false] {
        let access = FakeSelectedTextAccessibility()
        if failAtProbe { access.queryResult = (error, false) } else { access.writeResult = error }
        let paste = FakeClipboardPaste()
        let result = await TextInjector(accessibility: access, paste: paste).inject("Hello", into: target(), isValidTarget: { true })
        XCTAssertEqual(result, expected)
        XCTAssertTrue(paste.calls.isEmpty)
      }
    }
  }

  @MainActor func testEmptySecureAndNoneditableTargetsNeverReachAnInsertionBackend() async {
    for (text, target, expected) in [
      ("", target(), TextInjectionResult.empty),
      ("Hello", target(secure: true), .secureField),
      ("Hello", target(editable: false), .noTarget),
    ] {
      let access = FakeSelectedTextAccessibility()
      let paste = FakeClipboardPaste()
      let result = await TextInjector(accessibility: access, paste: paste).inject(text, into: target, isValidTarget: { true })
      XCTAssertEqual(result, expected)
      XCTAssertEqual(access.queryCount, 0)
      XCTAssertTrue(access.writes.isEmpty)
      XCTAssertTrue(paste.calls.isEmpty)
    }
  }

  @MainActor func testLostFocusBeforeProbeDoesNotReadOrWriteTarget() async {
    let access = FakeSelectedTextAccessibility()
    let paste = FakeClipboardPaste()
    let result = await TextInjector(accessibility: access, paste: paste).inject("Hello", into: target(), isValidTarget: { false })
    XCTAssertEqual(result, .targetChanged)
    XCTAssertEqual(access.queryCount, 0)
    XCTAssertTrue(paste.calls.isEmpty)
  }

  @MainActor func testCancellationDuringProbePreventsBothAXAndPaste() async {
    for settable in [true, false] {
      var valid = true
      let access = FakeSelectedTextAccessibility()
      access.queryResult = (.success, settable)
      access.onQuery = { valid = false }
      let paste = FakeClipboardPaste()
      let result = await TextInjector(accessibility: access, paste: paste).inject("Hello", into: target(), isValidTarget: { valid })
      XCTAssertEqual(result, .targetChanged)
      XCTAssertTrue(access.writes.isEmpty)
      XCTAssertTrue(paste.calls.isEmpty)
    }
  }

  @MainActor func testCancellationDuringRejectedWritePreventsFallback() async {
    var valid = true
    let access = FakeSelectedTextAccessibility()
    access.writeResult = .attributeUnsupported
    access.onWrite = { valid = false }
    let paste = FakeClipboardPaste()
    let result = await TextInjector(accessibility: access, paste: paste).inject("Hello", into: target(), isValidTarget: { valid })
    XCTAssertEqual(result, .targetChanged)
    XCTAssertEqual(access.writes.count, 1)
    XCTAssertTrue(paste.calls.isEmpty)
  }

  @MainActor func testPasteRetainsItsLastMomentFocusGuard() async {
    var valid = true
    let access = FakeSelectedTextAccessibility()
    access.queryResult = (.success, false)
    let paste = FakeClipboardPaste()
    paste.beforePosting = { valid = false }
    let result = await TextInjector(accessibility: access, paste: paste).inject("Hello", into: target(), isValidTarget: { valid })
    XCTAssertEqual(result, .targetChanged)
    XCTAssertEqual(paste.calls.count, 1)
  }

  @MainActor func testFailedPasteIsReportedWithoutRetry() async {
    let access = FakeSelectedTextAccessibility()
    access.queryResult = (.success, false)
    let paste = FakeClipboardPaste()
    paste.posted = false
    let result = await TextInjector(accessibility: access, paste: paste).inject("Hello", into: target(), isValidTarget: { true })
    XCTAssertEqual(result, .failed)
    XCTAssertTrue(access.writes.isEmpty)
    XCTAssertEqual(paste.calls.count, 1)
  }

  @MainActor func testNativeTextViewSelectedTextSetterInsertsAtCaret() {
    let view = NSTextView()
    view.string = "前后"
    view.setSelectedRange(NSRange(location: 1, length: 0))
    view.setAccessibilitySelectedText("你好👋\n")
    XCTAssertEqual(view.string, "前你好👋\n后")
  }

  @MainActor func testNativeTextViewSelectedTextSetterReplacesOnlySelection() {
    let view = NSTextView()
    view.string = "前旧内容后"
    view.setSelectedRange(NSRange(location: 1, length: 3))
    view.setAccessibilitySelectedText("新内容")
    XCTAssertEqual(view.string, "前新内容后")
  }
}
