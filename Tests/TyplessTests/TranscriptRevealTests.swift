import XCTest
@testable import Typless

final class TranscriptRevealTests: XCTestCase {
  func testAppendReleasesOneCharacterAtATimeWithOverlappingFades() {
    var reveal = TranscriptReveal()
    reveal.reset(to: "你好")
    reveal.retarget(to: "你好世界，这是流式转写。")
    let first = reveal.advance(at: 10)
    XCTAssertEqual(first.stableText, "你好")
    XCTAssertEqual(first.fading.first?.text, "世")
    XCTAssertEqual(first.fading.first?.opacity, 0)
    let middle = reveal.advance(at: 10.015)
    XCTAssertEqual(middle.text, "你好世")
    XCTAssertTrue(middle.fading.contains { $0.opacity > 0 && $0.opacity < 1 })
    XCTAssertEqual(reveal.advance(at: 10.03001).text, "你好世界")
    assertDrainsExactly(&reveal, after: 10.03001)
  }

  func testDuplicateChunksDoNotRestartCharacterFades() {
    var reveal = TranscriptReveal()
    reveal.retarget(to: "一二三四五六七八九十")
    _ = reveal.advance(at: 10)
    var uninterrupted = reveal
    reveal.retarget(to: reveal.text)
    XCTAssertEqual(reveal.advance(at: 10.02), uninterrupted.advance(at: 10.02))
    XCTAssertEqual(reveal.advance(at: 10.03001), uninterrupted.advance(at: 10.03001))
    assertDrainsExactly(&reveal, after: 10.03001)
  }

  func testIncomingChunksAppendWithoutCompressingOrRestartingTheCadence() {
    var reveal = TranscriptReveal()
    reveal.retarget(to: "一二三四五六七八九十")
    XCTAssertEqual(reveal.advance(at: 10).text, "一")
    reveal.retarget(to: "一二三四五六七八九十，后面还有很多很多文字。")
    XCTAssertEqual(reveal.advance(at: 10.02).text, "一")
    XCTAssertEqual(reveal.advance(at: 10.03001).text, "一二")
    reveal.retarget(to: "一二三四五六七八九十，后面还有很多很多文字。现在结束。")
    XCTAssertEqual(reveal.advance(at: 10.04).text, "一二")
    XCTAssertEqual(reveal.advance(at: 10.06002).text, "一二三")
    assertDrainsExactly(&reveal, after: 10.06002)
  }

  func testVisibleASRCorrectionReplacesInPlaceWithoutBackspacingAndRetyping() {
    var reveal = TranscriptReveal()
    reveal.reset(to: "我们明天三点开会")
    reveal.retarget(to: "我们明天四点开会。")
    let frame = reveal.advance(at: 10)
    XCTAssertEqual(frame.stableText, "我们明天四点开会")
    XCTAssertEqual(frame.fading.map(\.text), ["。"])
    XCTAssertFalse(frame.text.contains("三"))
    assertDrainsExactly(&reveal, after: 10)
  }

  func testCorrectionDropsUnrevealedStaleCharacters() {
    var reveal = TranscriptReveal()
    reveal.retarget(to: "我们明天三点开会")
    _ = reveal.advance(at: 10)
    reveal.retarget(to: "我们明天四点开会")
    for step in 0...30 {
      let frame = reveal.advance(at: 10.02 + Double(step) / 100)
      XCTAssertTrue(reveal.text.hasPrefix(frame.text))
      XCTAssertFalse(frame.text.contains("三"))
    }
    assertDrainsExactly(&reveal, after: 10.32)
  }

  func testShorteningAndEmptyCorrectionsDoNotLeaveOldText() {
    var reveal = TranscriptReveal()
    reveal.reset(to: "多余的文字需要被删除")
    reveal.retarget(to: "文字")
    XCTAssertEqual(reveal.advance(at: 10).stableText, "文字")
    XCTAssertFalse(reveal.isAnimating(at: 10))
    reveal.retarget(to: "")
    XCTAssertEqual(reveal.advance(at: 11).text, "")
    XCTAssertFalse(reveal.isAnimating(at: 11))
  }

