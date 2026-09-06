import AppKit
import Combine
import Foundation

enum RecognitionLanguage: String, CaseIterable, Identifiable {
  case englishUS = "en-US"
  case simplifiedChinese = "zh-CN"
  case traditionalChinese = "zh-TW"
  case japanese = "ja-JP"
  case korean = "ko-KR"

  var id: String { rawValue }

  var displayName: String {
    L10n.text("language.\(rawValue)")
  }
}

enum AppAppearance: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var displayName: String {
    L10n.text("menu.appearance.\(rawValue)")
  }

  var nsAppearance: NSAppearance? {
    switch self {
    case .system:
      nil
    case .light:
      NSAppearance(named: .aqua)
    case .dark:
      NSAppearance(named: .darkAqua)
    }
  }
}

@MainActor
final class AppPreferences: ObservableObject {
  @Published var qwenProjectPath: String { didSet { defaults.set(qwenProjectPath, forKey: "qwenProjectPath") } }
  @Published var writingMode: WritingMode { didSet { defaults.set(writingMode.rawValue, forKey: "writingMode") } }
  @Published var shortcutMode: ShortcutMode { didSet { defaults.set(shortcutMode.rawValue, forKey: "shortcutMode") } }
  @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "soundEnabled") } }
  @Published var keepHistory: Bool { didSet { defaults.set(keepHistory, forKey: "keepHistory") } }
  private enum Key {
    static let recognitionLanguage = "recognitionLanguage"
    static let appearance = "appearance"
    static let llmEnabled = "llmEnabled"
    static let apiBaseURL = "apiBaseURL"
    static let model = "llmModel"
  }

  private let defaults: UserDefaults

  @Published var recognitionLanguage: RecognitionLanguage {
    didSet { defaults.set(recognitionLanguage.rawValue, forKey: Key.recognitionLanguage) }
  }

  @Published var appearance: AppAppearance {
    didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
  }

  @Published var llmEnabled: Bool {
    didSet { defaults.set(llmEnabled, forKey: Key.llmEnabled) }
  }

  @Published var apiBaseURL: String {
    didSet { defaults.set(apiBaseURL, forKey: Key.apiBaseURL) }
  }

  @Published var model: String {
    didSet { defaults.set(model, forKey: Key.model) }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    qwenProjectPath = defaults.string(forKey: "qwenProjectPath") ?? "~/test-omni"
    writingMode = WritingMode(rawValue: defaults.string(forKey: "writingMode") ?? "") ?? .polished
    shortcutMode = ShortcutMode(rawValue: defaults.string(forKey: "shortcutMode") ?? "") ?? .automatic
    soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
    keepHistory = defaults.object(forKey: "keepHistory") as? Bool ?? true
    recognitionLanguage =
      RecognitionLanguage(
        rawValue: defaults.string(forKey: Key.recognitionLanguage) ?? ""
      ) ?? .simplifiedChinese
    appearance =
      AppAppearance(
        rawValue: defaults.string(forKey: Key.appearance) ?? ""
      ) ?? .system
    llmEnabled = defaults.bool(forKey: Key.llmEnabled)
    apiBaseURL = defaults.string(forKey: Key.apiBaseURL) ?? "https://api.openai.com/v1"
    model = defaults.string(forKey: Key.model) ?? ""
  }
}

enum ShortcutMode: String, CaseIterable, Identifiable {
  case automatic, hold, toggle
  var id: String { rawValue }
  func finishesOnRelease(heldFor seconds: TimeInterval) -> Bool {
    self == .hold || (self == .automatic && seconds >= 0.3)
  }
  var title: String {
    switch self {
    case .automatic: "轻按切换 / 长按说话"
    case .hold: "按住说话，松开完成"
    case .toggle: "按一下开始，再按一下完成"
    }
  }
}
