import SwiftUI
@preconcurrency import AVFoundation
import NookCore

@MainActor
struct AudioRecorderView: View {
    let save: (URL) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recorder: AVAudioRecorder?
    @State private var temporary: URL?
    @State private var paused = false
    @State private var error: String?
    @State private var starting = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "waveform").font(.system(size: 64)).foregroundStyle(Theme.accent)
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text(Duration.seconds(recorder?.currentTime ?? 0).formatted(.time(pattern: .minuteSecond))).font(.largeTitle.monospacedDigit())
                }
                if recorder != nil {
                    Button(paused ? "Resume Recording" : "Pause Recording") {
                        if paused { recorder?.record() } else { recorder?.pause() }
                        paused.toggle()
                    }.buttonStyle(.bordered)
                    Button("Save Recording") { finish() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Start Recording") { Task { await start() } }.buttonStyle(.borderedProminent).disabled(starting)
                }
                if let error { Text(verbatim: error).foregroundStyle(Pastel.rose.strong) }
            }.padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
            .navigationTitle("Audio Note").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .interactiveDismissDisabled(recorder?.isRecording == true)
        .onDisappear {
            recorder?.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            if let temporary { try? FileManager.default.removeItem(at: temporary) }
        }
    }
    private func start() async {
        starting = true; defer { starting = false }
        guard await AVAudioApplication.requestRecordPermission() else {
            error = String(localized: "Allow microphone access in Settings to record audio."); return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audio.setActive(true)
            let url = FileManager.default.temporaryDirectory.appending(path: "Nook-Recording-\(UUID()).m4a")
            temporary = url
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            guard recorder.record(forDuration: 3600) else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
        } catch { self.error = error.localizedDescription }
    }
    private func finish() {
        guard let recorder, let temporary else { return }
        recorder.stop(); paused = true
        do { try save(temporary); dismiss() } catch { self.error = error.localizedDescription }
    }
}

@MainActor
struct AudioPlaybackView: View {
    let url: URL
    let appendText: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVAudioPlayer?
    @State private var transcriber = SpeechInput()
    @State private var error: String?
    @State private var transcribing = false
    @State private var transcript = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        VStack(spacing: 16) {
                            Text(Duration.seconds(player?.currentTime ?? 0).formatted(.time(pattern: .minuteSecond))).font(.largeTitle.monospacedDigit())
                            Slider(value: Binding(get: { player?.currentTime ?? 0 }, set: { player?.currentTime = $0 }), in: 0...max(1, player?.duration ?? 1))
                            Button("Play / Pause") {
                                if player?.isPlaying == true { player?.pause() } else { player?.play() }
                            }
                        }.padding(.vertical)
                    }
                }
                Section {
                    Button("Transcribe on This Device") {
                        player?.pause(); transcribing = true
                        Task {
                            defer { transcribing = false }
                            do { transcript = try await transcriber.transcribe(url: url) }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(transcribing)
                    if transcribing { ProgressView() }
                    if !transcript.isEmpty {
                        TextEditor(text: $transcript).frame(minHeight: 140)
                        Button("Insert Transcript into Note") { appendText(transcript); dismiss() }
                    }
                } footer: { Text("Audio stays on this device during transcription. Review the text before inserting it.") }
                if let error { Text(verbatim: error).foregroundStyle(Pastel.rose.strong) }
            }
            .navigationTitle("Audio Note").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                player = try AVAudioPlayer(contentsOf: url); player?.prepareToPlay()
            } catch { self.error = error.localizedDescription }
        }
        .onDisappear { player?.stop(); transcriber.stop(); try? AVAudioSession.sharedInstance().setActive(false) }
    }
}
