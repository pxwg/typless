import Combine
import Foundation

@MainActor
final class QwenSettingsModel: ObservableObject {
  // This is only a draft. Never populate it with a saved credential.
  @Published var apiKeyInput = "" { didSet { draftChanged() } }
  @Published var region: QwenRegion { didSet { draftChanged() } }
  @Published var workspaceID: String { didSet { draftChanged() } }
  @Published var endpoint: String { didSet { draftChanged() } }
  @Published var systemPrompt: String { didSet { draftChanged() } }
  @Published private(set) var hasSavedKey = false
  @Published private(set) var statusMessage = ""
  var onConfigurationChanged: (() -> Void)?

  private let preferences: AppPreferences
  private let keyStore: any APIKeyStoring

  init(preferences: AppPreferences, keyStore: any APIKeyStoring = APIKeyStore.qwen) {
    self.preferences = preferences
    self.keyStore = keyStore
    region = preferences.qwenRegion
    workspaceID = preferences.qwenWorkspaceID
    endpoint = preferences.qwenEndpoint
    let savedPrompt = QwenProtocol.normalizedSystemPrompt(preferences.qwenSystemPrompt)
    systemPrompt = savedPrompt.isEmpty ? QwenProtocol.defaultSystemPrompt : savedPrompt
  }

  var hasUnsavedChanges: Bool {
    !apiKeyInput.isEmpty || region != preferences.qwenRegion
      || workspaceID != preferences.qwenWorkspaceID || endpoint != preferences.qwenEndpoint
      || QwenProtocol.normalizedSystemPrompt(systemPrompt) != QwenProtocol.normalizedSystemPrompt(preferences.qwenSystemPrompt)
  }

  var canTestConnection: Bool { hasSavedKey && !hasUnsavedChanges }

  func restoreDefaultSystemPrompt() {
    systemPrompt = QwenProtocol.defaultSystemPrompt
  }

  func refreshCredentialStatus() {
    do { hasSavedKey = try keyStore.contains() }
    catch { statusMessage = "无法访问钥匙串：\(error.localizedDescription)" }
  }

  @discardableResult
  func save() -> Bool {
    do {
      // Validate everything before replacing an existing working credential.
      _ = try QwenConfiguration.connectionURL(region: region, workspaceID: workspaceID, endpoint: endpoint)
      if !apiKeyInput.isEmpty {
        let key = try QwenConfiguration.validatedAPIKey(apiKeyInput)
        try keyStore.save(key)
      } else if try !keyStore.contains() {
        throw QwenError(message: "请先粘贴 API Key。")
      }
      preferences.qwenRegion = region
      preferences.qwenWorkspaceID = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
      preferences.qwenEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
      preferences.qwenSystemPrompt = QwenProtocol.normalizedSystemPrompt(systemPrompt)
      workspaceID = preferences.qwenWorkspaceID
      endpoint = preferences.qwenEndpoint
      systemPrompt = preferences.qwenSystemPrompt.isEmpty ? QwenProtocol.defaultSystemPrompt : preferences.qwenSystemPrompt
      hasSavedKey = true
      apiKeyInput = ""
      statusMessage = "已保存"
      onConfigurationChanged?()
      return true
    } catch {
      statusMessage = error.localizedDescription
      return false
    }
  }

  @discardableResult
  func removeAPIKey() -> Bool {
    do {
      try keyStore.delete()
      hasSavedKey = false
      apiKeyInput = ""
      statusMessage = "已删除 API Key"
      onConfigurationChanged?()
      return true
    } catch {
      statusMessage = "无法删除 API Key：\(error.localizedDescription)"
      return false
    }
  }

  /// Both dictation and connection tests use saved settings, never UI drafts or files.
  func configuration() throws -> QwenConfiguration {
    try QwenConfiguration(
      apiKey: keyStore.load(), region: preferences.qwenRegion,
      workspaceID: preferences.qwenWorkspaceID, endpoint: preferences.qwenEndpoint,
      systemPrompt: preferences.qwenSystemPrompt
    )
  }

  private func draftChanged() {
    statusMessage = ""
    onConfigurationChanged?()
  }
}
