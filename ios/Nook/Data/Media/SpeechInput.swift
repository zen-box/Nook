import Foundation
import Observation
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// Voice input and on-device transcription.
///
/// The audio tap and the speech callbacks run on background threads. They are created in the
/// `nonisolated` helpers at the bottom, never in main-actor code: Swift 6 treats a closure
/// written inside a main-actor method as main-actor code and stops the app when the audio
/// thread calls it.
@MainActor @Observable
final class SpeechInput {
    private(set) var isListening = false
    private(set) var isPreparing = false
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
        let authorization = await Self.requestSpeechAuthorization()
        guard generation == ticket, !Task.isCancelled else { throw CancellationError() }
        guard authorization == .authorized, let recognizer = SFSpeechRecognizer(locale: .current),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw CocoaError(.featureUnsupported) }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        return try await withCheckedThrowingContinuation { continuation in
            fileContinuation = continuation
            task = Self.recognize(request, with: recognizer) { [weak self] text, isFinal, failure in
                guard let self, let continuation = self.fileContinuation else { return }
                if isFinal, let text {
                    self.fileContinuation = nil
                    self.task = nil
                    continuation.resume(returning: text)
                } else if failure != nil {
                    self.fileContinuation = nil
                    self.task = nil
                    continuation.resume(throwing: CocoaError(.coderReadCorrupt))
                }
            }
        }
    }

    func start() async {
        guard !isListening, !isPreparing else { return }
        generation += 1
        let ticket = generation
        error = nil
        isPreparing = true
        defer { if ticket == generation { isPreparing = false } }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard ticket == generation else { return }
        guard microphone else {
            error = String(localized: "Allow microphone access in Settings to record audio.")
            return
        }
        let authorization = await Self.requestSpeechAuthorization()
        guard ticket == generation else { return }
        guard authorization == .authorized else {
            error = String(localized: "Allow speech recognition in Settings to use voice input.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            error = String(localized: "On-device recognition is unavailable for this language. Type your request instead; no audio has been uploaded.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            text = ""
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
            Self.installTap(on: input, format: format, feeding: request)
            hasTap = true
            task = Self.recognize(request, with: recognizer) { [weak self] value, isFinal, failure in
                guard let self, self.generation == ticket else { return }
                if let value {
                    self.text = value
                    self.onText?(value)
                }
                if let failure, !isFinal, value == nil {
                    self.error = failure
                }
                if isFinal || failure != nil {
                    self.stop()
                }
            }
            engine.prepare()
            try engine.start()
            isListening = true
        } catch {
            self.error = String(localized: "Voice input couldn't start. Check that no other app is using the microphone, then try again.")
            stop()
        }
    }

    func stop() {
        generation += 1
        isPreparing = false
        if engine.isRunning {
            engine.stop()
        }
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        fileContinuation?.resume(throwing: CancellationError())
        fileContinuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Background callbacks

    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// The tap block runs on the real-time audio thread and only hands buffers to the request.
    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, feeding request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    /// Results arrive on a background queue; `update` is called on the main actor.
    nonisolated private static func recognize(
        _ request: SFSpeechRecognitionRequest,
        with recognizer: SFSpeechRecognizer,
        update: @escaping @MainActor @Sendable (_ text: String?, _ isFinal: Bool, _ failure: String?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, failure in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let message = failure?.localizedDescription
            Task { @MainActor in
                update(text, isFinal, message)
            }
        }
    }
}
