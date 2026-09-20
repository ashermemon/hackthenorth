//
//  VoiceQueryController.swift
//  Blind Sight
//
//  Owns the STT -> Gemini -> TTS -> playback chain (PRD "Voice query (event-driven, on
//  button press)"). Call handleRecordingFinished(url:) from wherever a recording just
//  completed — all three trigger sources (on-screen button, CaptureEventTrigger,
//  VolumeButtonWatcher) hand off here the same way, since none of them need to know
//  anything about what happens after the file is written.
//

import AudioToolbox
import Foundation
import UIKit
import Combine

@MainActor
final class VoiceQueryController: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: String?

    private let frameProvider: FrameProviding
    private let stt: ElevenLabsSTT
    private let gemini: GeminiClient
    private let tts: ElevenLabsTTS
    private let player: AudioPlayer

    /// Inject `ARSessionManager.shared` for the real app, `MockFrameProvider()` to build/test
    /// this whole pipeline in Simulator without ARKit (which never runs sceneDepth there).
    init(
        frameProvider: FrameProviding = ARSessionManager.shared,
        stt: ElevenLabsSTT = ElevenLabsSTT(),
        gemini: GeminiClient = GeminiClient(),
        tts: ElevenLabsTTS = ElevenLabsTTS(),
        player: AudioPlayer = AudioPlayer()
    ) {
        self.frameProvider = frameProvider
        self.stt = stt
        self.gemini = gemini
        self.tts = tts
        self.player = player
    }

    /// Entry point for every trigger source. Reentrant-safe: a press while a query is
    /// already in flight is ignored rather than queued or allowed to overlap, since the
    /// STT/TTS calls would otherwise fight over the shared AVAudioSession.
    func handleRecordingFinished(url: URL?) {
        guard let url else { return }
        guard !isProcessing else {
            print("VoiceQueryController: query already in flight, ignoring")
            return
        }

        isProcessing = true
        lastError = nil
        playAcknowledgment()

        Task {
            await runPipeline(audioURL: url)
        }
    }

    /// Runs entirely off the caller's thread via `Task` — never called from, or blocking,
    /// the ARSession delegate callback or the belt's UDP loop.
    private func runPipeline(audioURL: URL) async {
        defer { isProcessing = false }

        do {
            guard let transcript = try await stt.transcribe(fileURL: audioURL) else {
                print("VoiceQueryController: empty transcript, stopping before Gemini")
                return
            }

            let answer = try await gemini.answer(question: transcript, frameProvider: frameProvider)
            let audio = try await tts.synthesize(text: answer)
            try await player.play(audio)
        } catch {
            // Never log the raw API keys — only the error itself, which URLSession/Codable
            // errors don't embed.
            print("VoiceQueryController: pipeline failed — \(error)")
            lastError = String(describing: error)
            playErrorTone()
        }
    }

    // MARK: - Local feedback

    private func playAcknowledgment() {
        // A short, unobtrusive chime plus haptic — the wearer needs to know the request
        // registered during the multi-second round trip (PRD: "don't let silence be the
        // only feedback"). System sound IDs aren't officially documented by Apple; verify
        // this one sounds right on-device and swap it if not.
        AudioServicesPlaySystemSound(1113)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func playErrorTone() {
        // Deliberately distinct from the acknowledgment tone above.
        AudioServicesPlaySystemSound(1006)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
