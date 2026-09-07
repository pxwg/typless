import AppKit
import Security
import SwiftUI
import XCTest
@testable import Typless

private final class InMemoryKeyStore: APIKeyStoring {
  var value = ""
  var loadCount = 0
  var saveCount = 0
  var deleteCount = 0
  var failure: Error?

  func contains() throws -> Bool {
    if let failure { throw failure }
    return !value.isEmpty
  }
  func load() throws -> String {
    loadCount += 1
    if let failure { throw failure }
    return value
  }
  func save(_ value: String) throws {
    if let failure { throw failure }
    saveCount += 1
    self.value = value
  }
  func delete() throws {
    if let failure { throw failure }
    deleteCount += 1
    value = ""
  }
}

final class QwenSettingsTests: XCTestCase {
  @MainActor
  private func fixture(_ action: (UserDefaults, String, InMemoryKeyStore, QwenSettingsModel) throws -> Void) rethrows {
    let domain = "typless-qwen-test-\(UUID())"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let store = InMemoryKeyStore()
    let model = QwenSettingsModel(preferences: AppPreferences(defaults: defaults), keyStore: store)
    try action(defaults, domain, store, model)
  }

  @MainActor func testPastedKeyAndNonsecretSettingsSurviveRestartWithoutSecretInDefaultsOrUI() throws {
    try fixture { defaults, domain, store, model in
      model.apiKeyInput = " \n synthetic-qwen-secret\n"
      model.region = .singapore
      model.workspaceID = " workspace-1 "
      XCTAssertFalse(model.canTestConnection)
      XCTAssertTrue(model.save())
      XCTAssertEqual(store.value, "synthetic-qwen-secret")
      XCTAssertEqual(model.apiKeyInput, "")
      XCTAssertFalse(model.hasUnsavedChanges)
      XCTAssertTrue(model.canTestConnection)
      XCTAssertEqual(store.loadCount, 0)
      let values = defaults.persistentDomain(forName: domain) ?? [:]
      XCTAssertFalse(String(describing: values).contains("synthetic-qwen-secret"))
      let restarted = QwenSettingsModel(preferences: AppPreferences(defaults: defaults), keyStore: store)
      restarted.refreshCredentialStatus()
      XCTAssertTrue(restarted.hasSavedKey)
      XCTAssertEqual(restarted.apiKeyInput, "")
      XCTAssertEqual(store.loadCount, 0, "Opening settings must not load the saved secret")
      let config = try restarted.configuration()
      XCTAssertEqual(config.apiKey, "synthetic-qwen-secret")
      XCTAssertEqual(config.url.host, "workspace-1.ap-southeast-1.maas.aliyuncs.com")
    }
  }

  @MainActor func testUnsavedDraftsNeverAffectDictationAndBlankDraftKeepsKey() throws {
    try fixture { _, _, store, model in
      model.apiKeyInput = "original"
      XCTAssertTrue(model.save())
      model.apiKeyInput = "replacement"
      model.region = .singapore
      XCTAssertEqual(try model.configuration().apiKey, "original")
      XCTAssertEqual(try model.configuration().url.host, "dashscope.aliyuncs.com")
      XCTAssertFalse(model.canTestConnection)
      model.apiKeyInput = ""
      XCTAssertTrue(model.save())
      XCTAssertEqual(store.value, "original")
      XCTAssertEqual(store.saveCount, 1)
      XCTAssertEqual(store.deleteCount, 0)
      XCTAssertEqual(try model.configuration().url.host, "dashscope-intl.aliyuncs.com")
    }
  }

