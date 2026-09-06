import AppKit
import Combine

@MainActor
final class AppCoordinator: ObservableObject {
  enum WorkflowState {
    case idle
    case recording
    case transcribing
    case refining
    case injecting
    case cancelling

    var isIdle: Bool {
      if case .idle = self { return true }
      return false
    }
  }

  let preferences: AppPreferences
  let qwenSettings: QwenSettingsModel
  let permissionManager: PermissionManager
  let store = DictationStore()
  @Published var selectedPage: HubPage = .home
  @Published var testText = ""
  @Published var connectionStatus = ""
  @Published var isTestingConnection = false
  @Published private(set) var fnSystemAction = FnSystemAction.read()

  @Published private(set) var workflowState: WorkflowState = .idle {
    didSet { onMenuStateChanged?() }
  }
  @Published private(set) var isPaused = false {
    didSet { onMenuStateChanged?() }
  }
  @Published private(set) var lastTranscript: String? {
    didSet { onMenuStateChanged?() }
  }
  @Published private(set) var recentStatus: String? {
    didSet { onMenuStateChanged?() }
  }

  var onMenuStateChanged: (() -> Void)?

  private let pasteInjector = PasteInjector()
  private let overlay = RecordingOverlayController()
  private let fnListener = FnKeyListener()
  private let launchAtLoginService = LaunchAtLoginService()
  private lazy var hub = HubWindowController(coordinator: self)
  private var originalTarget: InputTarget?
  private var recordingStartedAt: Date?
  private var recordingDuration: TimeInterval = 0
  private var practiceSession = false
  private var connectionProbe: QwenRealtimeClient?
  private var dismissalID = UUID()
  private lazy var permissionsWindow = PermissionsWindowController(
    manager: permissionManager
  )

  private var recognitionSession: SpeechRecognitionSession?
  private var sessionIdentifier: UUID?
  private var maximumDurationWorkItem: DispatchWorkItem?
  private var permissionCancellable: AnyCancellable?

  init(
    preferences: AppPreferences,
    permissionManager: PermissionManager
  ) {
    self.preferences = preferences
    self.permissionManager = permissionManager
    qwenSettings = QwenSettingsModel(preferences: preferences)
    qwenSettings.onConfigurationChanged = { [weak self] in self?.invalidateConnectionTest() }

    fnListener.onFnPress = { [weak self] in self?.handleFnPress() }
    fnListener.onCancel = { [weak self] in self?.cancelRecording() }
    overlay.onCancel = { [weak self] in self?.cancelRecording() }
    overlay.onFinish = { [weak self] in self?.finishRecording() }

    permissionCancellable = permissionManager.$accessibilityGranted
      .removeDuplicates()
      .sink { [weak self] granted in
        guard let self else { return }
        if granted, !isPaused {
          _ = fnListener.start()
        } else if !granted {
          fnListener.stop()
        }
      }

    NSApp.appearance = preferences.appearance.nsAppearance
    if permissionManager.accessibilityGranted {
      _ = fnListener.start()
    }
  }

  var statusTitle: String {
    if isPaused {
      return L10n.text("status.paused")
    }
    return workflowState.isIdle
      ? L10n.text("status.ready")
      : L10n.text("status.busy")
  }

  var launchAtLoginEnabled: Bool {
    launchAtLoginService.isEnabled
  }

  func showOnboardingIfNeeded() {
    permissionManager.refresh()
    presentHome()
  }

  func setPaused(_ paused: Bool) {
    isPaused = paused
    if paused {
      if !workflowState.isIdle {
        cancelRecording()
      }
      fnListener.stop()
    } else {
      permissionManager.refresh()
      if permissionManager.accessibilityGranted {
        if !fnListener.start() {
          recentStatus = L10n.text("status.permission_needed")
          permissionsWindow.present()
        }
      } else {
        permissionsWindow.present()
      }
    }
  }

  func selectLanguage(_ language: RecognitionLanguage) {
    preferences.recognitionLanguage = language
  }

  func selectAppearance(_ appearance: AppAppearance) {
    preferences.appearance = appearance
    NSApp.appearance = appearance.nsAppearance
  }

  func presentSettings() {
    refreshFnSystemAction()
    selectedPage = .settings
    hub.present()
  }

  func presentHome() { selectedPage = .home; hub.present() }

  func refreshFnSystemAction() { fnSystemAction = FnSystemAction.read() }

