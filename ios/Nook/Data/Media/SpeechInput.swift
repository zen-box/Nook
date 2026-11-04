import Foundation
import Observation
@preconcurrency import AVFoundation
@preconcurrency import Speech

@MainActor @Observable
final class SpeechInput {
    private(set) var isListening = false
    private(set) var text = ""
    private(set) var error: String?
    var onText: ((String) -> Void)?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasTap = false
    private var generation = 0
    private var fileContinuation: CheckedContinuation<String, any Error>?

    func transcribe(url: URL) async throws -> String {
        stop()
        let ticket = generation
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard generation == ticket, !Task.isCancelled else { throw CancellationError() }
        guard authorization == .authorized, let recognizer = SFSpeechRecognizer(locale: .current),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw CocoaError(.featureUnsupported) }
        let request = SFSpeechURLRecognitionRequest(url: url); request.requiresOnDeviceRecognition = true
        return try await withCheckedThrowingContinuation { continuation in
            fileContinuation = continuation
            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let text = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                let failed = failure != nil
                Task { @MainActor [weak self] in
                    guard let self, let continuation = self.fileContinuation, text != nil || failed else { return }
                    self.fileContinuation = nil
                    if let text { continuation.resume(returning: text) }
                    else { continuation.resume(throwing: CocoaError(.coderReadCorrupt)) }
                    self.task = nil
                }
            }
        }
    }

    func start() async {
        guard !isListening else { return }
        generation += 1; let ticket = generation; error = nil
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard ticket == generation else { return }
        guard microphone else { error = String(localized: "Allow microphone access in Settings to record audio."); return }
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard ticket == generation else { return }
        guard authorization == .authorized else { error = String(localized: "Allow speech recognition in Settings to use voice input."); return }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            error = String(localized: "On-device recognition is unavailable for this language. Type your request instead; no audio has been uploaded."); return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            self.request = request; text = ""
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            hasTap = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let value = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true || failure != nil
                let description = failure?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.generation == ticket else { return }
                    if let value { self.text = value; self.onText?(value) }
                    if let description { self.error = description }
                    if finished { self.stop() }
                }
            }
            engine.prepare(); try engine.start(); isListening = true
        } catch { self.error = error.localizedDescription; stop() }
    }
    func stop() {
        generation += 1
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil; isListening = false
        fileContinuation?.resume(throwing: CancellationError()); fileContinuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