  @MainActor func testSystemPromptUsesSavedValueAcrossRestartAndBothRequestStages() throws {
    try fixture { defaults, _, _, model in
      XCTAssertEqual(model.systemPrompt, QwenProtocol.defaultSystemPrompt)
      XCTAssertFalse(model.hasUnsavedChanges)
      model.apiKeyInput = "synthetic"
      XCTAssertTrue(model.save())
      let custom = "保留所有语气词和重复。\n只修正标点，保留疑问句。"
      model.systemPrompt = " \n\(custom)\n "
      XCTAssertTrue(model.hasUnsavedChanges)
      XCTAssertFalse(model.canTestConnection)
      XCTAssertEqual(try model.configuration().systemPrompt, "", "Unsaved prompts must not affect dictation")
      XCTAssertTrue(model.save())
      XCTAssertFalse(model.hasUnsavedChanges)
      XCTAssertTrue(model.canTestConnection)

      let preferences = AppPreferences(defaults: defaults)
      XCTAssertEqual(preferences.qwenSystemPrompt, custom)
      let config = try model.configuration()
      XCTAssertEqual(config.systemPrompt, custom)
      let initial = QwenProtocol.session(language: .simplifiedChinese, mode: .polished, dictionary: [], systemPrompt: config.systemPrompt)
      let refinement = try QwenProtocol.refinementInstructions(rawText: "嗯，你好吗？", language: .simplifiedChinese, dictionary: [], systemPrompt: config.systemPrompt)
      for instructions in [try XCTUnwrap(initial["instructions"] as? String), refinement] {
        XCTAssertTrue(instructions.contains(custom))
        XCTAssertFalse(instructions.contains(QwenProtocol.defaultSystemPrompt), "Custom rules replace default editing rules")
        XCTAssertFalse(instructions.contains("无意义的语气词是否已删除"), "The refinement tail must not reintroduce default editing rules")
        XCTAssertTrue(instructions.hasPrefix(QwenProtocol.dictationBoundary))
      }
      model.systemPrompt = "另一个未保存的草稿"
      let restarted = QwenSettingsModel(preferences: preferences, keyStore: InMemoryKeyStore())
      XCTAssertEqual(restarted.systemPrompt, custom)
      XCTAssertFalse(restarted.hasUnsavedChanges)
    }
  }

  @MainActor func testRestoringOrClearingSystemPromptFollowsDefaultAfterSave() throws {
    try fixture { defaults, _, _, model in
      model.apiKeyInput = "synthetic"
      model.systemPrompt = "只修正标点。"
      XCTAssertTrue(model.save())
      model.restoreDefaultSystemPrompt()
      XCTAssertEqual(model.systemPrompt, QwenProtocol.defaultSystemPrompt)
      XCTAssertTrue(model.hasUnsavedChanges)
      XCTAssertEqual(try model.configuration().systemPrompt, "只修正标点。")
      XCTAssertTrue(model.save())
      XCTAssertEqual(try model.configuration().systemPrompt, "")
      XCTAssertEqual(AppPreferences(defaults: defaults).qwenSystemPrompt, "")
      XCTAssertFalse(model.hasUnsavedChanges)

      model.systemPrompt = "保留重复。"
      XCTAssertTrue(model.save())
      model.systemPrompt = " \n\t "
      XCTAssertTrue(model.save())
      XCTAssertEqual(model.systemPrompt, QwenProtocol.defaultSystemPrompt)
      XCTAssertEqual(try model.configuration().systemPrompt, "")
      XCTAssertFalse(model.hasUnsavedChanges)
    }
  }

  @MainActor func testFailedSaveKeepsSavedPromptAndRetainsDraftForRetry() throws {
    try fixture { _, _, store, model in
      model.apiKeyInput = "synthetic"
      model.systemPrompt = "已保存的规则"
      XCTAssertTrue(model.save())
      model.systemPrompt = "新规则"
      model.endpoint = "ws://example.com"
      XCTAssertFalse(model.save())
      XCTAssertEqual(try model.configuration().systemPrompt, "已保存的规则")
      model.endpoint = ""
      store.failure = KeychainError.unexpectedStatus(errSecAuthFailed)
      XCTAssertFalse(model.save())
      store.failure = nil
      XCTAssertEqual(try model.configuration().systemPrompt, "已保存的规则")
      XCTAssertEqual(model.systemPrompt, "新规则")
      XCTAssertTrue(model.hasUnsavedChanges)
      XCTAssertTrue(model.save())
      XCTAssertEqual(try model.configuration().systemPrompt, "新规则")
    }
  }

