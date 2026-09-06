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
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1040, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.title = "Typless"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.minSize = CGSize(width: 860, height: 640)
    window.isReleasedWhenClosed = false
    window.setFrameAutosaveName("TyplessHub")
    window.contentView = NSHostingView(rootView: HubView(coordinator: coordinator,
      preferences: coordinator.preferences, permissions: coordinator.permissionManager, store: coordinator.store))
    window.center()
    super.init(window: window)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func present() {
    NSApp.activate(ignoringOtherApps: true)
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }
}

private enum Palette {
  static let blue = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    ? NSColor(red: 0.52, green: 0.61, blue: 1, alpha: 1) : NSColor(red: 0.28, green: 0.38, blue: 0.91, alpha: 1) })
  static let background = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    ? NSColor(white: 0.105, alpha: 1) : NSColor(red: 0.975, green: 0.973, blue: 0.962, alpha: 1) })
  static let sidebar = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    ? NSColor(white: 0.135, alpha: 1) : NSColor(red: 0.95, green: 0.948, blue: 0.937, alpha: 1) })
  static let card = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    ? NSColor(white: 0.155, alpha: 1) : .white })
  static let line = Color.primary.opacity(0.075)
}

private struct Card<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    content.padding(24).frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
      .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.line))
  }
}

private struct PrimaryButton: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 13, weight: .semibold))
      .padding(.horizontal, 17).padding(.vertical, 11)
      .foregroundStyle(.white).background(Palette.blue.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 10))
  }
}

private struct KeyCap: View {
  let text: String
  var body: some View {
    Text(text).font(.system(size: 12, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 5)
      .background(Palette.card, in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.13)))
      .shadow(color: .black.opacity(0.04), radius: 0, y: 2)
  }
}