  func openKeyboardSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
    NSWorkspace.shared.open(url)
  }

  func togglePractice() {
    if case .recording = workflowState { beginFinalizing(reachedLimit: false) }
    else if workflowState.isIdle { startRecording(practice: true) }
  }

  func testQwenConnection() {
    guard !isTestingConnection else { return }
    guard !qwenSettings.hasUnsavedChanges else {
      connectionStatus = "请先保存配置，再测试连接。"
      return
    }
    do {
      let config = try qwenSettings.configuration()
      isTestingConnection = true
      connectionStatus = "正在连接 Qwen…"
      let probe = QwenRealtimeClient(configuration: config, language: preferences.recognitionLanguage, mode: .verbatim)
      connectionProbe = probe
      probe.onReady = { [weak self, weak probe] in
        guard let self, let probe, self.connectionProbe === probe else { return }
        probe.cancel()
        self.isTestingConnection = false
        self.connectionStatus = "连接成功"
        self.connectionProbe = nil
      }
      probe.onFailure = { [weak self, weak probe] error in
        guard let self, let probe, self.connectionProbe === probe else { return }
        self.isTestingConnection = false
        self.connectionStatus = error.localizedDescription
        self.connectionProbe = nil
      }
      probe.start()
    } catch { connectionStatus = error.localizedDescription }
  }

  private func invalidateConnectionTest() {
    connectionProbe?.cancel()
    connectionProbe = nil
    isTestingConnection = false
    connectionStatus = ""
  }

  func presentPermissions() {
    permissionsWindow.present()
  }

  func previewOverlay() {
    overlay.show(
      on: InputTargetLocator.fallbackScreen(),
      appearance: preferences.appearance,
      initialStatus: L10n.text("status.listening")
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
      self?.overlay.updateText(
        "You speak faster than you type. You think faster when you speak.",
        isStatus: false
      )
      self?.overlay.updateLevel(0.82)
    }
  }

  func copyLastTranscript() {
    guard let lastTranscript else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(lastTranscript, forType: .string)
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      try launchAtLoginService.setEnabled(enabled)
      recentStatus = nil
    } catch {
      recentStatus = error.localizedDescription
    }
    onMenuStateChanged?()
  }

  func shutdown() {
    maximumDurationWorkItem?.cancel()
    recognitionSession?.cancel()
    fnListener.stop()
    connectionProbe?.cancel()
  }

  private func handleFnPress() {
    if case .recording = workflowState {
      finishRecording()
      return
    }
    startRecording(practice: false)
  }

  private func startRecording(practice: Bool) {
    guard workflowState.isIdle, !isPaused else { return }
    dismissalID = UUID()

    permissionManager.refresh()
    guard permissionManager.microphoneGranted && (practice || permissionManager.accessibilityGranted) else {
      presentTransientStatus(L10n.text("status.permission_needed"))
      permissionsWindow.present()
      return
    }

    let initialTarget = practice ? nil : InputTargetLocator.focusedTarget()
    guard practice || initialTarget?.isEditable == true else {
      presentTransientStatus(L10n.text("status.no_target"))
      return
    }
    guard initialTarget?.isSecure != true else {
      presentTransientStatus(L10n.text("status.secure_field"))
      return
    }

    let session = SpeechRecognitionSession()
    originalTarget = initialTarget
    practiceSession = practice
    recordingStartedAt = Date()
    let identifier = UUID()
    sessionIdentifier = identifier
    recognitionSession = session
    session.onTranscript = { [weak self] transcript in
      guard
        let self,
        sessionIdentifier == identifier,
        !workflowState.isIdle
      else {
        return
      }
      if !transcript.isEmpty {
        overlay.updateText(transcript, isStatus: false)
      }
    }
    session.onLevel = { [weak self] level in
      guard self?.sessionIdentifier == identifier else { return }
      self?.overlay.updateLevel(level)
    }
    session.onFailure = { [weak self] error in
      self?.handleSpeechFailure(error, identifier: identifier)
    }

    overlay.show(
      on: initialTarget?.screen ?? InputTargetLocator.fallbackScreen(),
      appearance: preferences.appearance,
      initialStatus: L10n.text("status.listening")
    )

    do {
      let configuration = try qwenSettings.configuration()
      try session.start(configuration: configuration, language: preferences.recognitionLanguage, mode: preferences.writingMode, dictionary: store.words)
      workflowState = .recording
      fnListener.isSessionActive = true
      overlay.setRecording(true)
      if preferences.soundEnabled { NSSound(named: "Tink")?.play() }
      recentStatus = nil
      scheduleMaximumDuration(for: identifier)
    } catch {
      recognitionSession = nil
      sessionIdentifier = nil
      recentStatus = error.localizedDescription
      workflowState = .cancelling
      overlay.updateText(error.localizedDescription, isStatus: true)
      dismissToIdle(after: 1.2)
    }
  }

  private func finishRecording() {
    guard case .recording = workflowState else { return }
    beginFinalizing(reachedLimit: false)
  }

  private func scheduleMaximumDuration(for identifier: UUID) {
    let workItem = DispatchWorkItem { [weak self] in
      guard
        let self,
        sessionIdentifier == identifier,
        case .recording = workflowState
      else {
        return
      }
      beginFinalizing(reachedLimit: true)
    }
    maximumDurationWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: workItem)
  }

  private func beginFinalizing(reachedLimit: Bool) {
    maximumDurationWorkItem?.cancel()
    maximumDurationWorkItem = nil
    guard
      let session = recognitionSession,
      let identifier = sessionIdentifier
    else {
      resetToIdle()
      return
    }

    let target = originalTarget
    recordingDuration = Date().timeIntervalSince(recordingStartedAt ?? Date())
    if target?.isSecure == true {
      session.cancel()
      overlay.updateLevel(0)
      overlay.updateText(L10n.text("status.secure_field"), isStatus: true)
      workflowState = .cancelling
      dismissToIdle(after: 0.8)
      return
    }

    workflowState = .transcribing
    overlay.setRecording(false)
    if preferences.soundEnabled { NSSound(named: "Pop")?.play() }
    overlay.updateLevel(0)
    overlay.updateText(
      reachedLimit
        ? L10n.text("status.limit")
        : L10n.text("status.transcribing"),
      isStatus: true
    )

    let statusDeadline = reachedLimit ? Date().addingTimeInterval(0.45) : Date()
    session.finish { [weak self] result in
      guard let self, sessionIdentifier == identifier else { return }
      let delay = max(0, statusDeadline.timeIntervalSinceNow)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self, sessionIdentifier == identifier else { return }
        if reachedLimit {
          overlay.updateText(L10n.text("status.transcribing"), isStatus: true)
        }
        recentStatus = result.warning
        if !result.text.isEmpty, preferences.keepHistory {
          let appName = target.flatMap { NSRunningApplication(processIdentifier: $0.processIdentifier)?.localizedName } ?? "Typless"
          store.add(DictationEntry(text: result.text, rawText: result.rawText, duration: recordingDuration, appName: appName))
        }
        handleFinalTranscript(
          result.text,
          target: target,
          identifier: identifier
        )
      }
    }
  }

  private func handleFinalTranscript(
    _ transcript: String?,
    target: InputTarget?,
    identifier: UUID
  ) {
    guard sessionIdentifier == identifier else { return }
    guard let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      overlay.updateText(L10n.text("status.no_speech"), isStatus: true)
      dismissToIdle(after: 0.65)
      return
    }

    completeTranscript(transcript, target: target, identifier: identifier)
  }

  private func completeTranscript(
    _ transcript: String,
    target: InputTarget?,
    identifier: UUID
  ) {
    guard sessionIdentifier == identifier else { return }
    lastTranscript = transcript
    if practiceSession {
      testText = transcript
      overlay.updateText("已完成", isStatus: true)
      dismissToIdle(after: 0.5)
      return
    }
    overlay.updateText(transcript, isStatus: false, animated: false)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      guard let self, sessionIdentifier == identifier else { return }
      guard let target, target.isEditable else {
        overlay.updateText(L10n.text("status.no_target"), isStatus: true)
        dismissToIdle(after: 0.9)
        return
      }
      guard InputTargetLocator.isStillFocused(target) else {
        overlay.updateText(L10n.text("status.focus_changed"), isStatus: true)
        dismissToIdle(after: 1.2)
        return
      }

      workflowState = .injecting
      pasteInjector.inject(transcript, isValidTarget: { [weak self] in
        self?.sessionIdentifier == identifier && InputTargetLocator.isStillFocused(target)
      }) { [weak self] posted in
        guard let self, sessionIdentifier == identifier else { return }
        if posted {
          dismissToIdle(after: 0)
        } else {
          recentStatus = L10n.text("status.injection_failed")
          overlay.updateText(L10n.text("status.injection_failed"), isStatus: true)
          dismissToIdle(after: 1)
        }
      }
    }
  }

  func cancelRecording() {
    guard !workflowState.isIdle else { return }
    maximumDurationWorkItem?.cancel()
    maximumDurationWorkItem = nil
    workflowState = .cancelling
    recognitionSession?.cancel()
    sessionIdentifier = nil
    overlay.setRecording(false)
    overlay.updateLevel(0)
    overlay.updateText(L10n.text("status.cancelled"), isStatus: true)
    dismissToIdle(after: 0.45)
  }

  private func handleSpeechFailure(_ error: Error, identifier: UUID) {
    guard sessionIdentifier == identifier, !workflowState.isIdle else { return }
    recentStatus = error.localizedDescription
    recognitionSession?.cancel()
    workflowState = .cancelling
    overlay.setRecording(false)
    overlay.updateText(error.localizedDescription, isStatus: true)
    dismissToIdle(after: 1.2)
  }

  private func presentTransientStatus(_ message: String) {
    workflowState = .cancelling
    overlay.show(
      on: InputTargetLocator.fallbackScreen(),
      appearance: preferences.appearance,
      initialStatus: message
    )
    dismissToIdle(after: 0.9)
  }

  private func dismissToIdle(after delay: TimeInterval) {
    let identifier = UUID()
    dismissalID = identifier
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self, dismissalID == identifier else { return }
      overlay.hide { [weak self] in
        guard let self, dismissalID == identifier else { return }
        resetToIdle()
      }
    }
  }

  private func resetToIdle() {
    maximumDurationWorkItem?.cancel()
    maximumDurationWorkItem = nil
    recognitionSession?.cancel()
    recognitionSession = nil
    originalTarget = nil
    recordingStartedAt = nil
    fnListener.isSessionActive = false
    sessionIdentifier = nil
    workflowState = .idle
  }

}