  @MainActor func testInvalidReplacementAndStorageFailurePreserveSavedConfiguration() throws {
    try fixture { defaults, _, store, model in
      model.apiKeyInput = "original"
      XCTAssertTrue(model.save())
      model.apiKeyInput = "replacement"
      model.region = .singapore
      model.endpoint = "ws://example.com"
      XCTAssertFalse(model.save())
      XCTAssertEqual(store.value, "original")
      model.endpoint = ""
      model.apiKeyInput = "sk-sp-synthetic"
      XCTAssertFalse(model.save())
      XCTAssertFalse(model.statusMessage.contains("sk-sp-synthetic"))
      model.apiKeyInput = "replacement"
      store.failure = KeychainError.unexpectedStatus(errSecAuthFailed)
      XCTAssertFalse(model.save())
      XCTAssertEqual(model.apiKeyInput, "replacement", "Allow retry after a failed save")
      XCTAssertEqual(store.value, "original")
      XCTAssertEqual(AppPreferences(defaults: defaults).qwenRegion, .beijing)
      XCTAssertEqual(store.saveCount, 1)
      store.failure = nil
      XCTAssertTrue(model.save())
      XCTAssertEqual(try model.configuration().apiKey, "replacement")
    }
  }

  @MainActor func testMissingKeyIgnoresLegacyPathAndNeverDeletesOnBlankOrWhitespaceSave() throws {
    try fixture { defaults, _, store, model in
      defaults.set("/legacy/configuration", forKey: "qwenProjectPath")
      defaults.set("legacy-secret", forKey: "DASHSCOPE_API_KEY")
      let restarted = QwenSettingsModel(preferences: AppPreferences(defaults: defaults), keyStore: store)
      XCTAssertThrowsError(try restarted.configuration()) { error in
        XCTAssertTrue(error.localizedDescription.contains("粘贴并保存"))
        XCTAssertFalse(error.localizedDescription.contains("/legacy/"))
      }
      XCTAssertFalse(model.save())
      model.apiKeyInput = " \n"
      XCTAssertFalse(model.save())
      XCTAssertEqual(store.saveCount, 0)
      XCTAssertEqual(store.deleteCount, 0)
    }
  }

  @MainActor func testRemovalAndChangesInvalidateConnectionStateWithoutTouchingOtherSettings() throws {
    try fixture { _, _, store, model in
      var invalidations = 0
      model.onConfigurationChanged = { invalidations += 1 }
      model.apiKeyInput = "synthetic"
      model.region = .singapore
      XCTAssertTrue(model.save())
      let afterSave = invalidations
      store.failure = KeychainError.unexpectedStatus(errSecAuthFailed)
      XCTAssertFalse(model.removeAPIKey())
      XCTAssertTrue(model.hasSavedKey)
      XCTAssertEqual(store.value, "synthetic")
      store.failure = nil
      XCTAssertTrue(model.removeAPIKey())
      XCTAssertFalse(model.hasSavedKey)
      XCTAssertEqual(model.region, .singapore)
      XCTAssertEqual(store.deleteCount, 1)
      XCTAssertGreaterThan(invalidations, afterSave)
      XCTAssertThrowsError(try model.configuration())
    }
  }

  @MainActor func testSettingsContainsNativeSecureFieldInLightAndDarkModes() throws {
    try fixture { _, _, store, model in
      store.value = "synthetic-saved-key"
      for width: CGFloat in [480, 760] {
        for dark in [false, true] {
          let view = NSHostingView(rootView: Form {
            QwenSettingsSection(model: model, connectionStatus: "", isTestingConnection: false, testConnection: {})
          }.formStyle(.grouped).environment(\.colorScheme, dark ? .dark : .light))
          view.frame = NSRect(x: 0, y: 0, width: width, height: 600)
          view.layoutSubtreeIfNeeded()
          @MainActor func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
          let field = try XCTUnwrap(descendants(view).compactMap { $0 as? NSSecureTextField }.first)
          XCTAssertTrue(field.isEditable)
          XCTAssertEqual(field.stringValue, "")
          XCTAssertGreaterThan(field.frame.width, 100)
          let rect = field.convert(field.bounds, to: view)
          XCTAssertGreaterThanOrEqual(rect.minX, 0)
          XCTAssertLessThanOrEqual(rect.maxX, width)
          XCTAssertEqual(store.loadCount, 0)
        }
      }
    }
  }

