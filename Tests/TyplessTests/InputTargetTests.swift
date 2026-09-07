import ApplicationServices
import XCTest
@testable import Typless

final class InputTargetTests: XCTestCase {
  func testAbsentOrOpaqueAccessibilityInformationDoesNotMeanNonEditable() {
    for role: String? in [nil, "", kAXWindowRole, kAXApplicationRole, kAXGroupRole, "AXUnknown"] {
      XCTAssertEqual(InputEditability(role: role), .unavailable)
    }
    XCTAssertTrue(target(.unavailable, elementID: nil).allowsDictation)
    XCTAssertFalse(target(.unavailable, elementID: nil, windowID: nil).allowsDictation,
      "An opaque target still needs an identifiable window")
  }

  func testStandardAndCustomTextEditorsAreRecognized() {
    for role in [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole] {
      XCTAssertEqual(InputEditability(role: role), .editable)
    }
    XCTAssertEqual(InputEditability(role: kAXGroupRole, explicitlyEditable: true), .editable)
    XCTAssertEqual(InputEditability(role: kAXGroupRole, selectedTextSettable: true), .editable)
  }

  func testKnownControlsAndExplicitReadOnlyFieldsDoNotUseWindowFallback() {
    for role in [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole,
      kAXSliderRole, kAXMenuItemRole, kAXMenuBarItemRole] {
      XCTAssertEqual(InputEditability(role: role), .nonEditable)
    }
    XCTAssertEqual(InputEditability(role: kAXTextFieldRole, enabled: false), .nonEditable)
    XCTAssertEqual(InputEditability(role: kAXTextAreaRole, explicitlyEditable: false,
      selectedTextSettable: true), .nonEditable)
    XCTAssertFalse(target(.nonEditable).allowsDictation)
  }

  func testSecureInputOverridesBothEditableAndUnavailableInformation() {
    XCTAssertEqual(InputEditability(role: kAXTextFieldRole, subrole: kAXSecureTextFieldSubrole,
      selectedTextSettable: true), .secure)
    XCTAssertEqual(InputEditability(role: nil, secureInputEnabled: true), .secure)
    XCTAssertEqual(InputEditability(role: kAXTextAreaRole, secureInputEnabled: true), .secure)
    XCTAssertTrue(target(.secure).isSecure)
    XCTAssertFalse(target(.secure).allowsDictation)
  }

  func testOpaqueTargetsRequireTheSameAppAndWindowAtInsertion() {
    let original = target(.unavailable, elementID: nil)
    XCTAssertTrue(original.matches(target(.unavailable, elementID: nil)))
    XCTAssertFalse(original.matches(target(.unavailable, elementID: nil, pid: 43)))
    XCTAssertFalse(original.matches(target(.unavailable, elementID: nil, windowID: 202)))
    XCTAssertFalse(original.matches(target(.unavailable, elementID: nil, windowID: nil)))
  }

  func testOpaqueTargetsCanGainTextMetadataButCannotBecomeBlocked() {
    let original = target(.unavailable, elementID: nil)
    XCTAssertTrue(original.matches(target(.editable)))
    XCTAssertFalse(original.matches(target(.nonEditable)))
    XCTAssertFalse(original.matches(target(.secure)))
    XCTAssertFalse(target(.secure).matches(target(.editable)))
  }

  func testPreciseTargetsNeverDowngradeToWindowOnlyValidation() {
    let original = target(.editable)
    XCTAssertTrue(original.matches(target(.editable)))
    XCTAssertFalse(original.matches(target(.editable, elementID: 102)))
    XCTAssertFalse(original.matches(target(.editable, pid: 43)))
    XCTAssertFalse(original.matches(target(.editable, windowID: 202)))
    XCTAssertFalse(original.matches(target(.editable, windowID: nil)))
    XCTAssertFalse(original.matches(target(.unavailable)))
    XCTAssertFalse(original.matches(target(.secure)))
    XCTAssertFalse(target(.editable, elementID: nil).allowsDictation)
  }

  func testPreciseTargetsCanUseElementIdentityWithoutWindowMetadata() {
    let original = target(.editable, windowID: nil)
    XCTAssertTrue(original.matches(target(.editable, windowID: nil)))
    XCTAssertFalse(original.matches(target(.editable, elementID: 102, windowID: nil)))
  }

  private func target(_ editability: InputEditability, elementID: pid_t? = 101,
    pid: pid_t = 42, windowID: pid_t? = 201) -> InputTarget
  {
    // Opaque AX handles provide stable identities without querying other apps,
    // changing focus, or requiring Accessibility permission in unit tests.
    InputTarget(
      element: elementID.map { AXUIElementCreateApplication($0) },
      window: windowID.map { AXUIElementCreateApplication($0) },
      processIdentifier: pid, editability: editability, screen: nil
    )
  }
}