  func testUnicodeGraphemesAreNeverSplitIntoPartialEmojiOrAccents() {
    let text = "你好 👩🏽‍💻 e\u{301} 🇨🇳 family 👨‍👩‍👧‍👦。"
    var reveal = TranscriptReveal()
    reveal.retarget(to: text)
    var previousCount = 0
    for step in 0...60 {
      let frame = reveal.advance(at: 10 + Double(step) / 200)
      XCTAssertTrue(text.hasPrefix(frame.text))
      XCTAssertTrue((0...1).contains(frame.text.count - previousCount))
      previousCount = frame.text.count
      for character in frame.fading {
        XCTAssertEqual(character.text.count, 1)
        XCTAssertTrue(text.contains(character.text))
        XCTAssertTrue((0...1).contains(character.opacity))
        XCTAssertTrue(character.opacity.isFinite)
      }
    }
    assertDrainsExactly(&reveal, after: 10.3)
  }

  func testLargeBurstsNeverFastForwardTheirPrefixOrRevealABatch() {
    var reveal = TranscriptReveal()
    let text = String(repeating: "字", count: 10_000)
    reveal.retarget(to: text)
    XCTAssertEqual(reveal.text, text)
    var previousCount = 0
    for step in 0...30 {
      let frame = reveal.advance(at: 10 + Double(step) / 100)
      XCTAssertTrue((0...1).contains(frame.text.count - previousCount))
      XCTAssertLessThanOrEqual(frame.fading.count, 3)
      previousCount = frame.text.count
    }
    XCTAssertLessThan(previousCount, 12, "A large chunk must not jump directly to its last 32 characters")
    XCTAssertTrue(reveal.isAnimating(at: 10.3))
  }

  func testFastContinuousChunksPreservePrefixAndNeverReleaseMoreThanOneCharacterPerUpdate() {
    var reveal = TranscriptReveal()
    var text = ""
    var previousCount = 0
    for step in 0..<80 {
      let now = 10 + Double(step) * 0.0125
      text += "中文 abc 👩🏽‍💻 "
      reveal.retarget(to: text)
      let frame = reveal.advance(at: now)
      XCTAssertTrue(text.hasPrefix(frame.text))
      XCTAssertTrue((0...1).contains(frame.text.count - previousCount))
      previousCount = frame.text.count
    }
    assertDrainsExactly(&reveal, after: 11)
  }

  func testStalledFrameDoesNotCatchUpByDumpingQueuedCharacters() {
    var reveal = TranscriptReveal()
    reveal.retarget(to: "一二三四五六七八九十")
    XCTAssertEqual(reveal.advance(at: 10).text, "一")
    XCTAssertEqual(reveal.advance(at: 50).text, "一二")
    XCTAssertEqual(reveal.advance(at: 50).text, "一二")
    XCTAssertEqual(reveal.advance(at: 50.03001).text, "一二三")
  }

  func testEmptyQueueResumesWithOneCharacterAfterANetworkGap() {
    var reveal = TranscriptReveal()
    reveal.retarget(to: "你")
    _ = reveal.advance(at: 10)
    XCTAssertEqual(reveal.advance(at: 10.1).stableText, "你")
    XCTAssertFalse(reveal.isAnimating(at: 10.1))
    reveal.retarget(to: "你好，继续说话")
    XCTAssertEqual(reveal.advance(at: 20).text, "你好")
    XCTAssertEqual(reveal.advance(at: 20.03001).text, "你好，")
  }

  private func assertDrainsExactly(_ reveal: inout TranscriptReveal, after start: TimeInterval,
    file: StaticString = #filePath, line: UInt = #line) {
    var now = start
    var lastFrame = TranscriptReveal.Frame()
    for _ in 0..<(reveal.text.count + 10) {
      now += TranscriptReveal.characterInterval + 0.00001
      lastFrame = reveal.advance(at: now)
      if !reveal.isAnimating(at: now) { break }
    }
    XCTAssertFalse(reveal.isAnimating(at: now), file: file, line: line)
    XCTAssertEqual(lastFrame.stableText, reveal.text, file: file, line: line)
    XCTAssertTrue(lastFrame.fading.isEmpty, file: file, line: line)
  }
}

