import Foundation

/// One connection per dictation. A single sender preserves PCM/commit ordering.
@MainActor
final class QwenRealtimeClient {
  var onTranscript: ((String) -> Void)?
  var onReady: (() -> Void)?
  var onResult: ((DictationResult) -> Void)?
  var onFailure: ((Error) -> Void)?
  var onEvent: ((String) -> Void)?
  private let configuration: QwenConfiguration
  private let language: RecognitionLanguage
  private let mode: WritingMode
  private let dictionary: [String]
  private let stream: AsyncStream<Data>
  private let continuation: AsyncStream<Data>.Continuation
  private var session: URLSession?
  private var socket: URLSessionWebSocketTask?
  private var sendTask: Task<Void, Never>?
  private var receiveTask: Task<Void, Never>?
  private var timeout: Task<Void, Never>?
  private var stopped = false
  private var finishing = false
  private var rawText: String?
  private var outputText = ""
  private var responseComplete = false
  private var responseRequested = false
  private var pendingWritingInstructions: String?
  private var byteCount = 0
  private var sentByteCount = 0
  private var hasSignal = false

  init(configuration: QwenConfiguration, language: RecognitionLanguage, mode: WritingMode, dictionary: [String] = []) {
    self.configuration = configuration
    self.language = language
    self.mode = mode
    self.dictionary = dictionary
    (stream, continuation) = AsyncStream.makeStream(of: Data.self)
  }

