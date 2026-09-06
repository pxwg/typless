import SwiftUI

/// Settings rows share a full-width label/control layout. Keep the native switch
/// and its binding/accessibility label; only take ownership of row positioning.
struct SettingsSwitchToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 16) {
      configuration.label
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityHidden(true)
      Toggle(configuration)
        .toggleStyle(.switch)
        .labelsHidden()
        .fixedSize()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
