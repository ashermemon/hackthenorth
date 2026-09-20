//
//  AudioRecorder.swift
//  Blind Sight
//

import AVFoundation
import Combine

/// Push-to-talk mic capture (PRD "Microphone" input). Call `start()` on button press, `stop()`
/// on release — `stop()` returns the file it wrote, or nil if nothing was in progress. This
/// class only owns capture; handing the file to ElevenLabs STT is the next step.
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false

    private var recorder: AVAudioRecorder?

    /// No-op if already recording. Requests mic permission if it hasn't been decided yet.
    func start() {
        guard !isRecording else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("AudioRecorder: failed to activate audio session — \(error)")
            return
        }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            beginRecording()
        case .undetermined:
            // Fires on a background thread.
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard granted else {
                        print("AudioRecorder: microphone permission denied")
                        return
                    }
                    self?.beginRecording()
                }
            }
        case .denied:
            print("AudioRecorder: microphone permission denied — enable it in Settings")
        @unknown default:
            print("AudioRecorder: unknown microphone permission state")
        }
    }

    /// Stops recording and returns the file it wrote. nil if nothing was in progress.
    @discardableResult
    func stop() -> URL? {
        guard isRecording, let recorder else { return nil }
        recorder.stop()
        isRecording = false
        let url = recorder.url
        self.recorder = nil
        return url
    }

    private func beginRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.prepareToRecord()
            newRecorder.record()
            recorder = newRecorder
            isRecording = true
        } catch {
            print("AudioRecorder: failed to start recording — \(error)")
        }
    }
}
