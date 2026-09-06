import AppKit
import Combine

/// Owns a short-lived display clock, independent of the recognition/insertion
/// workflow. Status/final text and hidden panels never keep an animation queue.
@MainActor
final class TranscriptPresentation: ObservableObject {
  @Published private(set) var text = ""
  @Published private(set) var isStatus = true
  @Published private(set) var frame = TranscriptReveal.Frame()
  @Published private(set) var animatesChanges = false
  private var reveal = TranscriptReveal()
  private var animationTask: Task<Void, Never>?
  private let reduceMotion: () -> Bool

  init(reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
    self.reduceMotion = reduceMotion
  }

  deinit { animationTask?.cancel() }

  func update(_ text: String, isStatus: Bool, animated: Bool = true) {
    let animate = animated && !isStatus && !reduceMotion()
    if text == self.text, isStatus == self.isStatus, animate { return }
    if !animate || self.isStatus {
      animationTask?.cancel()
      animationTask = nil
    }
    let now = ProcessInfo.processInfo.systemUptime
    if self.isStatus { reveal.reset() }
    self.text = text
    self.isStatus = isStatus
    animatesChanges = animate
    if animate {
      reveal.retarget(to: text)
    } else {
      reveal.reset(to: text)
    }
    frame = reveal.advance(at: now)
    // Keep one player alive across chunks instead of restarting its tick on
    // every network callback. Frequent chunks must not starve or burst playback.
    guard animationTask == nil, reveal.isAnimating(at: now) else { return }

    animationTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(16)) }
        catch { return }
        guard !Task.isCancelled, let self else { return }
        if reduceMotion() {
          finishImmediately()
          return
        }
        let now = ProcessInfo.processInfo.systemUptime
        frame = reveal.advance(at: now)
        if !reveal.isAnimating(at: now) {
          animationTask = nil
          return
        }
      }
    }
  }

  func finishImmediately() {
    animationTask?.cancel()
    animationTask = nil
    animatesChanges = false
    reveal.reset(to: text)
    frame = reveal.advance(at: ProcessInfo.processInfo.systemUptime)
  }
}
