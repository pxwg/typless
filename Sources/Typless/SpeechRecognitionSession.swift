import AVFoundation

/// Captures microphone PCM only. All recognition is performed by Qwen Realtime.
@MainActor
final class SpeechRecognitionSession {
  var onTranscript: ((String) -> Void)?
  var onLevel: ((Double) -> Void)?
  var onFailure: ((Error) -> Void)?
  private let audioEngine = AVAudioEngine()
  private var client: QwenRealtimeClient?
  private var tapInstalled = false
  private var completion: ((DictationResult) -> Void)?
  private var encoder: PCMEncoder?

  func start(configuration: QwenConfiguration, language: RecognitionLanguage, mode: WritingMode, dictionary: [String]) throws {
    let input = audioEngine.inputNode
    let source = input.outputFormat(forBus: 0)
    guard source.sampleRate > 0, source.channelCount > 0 else {
      throw QwenError(message: "未找到可用的麦克风。")
    }
    let encoder = try PCMEncoder(source: source)
    self.encoder = encoder
    let client = QwenRealtimeClient(configuration: configuration, language: language, mode: mode, dictionary: dictionary)
    self.client = client
    client.onTranscript = { [weak self] in self?.onTranscript?($0) }
    client.onFailure = { [weak self] error in self?.stopAudio(); self?.onFailure?(error) }
    client.onResult = { [weak self] result in
      guard let self else { return }
      completion?(result)
      completion = nil
    }
    input.installTap(onBus: 0, bufferSize: 2048, format: source) { [weak self] buffer, _ in
      do {
        let (pcm, level) = try encoder.encode(buffer)
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          self.client?.append(pcm)
          onLevel?(level)
        }
      } catch {
        DispatchQueue.main.async { [weak self] in self?.cancel(); self?.onFailure?(error) }
      }
    }
    tapInstalled = true
    audioEngine.prepare()
    do { try audioEngine.start(); client.start() }
    catch { cancel(); throw error }
  }

  func finish(completion: @escaping (DictationResult) -> Void) {
    self.completion = completion
    stopAudio()
    // Audio callbacks already queued on main drain before commit.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      do {
        if let tail = try encoder?.finish(), !tail.isEmpty { client?.append(tail) }
        client?.finish()
      } catch { cancel(); onFailure?(error) }
    }
  }

  func cancel() {
    stopAudio()
    completion = nil
    client?.cancel()
    client = nil
  }

  private func stopAudio() {
    if audioEngine.isRunning { audioEngine.stop() }
    if tapInstalled { audioEngine.inputNode.removeTap(onBus: 0); tapInstalled = false }
  }
}

/// AVAudioConverter maintains resampling state across microphone buffers.
final class PCMEncoder {
  let format: AVAudioFormat
  private let converter: AVAudioConverter

  init(source: AVAudioFormat) throws {
    guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
      let converter = AVAudioConverter(from: source, to: target) else {
      throw QwenError(message: "无法转换麦克风音频格式。")
    }
    self.format = target
    self.converter = converter
    converter.primeMethod = .none
  }

  func encode(_ input: AVAudioPCMBuffer) throws -> (Data, Double) {
    let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16000 / input.format.sampleRate)) + 64
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
      throw QwenError(message: "无法分配音频缓冲区。")
    }
    var supplied = false
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, state in
      if supplied { state.pointee = .noDataNow; return nil }
      supplied = true
      state.pointee = .haveData
      return input
    }
    if status == .error { throw error ?? QwenError(message: "音频转换失败。") as NSError }
    guard let samples = output.int16ChannelData?[0] else { return (Data(), 0) }
    let count = Int(output.frameLength)
    var square = 0.0
    for i in 0..<count { square += pow(Double(samples[i]) / 32768, 2) }
    let rms = sqrt(square / Double(max(1, count)))
    let level = max(0, min(1, (20 * log10(max(rms, 0.00001)) + 55) / 45))
    return (Data(bytes: samples, count: count * 2), level)
  }

  func finish() throws -> Data {
    var tail = Data()
    while true {
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
      var error: NSError?
      let status = converter.convert(to: buffer, error: &error) { _, state in
        state.pointee = .endOfStream
        return nil
      }
      if status == .error { throw error ?? QwenError(message: "无法结束音频转换。") as NSError }
      if let samples = buffer.int16ChannelData?[0], buffer.frameLength > 0 {
        tail.append(Data(bytes: samples, count: Int(buffer.frameLength) * 2))
      }
      if status == .endOfStream || buffer.frameLength == 0 { return tail }
    }
  }
}
