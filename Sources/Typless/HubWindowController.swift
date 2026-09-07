import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum HubPage: String, CaseIterable, Identifiable {
  case home, history, dictionary, settings
  var id: String { rawValue }
  var title: String {
    switch self { case .home: "首页"; case .history: "历史记录"; case .dictionary: "词典"; case .settings: "设置" }
  }
  var icon: String {
    switch self { case .home: "house"; case .history: "clock.arrow.circlepath"; case .dictionary: "text.book.closed"; case .settings: "gearshape" }
  }
}

@MainActor
final class HubWindowController: NSWindowController {
  init(coordinator: AppCoordinator) {
    let window = Self.makeWindow(rootView: HubView(coordinator: coordinator,
      preferences: coordinator.preferences, permissions: coordinator.permissionManager, store: coordinator.store))
    super.init(window: window)
  }

  static func makeWindow<Content: View>(rootView: Content, autosaveName: String? = "TyplessHub") -> NSWindow {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1040, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.title = "Typless"
    window.toolbarStyle = .unified
    window.minSize = CGSize(width: 760, height: 600)
    window.isReleasedWhenClosed = false
    if let autosaveName { window.setFrameAutosaveName(autosaveName) }
    let hosting = NSHostingController(rootView: rootView)
    hosting.sceneBridgingOptions = .all
    window.contentViewController = hosting
    window.center()
    return window
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func present() {
    NSApp.activate(ignoringOtherApps: true)
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }
}

private enum Palette {
  static let blue = Color.accentColor
  static let background = Color(nsColor: .textBackgroundColor)
  static let line = Color(nsColor: .separatorColor)
}

private struct Card<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    GroupBox {
      content.padding(8).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct PrimaryButton: PrimitiveButtonStyle {
  @ViewBuilder func makeBody(configuration: Configuration) -> some View {
    if #available(macOS 26.0, *) {
      Button(configuration).buttonStyle(.glassProminent)
    } else {
      Button(configuration).buttonStyle(.borderedProminent)
    }
  }
}

private struct KeyCap: View {
  let text: String
  var body: some View {
    Text(text).font(.caption.monospaced()).padding(.horizontal, 8).padding(.vertical, 4)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
  }
}

private struct HubView: View {
  @ObservedObject var coordinator: AppCoordinator
  @ObservedObject var preferences: AppPreferences
  @ObservedObject var permissions: PermissionManager
  @ObservedObject var store: DictationStore
  @State private var search = ""
  @State private var newWord = ""
  @State private var showAddWord = false
  @State private var copiedID: UUID?
  @State private var expandedID: UUID?
  @State private var deleteEntry: DictationEntry?
  @State private var deleteAll = false
  @State private var loginEnabled = false

  var body: some View {
    HubNavigationLayout(selection: $coordinator.selectedPage) {
      detail
    } actions: {
      toolbar
    }
    .onChange(of: coordinator.selectedPage) { _, _ in search = "" }
    .onChange(of: preferences.appearance) { _, value in coordinator.selectAppearance(value) }
    .onAppear {
      loginEnabled = coordinator.launchAtLoginEnabled
      coordinator.refreshFnSystemAction()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      coordinator.refreshFnSystemAction()
    }
    .sheet(isPresented: $showAddWord) { wordSheet }
    .alert("删除这条记录？", isPresented: Binding(get: { deleteEntry != nil }, set: { if !$0 { deleteEntry = nil } })) {
      Button("取消", role: .cancel) { deleteEntry = nil }
      Button("删除", role: .destructive) { if let entry = deleteEntry { store.delete(entry.id) }; deleteEntry = nil }
    } message: { Text("删除后将无法在历史记录中找回。") }
    .alert("清空所有历史记录？", isPresented: $deleteAll) {
      Button("取消", role: .cancel) {}
      Button("清空", role: .destructive) { store.clearHistory() }
    } message: { Text("这会删除此设备上保存的全部转写文字。") }
  }