private struct HubView: View {
  @ObservedObject var coordinator: AppCoordinator
  @ObservedObject var preferences: AppPreferences
  @ObservedObject var permissions: PermissionManager
  @ObservedObject var store: DictationStore
  @Environment(\.colorScheme) private var scheme
  @State private var search = ""
  @State private var newWord = ""
  @State private var showAddWord = false
  @State private var copiedID: UUID?
  @State private var expandedID: UUID?
  @State private var deleteEntry: DictationEntry?
  @State private var deleteAll = false
  @State private var loginEnabled = false

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          switch coordinator.selectedPage {
          case .home: home
          case .history: history
          case .dictionary: dictionary
          case .settings: settings
          }
          if let error = store.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
          }
        }.padding(.horizontal, 38).padding(.top, 42).padding(.bottom, 32)
          .frame(maxWidth: 1080, alignment: .leading).frame(maxWidth: .infinity)
      }.background(Palette.background)
    }
    .font(.system(size: 13)).tint(Palette.blue)
    .frame(minWidth: 860, minHeight: 610).ignoresSafeArea()
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

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Image(systemName: "waveform").font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.blue)
        Text("Typless").font(.system(size: 22, weight: .semibold, design: .rounded))
      }.padding(.horizontal, 14).padding(.top, 56).padding(.bottom, 28)
      ForEach([HubPage.home, .history, .dictionary]) { page in navButton(page) }
      Spacer()
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 6) {
          Circle().fill(coordinator.isPaused ? Color.orange : Palette.blue).frame(width: 6, height: 6)
          Text(coordinator.isPaused ? "已暂停" : "让表达自然发生").font(.system(size: 12, weight: .medium))
        }
        HStack(spacing: 6) { KeyCap(text: "fn"); Text("随时开始说话").foregroundStyle(.secondary).font(.system(size: 11)) }
      }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 8)
      navButton(.settings)
      HStack {
        Text("QWEN OMNI").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(.tertiary)
        Spacer()
        Button { coordinator.setPaused(!coordinator.isPaused) } label: {
          Image(systemName: coordinator.isPaused ? "play.circle" : "pause.circle").font(.system(size: 15)).foregroundStyle(.secondary)
        }.buttonStyle(.plain).help(coordinator.isPaused ? "恢复监听" : "暂停监听")
      }.padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 24)
    }.padding(.horizontal, 14).frame(width: 184).background(Palette.sidebar)
      .overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 1) }
  }

  private func navButton(_ page: HubPage) -> some View {
    let selected = coordinator.selectedPage == page
    return Button { coordinator.selectedPage = page } label: {
      HStack(spacing: 11) {
        Image(systemName: page.icon).font(.system(size: 15)).frame(width: 19)
        Text(page.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
        Spacer()
      }.foregroundStyle(selected ? Color.primary : .secondary)
        .padding(.horizontal, 13).padding(.vertical, 12)
        .background(selected ? Palette.card : .clear, in: RoundedRectangle(cornerRadius: 10))
    }.buttonStyle(.plain)
  }

  private func heading(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title).font(.system(size: 32, weight: .semibold)).tracking(-0.7)
      Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private var home: some View {
    HStack(alignment: .top) {
      heading("说话，不要打字。", "把时间留给思考，让表达跟上你的想法。")
      Spacer()
      Label("Qwen", systemImage: "sparkle").font(.system(size: 11, weight: .medium))
        .foregroundStyle(Palette.blue).padding(.horizontal, 11).padding(.vertical, 7)
        .background(Palette.blue.opacity(0.09), in: Capsule()).padding(.top, 7)
    }
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
          VStack(alignment: .leading, spacing: 6) {
            Text("从一个想法开始").font(.system(size: 18, weight: .semibold))
            Text("在任何输入框按下 Fn，自然地说，再按一下完成。")
              .foregroundStyle(.secondary).font(.system(size: 12))
          }
          Spacer()
          KeyCap(text: "fn")
        }
        HStack(alignment: .center, spacing: 24) {
          VStack(alignment: .leading, spacing: 12) {
            Label("随心说，边想边说", systemImage: "waveform")
            Label("自动整理重复与口头禅", systemImage: "sparkles")
            Label("文字出现在原来的输入框", systemImage: "cursorarrow.rays")
          }.font(.system(size: 12)).foregroundStyle(.secondary)
          Spacer()
          HStack(alignment: .center, spacing: 5) {
            ForEach(Array([14, 25, 40, 56, 32, 65, 47, 25, 40, 18, 10].enumerated()), id: \.offset) { index, height in
              Capsule().fill(Palette.blue.opacity(index % 3 == 0 ? 0.4 : 0.85)).frame(width: 6, height: CGFloat(height))
            }
          }.frame(width: 160, height: 90).background(Palette.blue.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
        }
        Divider().overlay(Palette.line)
        HStack {
          Text("也可以长按 Fn 说话，松开即可完成。")
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
          Text("你的下一段文字，从声音开始。")
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
      heading("历史记录", "每一次表达，都可以再次找到。")
      Spacer()
      Menu { Button("导出文字…", action: exportHistory); Button("清空历史记录…", role: .destructive) { deleteAll = true } }
      label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }.menuStyle(.borderlessButton).frame(width: 34)
    }
    searchField("搜索转写内容")
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
    HStack {
      heading("你的词典", "人名、产品名、专业术语。让 Typless 更懂你的表达。")
      Spacer()
      Button { showAddWord = true } label: { Label("添加词语", systemImage: "plus") }.buttonStyle(PrimaryButton())
    }
    searchField("搜索词语")
    HStack {
      Text("全部词语 · \(store.words.count)").font(.system(size: 12, weight: .medium))
      Spacer()
      Button("导入 CSV…", action: importWords).buttonStyle(.plain).foregroundStyle(.secondary)
    }
    let words = store.words.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
    if words.isEmpty {
      emptyState(icon: "text.book.closed", title: search.isEmpty ? "让专有名词，被准确听见" : "没有匹配的词语", detail: "添加常用的人名与术语，Qwen 整理文字时会参考你的词典。")
    } else {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
        ForEach(words, id: \.self) { word in
          HStack {
            Text(word).lineLimit(2)
            Spacer(minLength: 4)
            Button { store.deleteWord(word) } label: { Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.tertiary) }
              .buttonStyle(.plain).help("移除 \(word)")
          }.padding(.horizontal, 16).padding(.vertical, 13)
            .background(Palette.card, in: Capsule()).overlay(Capsule().strokeBorder(Palette.line))
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

  @ViewBuilder private var settings: some View {
    heading("设置", "让 Typless 适应你的工作方式。")
    sectionLabel("键盘快捷键", icon: "keyboard")
    Card {
      VStack(spacing: 20) {
        HStack {
          rowTitle("语音输入", "在任何输入框中开始说话。")
          Spacer()
          KeyCap(text: "fn")
        }
        Divider()
        HStack {
          rowTitle("Fn 系统动作", coordinator.fnSystemAction.detail)
          Spacer()
          Button("键盘设置") { coordinator.openKeyboardSettings() }
        }
        Divider()
        HStack {
          rowTitle("操作方式", "轻按可免长按，Esc 随时取消。")
          Spacer()
          Picker("操作方式", selection: $preferences.shortcutMode) {
            ForEach(ShortcutMode.allCases) { Text($0.title).tag($0) }
          }.labelsHidden().frame(width: 220)
        }
      }
    }
    sectionLabel("文字与语言", icon: "textformat")
    Card {
      VStack(spacing: 20) {
        HStack {
          rowTitle("文字处理", preferences.writingMode.detail)
          Spacer()
          Picker("文字处理", selection: $preferences.writingMode) {
            ForEach(WritingMode.allCases) { Text($0.title).tag($0) }
          }.labelsHidden().frame(width: 140)
        }
        Divider()
        HStack {
          rowTitle("首选语言", "自然混合中英文，保留专业表达。")
          Spacer()
          Picker("首选语言", selection: $preferences.recognitionLanguage) {
            ForEach(RecognitionLanguage.allCases) { Text($0.displayName).tag($0) }
          }.labelsHidden().frame(width: 140)
        }
      }
    }
    sectionLabel("语音模型", icon: "sparkles")
    Card {
      VStack(alignment: .leading, spacing: 17) {
        HStack {
          Image(systemName: "waveform.circle.fill").font(.system(size: 36)).foregroundStyle(Palette.blue)
          VStack(alignment: .leading, spacing: 5) {
            Text("Qwen Omni").font(.system(size: 16, weight: .semibold))
            Text(QwenConfiguration.model).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
          }
          Spacer()
          Text("识别 + 整理").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.blue)
            .padding(8).background(Palette.blue.opacity(0.08), in: Capsule())
        }
        Divider()
        rowTitle("配置目录", "使用此目录 .env 中的百炼 Key、地域与连接地址。")
        HStack {
          TextField("~/test-omni", text: $preferences.qwenProjectPath).textFieldStyle(.roundedBorder)
          Button("测试连接") { coordinator.testQwenConnection() }.disabled(coordinator.isTestingConnection)
        }
        if !coordinator.connectionStatus.isEmpty {
          Text(coordinator.connectionStatus).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
        }
        Text("录音通过加密连接发送至配置的 Qwen 服务。密钥不会写入应用或历史记录。")
          .font(.system(size: 11)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
      }
    }
    sectionLabel("常规", icon: "slider.horizontal.3")
    Card {
      VStack(spacing: 20) {
        HStack {
          rowTitle("外观", "选择你习惯的明暗。")
          Spacer()
          Picker("外观", selection: $preferences.appearance) { ForEach(AppAppearance.allCases) { Text($0.displayName).tag($0) } }
            .labelsHidden().frame(width: 140)
        }
        Divider()
        Toggle(isOn: $preferences.soundEnabled) { rowTitle("交互声音", "开始和结束录音时播放轻提示。") }.toggleStyle(.switch)
        Divider()
        Toggle(isOn: $preferences.keepHistory) { rowTitle("保存历史记录", "关闭后不保存新记录，已有记录可在历史页清空。") }.toggleStyle(.switch)
        Divider()
        Toggle(isOn: Binding(get: { loginEnabled }, set: { coordinator.setLaunchAtLogin($0); loginEnabled = coordinator.launchAtLoginEnabled })) {
          rowTitle("登录时启动", "开机后，Typless 随时待命。")
        }.toggleStyle(.switch)
        Divider()
        HStack {
          rowTitle("系统权限", permissions.allGranted ? "麦克风与辅助功能已授权。" : "需要麦克风与辅助功能授权。")
          Spacer()
          Button("管理权限") { coordinator.presentPermissions() }
        }
      }
    }
    Text("Typless · 为流畅表达而设计").font(.system(size: 11)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
  }

  private func sectionLabel(_ title: String, icon: String) -> some View {
    Label(title, systemImage: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.top, 2)
  }
  private func rowTitle(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(size: 13, weight: .medium))
      Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
  private func searchField(_ placeholder: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
      TextField(placeholder, text: $search).textFieldStyle(.plain)
      if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain) }
    }.padding(13).background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
  }
  private func emptyState(icon: String, title: String, detail: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: icon).font(.system(size: 35, weight: .light)).foregroundStyle(Palette.blue.opacity(0.65))
        .frame(width: 82, height: 82).background(Palette.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
      Text(title).font(.system(size: 18, weight: .medium))
      Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }.padding(.vertical, 80).frame(maxWidth: .infinity)
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