final class TranscriptPresentationTests: XCTestCase {
  @MainActor func testFrequentChunksShareContinuousPlaybackWithoutBatchFrames() async throws {
    let presentation = TranscriptPresentation(reduceMotion: { false })
    var counts: [Int] = []
    let observation = presentation.$frame.sink { counts.append($0.text.count) }
    defer {
      observation.cancel()
      presentation.finishImmediately()
    }
    presentation.update(String(repeating: "字", count: 40), isStatus: false)
    for length in 41...50 {
      try await Task.sleep(for: .milliseconds(5))
      presentation.update(String(repeating: "字", count: length), isStatus: false)
    }
    try await Task.sleep(for: .milliseconds(150))
    for (before, after) in zip(counts, counts.dropFirst()) {
      XCTAssertTrue((0...1).contains(after - before), "A network callback/tick must never dump a chunk")
    }
    XCTAssertGreaterThan(counts.last ?? 0, 2, "Playback must continue across frequent chunk updates")
    XCTAssertLessThan(counts.last ?? 0, 50)
    XCTAssertEqual(presentation.text.count, 50, "Only presentation is queued, not the authoritative text")
  }

  @MainActor func testFinalTextFlushesImmediatelyWithoutWaitingForDisplayAnimation() async throws {
    let presentation = TranscriptPresentation(reduceMotion: { false })
    presentation.update("正在聆听…", isStatus: true)
    presentation.update("我们明天下午三点开会。", isStatus: false)
    XCTAssertEqual(presentation.text, "我们明天下午三点开会。", "Authoritative output is never delayed")
    XCTAssertNotEqual(presentation.frame.stableText, presentation.text)
    presentation.update("我们明天下午四点开会。", isStatus: false, animated: false)
    XCTAssertEqual(presentation.frame.stableText, presentation.text)
    XCTAssertFalse(presentation.animatesChanges)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(presentation.frame.stableText, "我们明天下午四点开会。")
  }

  @MainActor func testCancelAndNextSessionCannotBeOverwrittenByOldAnimationTicks() async throws {
    let presentation = TranscriptPresentation(reduceMotion: { false })
    presentation.update("上一轮有很多尚未显示的文字", isStatus: false)
    presentation.update("已取消", isStatus: true)
    XCTAssertEqual(presentation.frame.stableText, "已取消")
    presentation.finishImmediately()
    presentation.update("正在聆听…", isStatus: true, animated: false)
    presentation.update("全新的下一轮文字", isStatus: false)
    XCTAssertTrue("全新的下一轮文字".hasPrefix(presentation.frame.text))
    try await Task.sleep(for: .milliseconds(600))
    XCTAssertEqual(presentation.frame.stableText, "全新的下一轮文字")
    XCTAssertTrue(presentation.frame.fading.isEmpty)
  }

  @MainActor func testReducedMotionBypassesCharacterAnimation() async throws {
    var reduced = true
    let presentation = TranscriptPresentation(reduceMotion: { reduced })
    presentation.update("减少动态效果时直接显示", isStatus: false)
    XCTAssertEqual(presentation.frame.stableText, presentation.text)
    XCTAssertFalse(presentation.animatesChanges)
    reduced = false
    presentation.update("减少动态效果时直接显示，恢复动画。", isStatus: false)
    XCTAssertTrue(presentation.animatesChanges)
    reduced = true
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(presentation.frame.stableText, presentation.text)
    XCTAssertFalse(presentation.animatesChanges)
  }

  @MainActor func testClosingPresentationDoesNotRetainAnAnimationTask() async throws {
    var presentation: TranscriptPresentation? = TranscriptPresentation(reduceMotion: { false })
    weak let weakPresentation = presentation
    presentation?.update("这一段动画还没有播放完成", isStatus: false)
    try await Task.sleep(for: .milliseconds(20))
    presentation = nil
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertNil(weakPresentation)
  }
}