  @ViewBuilder private var detail: some View {
    switch coordinator.selectedPage {
    case .settings:
      settings
    case .history:
      pageContent { history }
        .searchable(text: $search, placement: .toolbar, prompt: "搜索转写内容")
    case .dictionary:
      pageContent { dictionary }
        .searchable(text: $search, placement: .toolbar, prompt: "搜索词语")
    case .home:
      pageContent { home }
    }
  }

  private func pageContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        content()
        if let error = store.errorMessage {
          Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
      }
      .padding(24).frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
    }
  }

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    if coordinator.selectedPage == .history {
      ToolbarItem {
        Menu("历史记录操作", systemImage: "ellipsis") {
          Button("导出文字…", action: exportHistory)
          Button("清空历史记录…", role: .destructive) { deleteAll = true }
        }
      }
    }
    if coordinator.selectedPage == .dictionary {
      ToolbarItem {
        Button("导入词语", systemImage: "square.and.arrow.down", action: importWords)
      }
      ToolbarItem {
        Button("添加词语", systemImage: "plus") { showAddWord = true }
      }
    }
    ToolbarItem(placement: .primaryAction) {
      Button(coordinator.isPaused ? "恢复监听" : "暂停监听",
        systemImage: coordinator.isPaused ? "play" : "pause") {
        coordinator.setPaused(!coordinator.isPaused)
      }
      .help(coordinator.isPaused ? "恢复 Fn 语音输入" : "暂停 Fn 语音输入")
    }
  }

  @ViewBuilder private var home: some View {
    if !permissions.allGranted { permissionCard }
    if coordinator.fnSystemAction.needsAttention {
      Card {
        HStack(spacing: 16) {
          Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
          rowTitle("让 Fn 专用于语音输入", coordinator.fnSystemAction.detail)
          Spacer()
          Button("打开键盘设置") { coordinator.openKeyboardSettings() }
        }
      }
    }
    HStack(spacing: 14) {
      stat("口述字数", value: store.totalWords.formatted(), unit: "字", icon: "text.alignleft")
      stat("节省时间", value: "\(store.savedMinutes)", unit: "分钟", icon: "hourglass")
      stat("活跃天数", value: "\(store.activeDays)", unit: "天", icon: "sun.max")
    }
    Card {
      VStack(alignment: .leading, spacing: 22) {
        HStack {
          Label("语音输入", systemImage: "mic").font(.title2)
          Spacer()
          KeyCap(text: "fn")
        }
        Divider()
        HStack {
          Text("按一下 Fn 开始，再按一下完成；Esc 取消。")
            .font(.system(size: 11)).foregroundStyle(.tertiary)
          Spacer()
          Button { coordinator.togglePractice() } label: {
            Label(isRecording ? "完成录音" : "试着说一句", systemImage: isRecording ? "stop.fill" : "mic.fill")
          }.buttonStyle(PrimaryButton()).disabled(isProcessing)
        }
        if !coordinator.testText.isEmpty {
          Text(coordinator.testText).font(.system(size: 14)).textSelection(.enabled)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
        }
        if let status = coordinator.recentStatus { Text(status).foregroundStyle(.orange).font(.callout) }
      }
    }
    HStack {
      Text("最近的表达").font(.system(size: 15, weight: .semibold))
      Spacer()
      Button("查看全部 →") { coordinator.selectedPage = .history }.buttonStyle(.plain).foregroundStyle(.secondary)
    }
    if let entry = store.entries.first { entryCard(entry) }
    else {
      HStack(spacing: 14) {
        Image(systemName: "text.bubble").font(.system(size: 23)).foregroundStyle(.tertiary)
        VStack(alignment: .leading, spacing: 5) {
          Text("暂无转录")
          Text("完成第一次语音输入后，会在这里看到记录。")
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
      }.padding(.vertical, 8)
    }
    HStack(spacing: 5) {
      Image(systemName: "lock.shield")
      Text("历史记录仅保存在此设备 · 音频由 Qwen 处理")
    }.font(.system(size: 10)).foregroundStyle(.tertiary)
  }

  private func stat(_ title: String, value: String, unit: String, icon: String) -> some View {
    Card {
      VStack(alignment: .leading, spacing: 17) {
        HStack { Text(title).font(.system(size: 12)); Spacer(); Image(systemName: icon) }.foregroundStyle(.secondary)
        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Text(value).font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
          Text(unit).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
      }
    }
  }

  private var permissionCard: some View {
    HStack(spacing: 14) {
      Image(systemName: "hand.raised.fill").font(.system(size: 22)).foregroundStyle(Palette.blue)
      VStack(alignment: .leading, spacing: 5) {
        Text("再一步，就可以自由表达").fontWeight(.semibold)
        Text("开启麦克风和辅助功能，让声音变成文字。")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer()
      Button("开启权限") { coordinator.presentPermissions() }.buttonStyle(PrimaryButton())
    }.padding(18).background(Palette.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
  }

  @ViewBuilder private var history: some View {
    HStack {
      Label("全部口述", systemImage: "waveform").foregroundStyle(Palette.blue)
      Text("\(store.entries.count)").foregroundStyle(.secondary)
      Spacer()
      Label("仅此设备", systemImage: "lock").font(.system(size: 11)).foregroundStyle(.tertiary)
    }.font(.system(size: 12, weight: .medium))
    let entries = store.entries.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) || $0.rawText.localizedCaseInsensitiveContains(search) }
    if entries.isEmpty {
      emptyState(icon: "clock", title: search.isEmpty ? "还没有历史记录" : "没有找到匹配的记录", detail: "按下 Fn，说出你的第一个想法。")
    } else {
      LazyVStack(spacing: 13) { ForEach(entries) { entry in entryCard(entry) } }
    }
  }

  private func entryCard(_ entry: DictationEntry) -> some View {
    Card {
      VStack(alignment: .leading, spacing: 13) {
        HStack(spacing: 8) {
          Image(systemName: "waveform").foregroundStyle(Palette.blue)
          Text(entry.appName)
          Text("·")
          Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
          Spacer()
          Text("\(Int(entry.duration)) 秒")
          Button { store.copy(entry.text); copiedID = entry.id } label: {
            Image(systemName: copiedID == entry.id ? "checkmark" : "doc.on.doc")
          }.buttonStyle(.plain).help("复制文字").accessibilityLabel("复制文字")
          Menu {
            Button(expandedID == entry.id ? "收起原始转写" : "查看原始转写") { expandedID = expandedID == entry.id ? nil : entry.id }
            Button("删除记录…", role: .destructive) { deleteEntry = entry }
          } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20)
        }.font(.system(size: 11)).foregroundStyle(.secondary)
        Text(entry.text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        if expandedID == entry.id {
          Divider()
          Text("原始转写").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
          Text(entry.rawText).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
        }
      }
    }
  }

  @ViewBuilder private var dictionary: some View {
    Text("全部词语 · \(store.words.count)").font(.headline)
    let words = store.words.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
    if words.isEmpty {
      emptyState(icon: "text.book.closed", title: search.isEmpty ? "让专有名词，被准确听见" : "没有匹配的词语", detail: "添加常用的人名与术语，智能整理时会参考你的词典。")
    } else {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
        ForEach(words, id: \.self) { word in
          GroupBox {
            HStack {
              Text(word).lineLimit(2)
              Spacer(minLength: 4)
              Button("移除 \(word)", systemImage: "xmark") { store.deleteWord(word) }
                .labelStyle(.iconOnly).buttonStyle(.borderless).help("移除 \(word)")
            }.padding(4)
          }
        }
      }
    }
    Label("词典用于智能整理；忠实转写保留模型的原始识别结果。", systemImage: "info.circle")
      .font(.system(size: 11)).foregroundStyle(.tertiary)
  }

  private var wordSheet: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("添加到你的词典").font(.system(size: 22, weight: .semibold))
      Text("输入词语或短语，多个词语用逗号或换行分隔。") .foregroundStyle(.secondary)
      TextEditor(text: $newWord).font(.system(size: 14)).padding(8).frame(height: 110)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line))
      HStack {
        Spacer()
        Button("取消") { showAddWord = false }.keyboardShortcut(.cancelAction)
        Button("添加词语") { store.addWords(newWord); newWord = ""; showAddWord = false }
          .buttonStyle(PrimaryButton()).disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(30).frame(width: 430)
  }

  private var settings: some View {
    Form {
      Section("录音键") {
        LabeledContent {
          KeyCap(text: "fn")
        } label: {
          rowTitle("语音输入", "按一下开始，再按一下完成；Esc 取消。")
        }
        LabeledContent {
          Button("键盘设置") { coordinator.openKeyboardSettings() }
        } label: {
          rowTitle("Fn 系统动作", coordinator.fnSystemAction.detail)
        }
      }
      Section("文字与语言") {
        Picker(selection: $preferences.writingMode) {
          ForEach(WritingMode.allCases) { Text($0.title).tag($0) }
        } label: {
          rowTitle("文字处理", preferences.writingMode.detail)
        }
        Picker(selection: $preferences.recognitionLanguage) {
          ForEach(RecognitionLanguage.allCases) { Text($0.displayName).tag($0) }
        } label: {
          rowTitle("首选语言", "自然混合中英文，保留专业表达。")
        }
      }
      QwenSettingsSection(
        model: coordinator.qwenSettings,
        connectionStatus: coordinator.connectionStatus,
        isTestingConnection: coordinator.isTestingConnection,
        testConnection: coordinator.testQwenConnection
      )
      Section("常规") {
        Picker("外观", selection: $preferences.appearance) {
          ForEach(AppAppearance.allCases) { Text($0.displayName).tag($0) }
        }
        Toggle(isOn: $preferences.soundEnabled) { rowTitle("交互声音", "开始和结束录音时播放轻提示。") }
        Toggle(isOn: $preferences.showRecordingControls) {
          rowTitle("显示胶囊控制按钮", "显示取消和完成按钮；关闭时使用快捷键操作。")
        }
        Toggle(isOn: $preferences.keepHistory) { rowTitle("保存历史记录", "关闭后不保存新记录，已有记录可在历史页清空。") }
        Toggle(isOn: Binding(get: { loginEnabled }, set: { coordinator.setLaunchAtLogin($0); loginEnabled = coordinator.launchAtLoginEnabled })) {
          rowTitle("登录时启动", "开机后，Typless 随时待命。")
        }
        LabeledContent {
          Button("管理权限") { coordinator.presentPermissions() }
        } label: {
          rowTitle("系统权限", permissions.allGranted ? "麦克风与辅助功能已授权。" : "需要麦克风与辅助功能授权。")
        }
      }
      .toggleStyle(SettingsSwitchToggleStyle())
      if let error = store.errorMessage {
        Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
      }
    }
    .formStyle(.grouped)
  }
  private func rowTitle(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(size: 13, weight: .medium))
      Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
  private func emptyState(icon: String, title: String, detail: String) -> some View {
    ContentUnavailableView(title, systemImage: icon, description: Text(detail))
      .frame(maxWidth: .infinity, minHeight: 260)
  }
  private var isRecording: Bool { if case .recording = coordinator.workflowState { return true }; return false }
  private var isProcessing: Bool { !coordinator.workflowState.isIdle && !isRecording }
  private func importWords() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.commaSeparatedText, .plainText]
    if panel.runModal() == .OK, let url = panel.url {
      do { store.addWords(try String(contentsOf: url, encoding: .utf8)) }
      catch { store.errorMessage = error.localizedDescription }
    }
  }
  private func exportHistory() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.plainText]
    panel.nameFieldStringValue = "Typless-history.txt"
    if panel.runModal() == .OK, let url = panel.url {
      let content = store.entries.map { "\($0.date.formatted()) · \($0.appName)\n\($0.text)" }.joined(separator: "\n\n")
      do { try content.write(to: url, atomically: true, encoding: .utf8) }
      catch { store.errorMessage = error.localizedDescription }
    }
  }
}
