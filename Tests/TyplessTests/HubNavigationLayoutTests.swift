import AppKit
import SwiftUI
import XCTest
@testable import Typless

@MainActor
private final class HubNavigationFixtureState: ObservableObject {
  @Published var page = HubPage.home
}

private struct HubNavigationFixture: View {
  @ObservedObject var state: HubNavigationFixtureState

  var body: some View {
    HubNavigationLayout(selection: $state.page) {
      if state.page == .settings {
        Form {
          Section("常规") {
            Picker("外观", selection: .constant(0)) { Text("跟随系统").tag(0) }
            Toggle("交互声音", isOn: .constant(true))
            Toggle("保存历史记录", isOn: .constant(true))
            Toggle("登录时启动", isOn: .constant(false))
          }.toggleStyle(SettingsSwitchToggleStyle())
        }.formStyle(.grouped)
      } else {
        ScrollView {
          GroupBox {
            VStack(alignment: .leading, spacing: 16) {
              Text("语音输入").font(.title2)
              Text("按一下 Fn 开始，再按一下完成。")
              Button("试着说一句") {}.buttonStyle(.borderedProminent)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
          }.padding(24)
        }
      }
    } actions: {
      ToolbarItem { Button("暂停监听", systemImage: "pause") {} }
    }
  }
}

final class HubNavigationLayoutTests: XCTestCase {
  @MainActor func testNativeSplitViewAndToolbarInLightDarkAndNarrowWideWindows() throws {
    // Uses the production window factory with isolated, noninteractive fixture
    // data. Never activates a window, loads user history, or changes preferences.
    for width: CGFloat in [760, 1040] {
      for dark in [false, true] {
        let state = HubNavigationFixtureState()
        let window = HubWindowController.makeWindow(rootView: HubNavigationFixture(state: state), autosaveName: nil)
        defer { window.close() }
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: width, height: 700))
        for page in HubPage.allCases {
          state.page = page
          RunLoop.main.run(until: Date().addingTimeInterval(0.05))
          let content = try XCTUnwrap(window.contentView)
          content.layoutSubtreeIfNeeded()
          XCTAssertFalse(window.isVisible)
          XCTAssertEqual(window.title, page.title)
          XCTAssertNotNil(window.standardWindowButton(.closeButton))
          let toolbar = try XCTUnwrap(window.toolbar, "SwiftUI must bridge the toolbar into the AppKit window")
          XCTAssertFalse(toolbar.items.isEmpty)
          let split = try XCTUnwrap(descendants(of: NSSplitView.self, in: content).first)
          XCTAssertTrue(split.isVertical)
          XCTAssertGreaterThanOrEqual(split.arrangedSubviews.count, 2)
          XCTAssertGreaterThan(split.arrangedSubviews[0].frame.width, 100)
          XCTAssertGreaterThan(split.arrangedSubviews[1].frame.width, 300)
          XCTAssertGreaterThan(split.arrangedSubviews[1].frame.height, 500)
          let rows = descendants(of: NSTableView.self, in: split.arrangedSubviews[0])
            .reduce(0) { $0 + $1.numberOfRows }
          XCTAssertGreaterThanOrEqual(rows, 4, "All four sidebar destinations must be present")
          if page == .settings {
            let switches = descendants(of: NSSwitch.self, in: split.arrangedSubviews[1])
            XCTAssertEqual(switches.count, 3)
            let edges = switches.map { $0.convert($0.bounds, to: content).maxX }
            for edge in edges {
              XCTAssertEqual(edge, try XCTUnwrap(edges.first), accuracy: 2,
                "Grouped-form switches must share the same trailing alignment")
            }
          }
          // cacheDisplay cannot faithfully capture the compositor-backed glass
          // or nested hosting layers in an invisible window. Assert structure,
          // not misleading blank snapshots; inspect the actual app separately.
        }
      }
    }
  }

  @MainActor private func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
  }
}
