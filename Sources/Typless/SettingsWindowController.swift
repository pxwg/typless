import AppKit
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
  @Published var baseURL: String
  @Published var apiKey: String
  @Published var model: String
  @Published var statusMessage = ""
  @Published var isTesting = false

  private let preferences: AppPreferences
  private let keyStore: APIKeyStore
  private let service: LLMRefinementService

  init(
    preferences: AppPreferences,
    keyStore: APIKeyStore,
    service: LLMRefinementService
  ) {
    self.preferences = preferences
    self.keyStore = keyStore
    self.service = service
    baseURL = preferences.apiBaseURL
    model = preferences.model
    apiKey = (try? keyStore.load()) ?? ""
  }

  func reload() {
    baseURL = preferences.apiBaseURL
    model = preferences.model
    apiKey = (try? keyStore.load()) ?? ""
    statusMessage = ""
  }

  func save() {
    let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedBaseURL.isEmpty {
      do {
        _ = try APIEndpoint.chatCompletionsURL(from: trimmedBaseURL)
      } catch {
        statusMessage = error.localizedDescription
        return
      }
    }

    do {
      try keyStore.save(apiKey)
      preferences.apiBaseURL = trimmedBaseURL
      preferences.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
      let configuration = currentConfiguration
      if !configuration.isComplete {
        preferences.llmEnabled = false
      }
      statusMessage = L10n.text("settings.saved")
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  func test() {
    guard currentConfiguration.isComplete else {
      statusMessage = L10n.text("settings.missing_fields")
      return
    }
    do {
      _ = try APIEndpoint.chatCompletionsURL(from: currentConfiguration.baseURL)
    } catch {
      statusMessage = error.localizedDescription
      return
    }

    isTesting = true
    statusMessage = L10n.text("settings.testing")
    let configuration = currentConfiguration
    Task {
      do {
        try await service.test(configuration: configuration)
        statusMessage = L10n.text("settings.test_success")
      } catch {
        statusMessage = error.localizedDescription
      }
      isTesting = false
    }
  }

  private var currentConfiguration: LLMConfiguration {
    LLMConfiguration(
      baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
      apiKey: apiKey,
      model: model.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }
}

@MainActor
final class SettingsWindowController: NSWindowController {
  private let viewModel: SettingsViewModel

  init(
    preferences: AppPreferences,
    keyStore: APIKeyStore,
    service: LLMRefinementService
  ) {
    viewModel = SettingsViewModel(
      preferences: preferences,
      keyStore: keyStore,
      service: service
    )
    let contentView = SettingsView(viewModel: viewModel)
    let hostingController = NSHostingController(rootView: contentView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = L10n.text("settings.title")
    window.styleMask = [.titled, .closable]
    window.setContentSize(CGSize(width: 480, height: 280))
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    viewModel.reload()
    NSApp.activate(ignoringOtherApps: true)
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }
}

private struct SettingsView: View {
  @ObservedObject var viewModel: SettingsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(L10n.text("settings.title"))
        .font(.title2.weight(.semibold))

      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
        GridRow {
          Text(L10n.text("settings.base_url"))
          TextField("https://api.openai.com/v1", text: $viewModel.baseURL)
            .textFieldStyle(.roundedBorder)
        }
        GridRow {
          Text(L10n.text("settings.api_key"))
          HStack(spacing: 6) {
            SecureField("", text: $viewModel.apiKey)
              .textFieldStyle(.roundedBorder)
            Button {
              viewModel.apiKey = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear API Key")
          }
        }
        GridRow {
          Text(L10n.text("settings.model"))
          TextField("model-name", text: $viewModel.model)
            .textFieldStyle(.roundedBorder)
        }
      }

      HStack {
        Text(viewModel.statusMessage)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Spacer()
        Button(L10n.text("settings.test")) {
          viewModel.test()
        }
        .disabled(viewModel.isTesting)
        Button(L10n.text("settings.save")) {
          viewModel.save()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(minWidth: 480, minHeight: 280)
  }
}