  func testKeychainUsesDedicatedIdentityAndMetadataOnlyPresenceCheck() throws {
    var store = APIKeyStore.qwen
    store.operations.copyMatching = { query, _ in
      let query = query as NSDictionary
      XCTAssertEqual(query[kSecAttrService] as? String, "com.typless.Typless")
      XCTAssertEqual(query[kSecAttrAccount] as? String, "QwenRealtimeAPIKey")
      XCTAssertNil(query[kSecReturnData])
      XCTAssertEqual(query[kSecReturnAttributes] as? Bool, true)
      return errSecSuccess
    }
    XCTAssertNotEqual(store.account, APIKeyStore().account)
    XCTAssertTrue(try store.contains())
    store.operations.copyMatching = { _, _ in errSecItemNotFound }
    XCTAssertFalse(try store.contains())
    XCTAssertEqual(try store.load(), "")
    store.operations.copyMatching = { _, _ in errSecAuthFailed }
    XCTAssertThrowsError(try store.contains())
    XCTAssertThrowsError(try store.load())
  }

  func testKeychainReplacesInPlaceAndDoesNotDeleteOrAddOnDeniedUpdate() throws {
    var store = APIKeyStore.qwen
    var updates = 0
    var adds = 0
    store.operations.delete = { _ in XCTFail("Replacing a credential must not delete it"); return errSecSuccess }
    store.operations.update = { query, attributes in
      updates += 1
      XCTAssertEqual((query as NSDictionary)[kSecAttrAccount] as? String, "QwenRealtimeAPIKey")
      XCTAssertEqual((attributes as NSDictionary)[kSecValueData] as? Data, Data("synthetic".utf8))
      XCTAssertEqual((attributes as NSDictionary)[kSecAttrAccessible] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
      return errSecItemNotFound
    }
    store.operations.add = { query, _ in
      adds += 1
      XCTAssertEqual((query as NSDictionary)[kSecAttrAccount] as? String, "QwenRealtimeAPIKey")
      return errSecSuccess
    }
    try store.save("synthetic")
    XCTAssertEqual(updates, 1)
    XCTAssertEqual(adds, 1)
    store.operations.update = { _, _ in errSecSuccess }
    try store.save("replacement")
    XCTAssertEqual(adds, 1)
    store.operations.update = { _, _ in errSecAuthFailed }
    XCTAssertThrowsError(try store.save("replacement"))
    XCTAssertEqual(adds, 1)
  }

  func testKeychainReadValidatesDataAndDeleteIsScoped() throws {
    var store = APIKeyStore.qwen
    store.operations.copyMatching = { query, item in
      XCTAssertEqual((query as NSDictionary)[kSecReturnData] as? Bool, true)
      item?.pointee = Data("synthetic".utf8) as CFData
      return errSecSuccess
    }
    XCTAssertEqual(try store.load(), "synthetic")
    store.operations.copyMatching = { _, item in
      item?.pointee = Data([0xFF]) as CFData
      return errSecSuccess
    }
    XCTAssertThrowsError(try store.load())
    store.operations.delete = { query in
      XCTAssertEqual((query as NSDictionary)[kSecAttrAccount] as? String, "QwenRealtimeAPIKey")
      XCTAssertEqual((query as NSDictionary)[kSecAttrService] as? String, "com.typless.Typless")
      return errSecItemNotFound
    }
    XCTAssertNoThrow(try store.delete())
    store.operations.delete = { _ in errSecAuthFailed }
    XCTAssertThrowsError(try store.delete())
  }
}
