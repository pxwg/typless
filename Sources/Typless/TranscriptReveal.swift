import Foundation

/// Presentation only. All indices are extended grapheme clusters, never UTF-16
/// offsets; model output and the text eventually pasted are not modified.
struct TranscriptReveal {
  static let characterInterval = 0.030
  static let fadeDuration = 0.070

  struct FadingCharacter: Equatable {
    let text: String
    let opacity: Double
  }

  struct Frame: Equatable {
    var stableText = ""
    var fading: [FadingCharacter] = []
    var text: String { stableText + fading.map(\.text).joined() }
  }

  private struct CharacterTiming {
    let character: Character
    let appearedAt: TimeInterval
  }

  private(set) var text = ""
  private var characters: [Character] = []
  private var revealed: [CharacterTiming] = []
  private var nextCharacterAt: TimeInterval = -.infinity

  mutating func reset(to text: String = "") {
    self.text = text
    characters = Array(text)
    revealed = characters.map { CharacterTiming(character: $0, appearedAt: -.infinity) }
    nextCharacterAt = -.infinity
  }

  mutating func retarget(to text: String) {
    guard text != self.text else { return }
    let incoming = Array(text)
    let common = zip(characters, incoming).prefix { $0 == $1 }.count
    // Corrections to already visible words replace them in place. Do not erase
    // and replay the whole sentence when ASR changes an early word/punctuation.
    let retained = min(revealed.count, incoming.count)
    revealed = (0..<retained).map { index in
      index < common ? revealed[index] : CharacterTiming(character: incoming[index], appearedAt: -.infinity)
    }
    self.text = text
    characters = incoming
    // Appending/correcting chunks changes the queue, never the playback clock.
    // In particular, do not fast-forward long chunks or assign them one deadline.
  }

  func isAnimating(at now: TimeInterval) -> Bool {
    revealed.count < characters.count || revealed.contains { $0.appearedAt + Self.fadeDuration > now }
  }

  mutating func advance(at now: TimeInterval) -> Frame {
    // Consume at most ONE grapheme per presentation update, even after a long
    // main-thread stall. Wall-clock catch-up would recreate the chunk-sized jumps.
    if revealed.count < characters.count, now >= nextCharacterAt {
      revealed.append(CharacterTiming(character: characters[revealed.count], appearedAt: now))
      nextCharacterAt = now + Self.characterInterval
    }
    var frame = Frame()
    for character in revealed {
      let opacity = max(0, min(1, (now - character.appearedAt) / Self.fadeDuration))
      if opacity == 1, frame.fading.isEmpty {
        frame.stableText.append(character.character)
      } else {
        frame.fading.append(FadingCharacter(text: String(character.character), opacity: opacity))
      }
    }
    return frame
  }
}
