import SwiftUI

/// System-owned navigation and toolbar chrome. Do not paint over the sidebar:
/// macOS 26 supplies Liquid Glass, with native materials on older systems.
struct HubNavigationLayout<Content: View, Actions: ToolbarContent>: View {
  @Binding var selection: HubPage
  @ViewBuilder var content: Content
  @ToolbarContentBuilder var actions: Actions

  var body: some View {
    NavigationSplitView {
      List(selection: Binding<HubPage?>(get: { selection }, set: { if let page = $0 { selection = page } })) {
        Section {
          ForEach([HubPage.home, .history, .dictionary]) { page in
            NavigationLink(value: page) { Label(page.title, systemImage: page.icon) }
          }
        }
        Section {
          NavigationLink(value: HubPage.settings) {
            Label(HubPage.settings.title, systemImage: HubPage.settings.icon)
          }
        }
      }
      .listStyle(.sidebar)
      .navigationTitle("Typless")
      .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
    } detail: {
      content
        .navigationTitle(selection.title)
        .toolbar { actions }
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 760, minHeight: 560)
  }
}