  func start() {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 20
    let session = URLSession(configuration: config)
    self.session = session
    var request = URLRequest(url: configuration.url)
    request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
    let socket = session.webSocketTask(with: request)
    self.socket = socket
    socket.resume()
    setTimeout(seconds: 20, message: "连接 Qwen 超时，请检查网络和模型权限。")
    sendTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await send("session.update", fields: ["session": QwenProtocol.session(language: language, mode: mode, dictionary: dictionary, systemPrompt: configuration.systemPrompt)])
        while !stopped {
          let event = try await receive()
          if event["type"] as? String == "session.updated" {
            let accepted = event["session"] as? [String: Any] ?? [:]
            if let vad = accepted["turn_detection"], !(vad is NSNull) {
              throw QwenError(message: "Qwen 未接受手动录音模式。")
            }
            if let audio = accepted["audio"] as? [String: Any],
              let input = audio["input"] as? [String: Any], let format = input["format"] as? [String: Any],
              (format["sample_rate"] as? Int != 16000 || format["type"] as? String != "pcm") {
              throw QwenError(message: "Qwen 未接受 16 kHz PCM 音频格式。")
            }
            break
          }
        }
        guard !stopped else { return }
        if !finishing { timeout?.cancel() }
        onReady?()
        receiveTask = Task { [weak self] in
          guard let self else { return }
          do { while !stopped { try await handle(try await receive()) } }
          catch { fail(error) }
        }
        for await pcm in stream {
          guard !stopped else { return }
          try await send("input_audio_buffer.append", fields: ["audio": pcm.base64EncodedString()])
          sentByteCount += pcm.count
        }
        guard !stopped else { return }
        guard sentByteCount >= 3200, hasSignal else { succeed(DictationResult(text: "", rawText: "")); return }
        try await send("input_audio_buffer.commit")
      } catch { fail(error) }
    }
  }

  func append(_ pcm: Data) {
    guard !stopped, !finishing else { return }
    byteCount += pcm.count
    if !hasSignal { hasSignal = pcm.contains(where: { $0 != 0 }) }
    guard byteCount <= 16000 * 2 * 300 + 32000 else {
      fail(QwenError(message: "录音超过五分钟，请分段输入。")); return
    }
    continuation.yield(pcm)
  }

  func finish() {
    guard !stopped, !finishing else { return }
    finishing = true
    continuation.finish()
    setTimeout(seconds: 45, message: "Qwen 转写超时，请检查网络后重试。")
  }

  func cancel() {
    guard !stopped else { return }
    stopped = true
    continuation.finish()
    sendTask?.cancel()
    receiveTask?.cancel()
    timeout?.cancel()
    socket?.cancel(with: .normalClosure, reason: nil)
    session?.invalidateAndCancel()
    socket = nil
    session = nil
  }

  private func send(_ type: String, fields: [String: Any] = [:]) async throws {
    guard let socket, !stopped else { throw CancellationError() }
    var event = fields
    event["event_id"] = "event_\(UUID().uuidString)"
    event["type"] = type
    onEvent?("send:\(type)")
    let data = try JSONSerialization.data(withJSONObject: event)
    try await socket.send(.string(String(decoding: data, as: UTF8.self)))
  }

  private func receive() async throws -> [String: Any] {
    guard let socket else { throw CancellationError() }
    let event: [String: Any]
    switch try await socket.receive() {
    case .data(let data): event = try QwenProtocol.decode(data)
    case .string(let text): event = try QwenProtocol.decode(Data(text.utf8))
    @unknown default: throw QwenError(message: "Qwen 返回了未知的数据类型。")
    }
    onEvent?(event["type"] as? String ?? "unknown")
    return event
  }

  private func handle(_ event: [String: Any]) async throws {
    switch event["type"] as? String {
    case "conversation.item.input_audio_transcription.delta":
      onTranscript?(QwenProtocol.transcriptionPreview(event))
    case "conversation.item.input_audio_transcription.completed":
      rawText = event["transcript"] as? String ?? ""
      // Omni can omit ASR completion if response.create races its input transcription.
      // Finish ASR first, then give the editor the complete draft as data. Asking
      // Omni to edit directly from audio often degenerates into verbatim output.
      if mode == .polished, !responseRequested {
        if rawText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
          succeed(DictationResult(text: "", rawText: ""))
          return
        }
        responseRequested = true
        let instructions = try QwenProtocol.refinementInstructions(rawText: rawText ?? "", language: language, dictionary: dictionary, systemPrompt: configuration.systemPrompt)
        pendingWritingInstructions = instructions
        try await send("session.update", fields: ["session": ["instructions": instructions]])
      }
      completeIfReady()
    case "session.updated":
      if let instructions = pendingWritingInstructions {
        let accepted = event["session"] as? [String: Any] ?? [:]
        guard accepted["instructions"] as? String == instructions else {
          throw QwenError(message: "Qwen 未接受文字整理指令。")
        }
        pendingWritingInstructions = nil
        try await send("response.create")
      }
    case "conversation.item.input_audio_transcription.failed":
      throw QwenError(message: "Qwen 未能识别这段录音，请重试。")
    case "response.text.delta":
      outputText += event["delta"] as? String ?? ""
      onTranscript?(outputText)
    case "response.text.done":
      if let text = event["text"] as? String { outputText = text }
    case "response.done":
      let response = event["response"] as? [String: Any] ?? [:]
      guard response["status"] as? String == "completed" else { throw QwenError(message: "Qwen 文字整理未完成。") }
      if outputText.isEmpty {
        let items = response["output"] as? [[String: Any]] ?? []
        outputText = items.flatMap { $0["content"] as? [[String: Any]] ?? [] }.compactMap { $0["text"] as? String }.joined()
      }
      responseComplete = true
      completeIfReady()
    default: break
    }
  }

  private func completeIfReady() {
    guard finishing, let rawText, mode == .verbatim || responseComplete else { return }
    let raw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    let text = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
    // ASR gates generative output: silence must never become invented dictation.
    succeed(DictationResult(text: raw.isEmpty ? "" : (mode == .polished && !text.isEmpty ? text : raw), rawText: raw))
  }

  private func succeed(_ result: DictationResult) {
    guard !stopped else { return }
    cancel()
    onResult?(result)
  }

  private func fail(_ error: Error) {
    guard !stopped else { return }
    let safe = configuration.sanitized(error)
    if finishing, let rawText, !rawText.isEmpty {
      succeed(DictationResult(text: rawText, rawText: rawText, warning: "整理失败，已保留 Qwen 原始转写。\(safe.message)"))
    } else { cancel(); onFailure?(safe) }
  }

  private func setTimeout(seconds: Double, message: String) {
    timeout?.cancel()
    timeout = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
      self?.fail(QwenError(message: message))
    }
  }
}
