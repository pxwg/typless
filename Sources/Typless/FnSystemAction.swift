import Foundation

/// Globe's single-press action can be handled outside the CGEvent tap. Consuming
/// flagsChanged in FnKeyListener is not sufficient to disable the emoji picker.
/// Only inspect this preference: never overwrite a user's system choice on launch.
enum FnSystemAction: Equatable {
  case doNothing, changeInputSource, emoji, dictation, unknown

  init(preference: Int?) {
    switch preference {
    case 0: self = .doNothing
    case 1: self = .changeInputSource
    case 2: self = .emoji
    case 3: self = .dictation
    default: self = .unknown
    }
  }

  static func read() -> Self {
    let domain = "com.apple.HIToolbox" as CFString
    CFPreferencesAppSynchronize(domain)
    let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, domain)
    return Self(preference: (value as? NSNumber)?.intValue)
  }

  var needsAttention: Bool { self != .doNothing }

  var detail: String {
    switch self {
    case .doNothing: return "系统单键动作已设为不执行任何操作。"
    case .emoji: return "系统仍会用 Fn 打开表情面板，请改为“不执行任何操作”。"
    case .changeInputSource: return "系统仍会用 Fn 切换输入法，请改为“不执行任何操作”。"
    case .dictation: return "系统仍会用 Fn 启动听写，请改为“不执行任何操作”。"
    case .unknown: return "请检查系统“按下 🌐 键时”是否设为“不执行任何操作”。"
    }
  }
}
