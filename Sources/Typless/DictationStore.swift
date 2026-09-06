import AppKit
import Combine

struct DictationEntry: Codable, Identifiable {
  var id = UUID()
  var date = Date()
  let text: String
  let rawText: String
  let duration: TimeInterval
  let appName: String
  var wordCount: Int {
    var count = 0
    let latin = String(text.map { character -> Character in
      let scalar = character.unicodeScalars.first?.value ?? 0
      if (0x3400...0x9FFF).contains(scalar) || (0x20000...0x3134F).contains(scalar)
        || (0x3040...0x30FF).contains(scalar) || (0xAC00...0xD7AF).contains(scalar) {
        count += 1
        return " "
      }
      return character
    })
    latin.enumerateSubstrings(in: latin.startIndex..., options: .byWords) { _, _, _, _ in count += 1 }
    return count
  }
}

@MainActor
final class DictationStore: ObservableObject {
  @Published private(set) var entries: [DictationEntry] = []
  @Published private(set) var words: [String] = []
  @Published var errorMessage: String?
  private let directory: URL

  init(directory: URL? = nil) {
    self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Typless", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      entries = try read([DictationEntry].self, "history.json") ?? []
      words = try read([String].self, "dictionary.json") ?? []
    } catch { errorMessage = "无法读取本地记录：\(error.localizedDescription)" }
  }

  func add(_ entry: DictationEntry) {
    var next = entries
    next.insert(entry, at: 0)
    if save(next, "history.json") { entries = next }
  }
  func delete(_ id: UUID) {
    let next = entries.filter { $0.id != id }
    if save(next, "history.json") { entries = next }
  }
  func clearHistory() { if save([DictationEntry](), "history.json") { entries = [] } }
  func addWords(_ input: String) {
    let candidates = input.components(separatedBy: CharacterSet(charactersIn: "\n,，")).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }.filter { !$0.isEmpty && $0.count <= 100 }
    var next = words
    for word in candidates where !next.contains(where: { $0.localizedCaseInsensitiveCompare(word) == .orderedSame }) { next.append(word) }
    if save(next, "dictionary.json") { words = next }
  }
  func deleteWord(_ word: String) {
    let next = words.filter { $0 != word }
    if save(next, "dictionary.json") { words = next }
  }
  func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
  var totalWords: Int { entries.reduce(0) { $0 + $1.wordCount } }
  var totalDuration: TimeInterval { entries.reduce(0) { $0 + $1.duration } }
  var savedMinutes: Int { max(0, Int(Double(totalWords) / 40 - totalDuration / 60)) }
  var activeDays: Int { Set(entries.map { Calendar.current.startOfDay(for: $0.date) }).count }

  private func read<T: Decodable>(_ type: T.Type, _ name: String) throws -> T? {
    let url = directory.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }
  private func save<T: Encodable>(_ value: T, _ name: String) -> Bool {
    do {
      let url = directory.appendingPathComponent(name)
      try JSONEncoder().encode(value).write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      errorMessage = nil
      return true
    } catch { errorMessage = "无法保存本地记录：\(error.localizedDescription)"; return false }
  }
}
