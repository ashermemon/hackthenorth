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
    /// One leg of the STT -> Gemini -> TTS chain, for the demo screen's "voice pipeline" readout.
    enum PipelineStep {
        case stt
        case gemini
        case tts
    }

    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: String?
    /// The most recent ElevenLabs TTS response, kept around so it can be replayed without
    /// re-running the whole STT -> Gemini -> TTS chain.
    @Published private(set) var lastResponseAudio: Data?
    /// The step currently in flight, nil when idle or between runs.
    @Published private(set) var activeStep: PipelineStep?
    /// Steps finished in the run currently in flight (or just finished), reset at the start of
    /// the next run — lets the UI show "done" for a step that's finished but not the newest one.
    @Published private(set) var completedSteps: Set<PipelineStep> = []
    @Published private(set) var sttDuration: TimeInterval?
    /// True only while the answer audio is actually playing — distinct from `isProcessing`, which
    /// also covers the STT/Gemini/TTS-synthesis work before any sound plays.
    @Published private(set) var isSpeaking = false
    @Published private(set) var lastQuestionText: String?
    @Published private(set) var lastAnswerText: String?

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

        // Capture the camera frame right now, at button release, as the PRD specifies. Waiting
        // until after speech-to-text (a second or two later) would answer "what's in front of
        // me?" about wherever the wearer had walked or turned to by then. Doing it here also
        // covers every trigger, since they all end up in this method.
        guard let frameJPEG = frameProvider.latestJPEG else {
            report(GeminiClient.GeminiError.noFrameAvailable, context: "no camera frame at release")
            playErrorTone()
            return
        }

        isProcessing = true
        lastError = nil
        playAcknowledgment()

        Task {
            await runPipeline(audioURL: url, frameJPEG: frameJPEG)
        }
    }

    /// Runs entirely off the caller's thread via `Task` — never called from, or blocking,
    /// the ARSession delegate callback or the belt's UDP loop.
    private func runPipeline(audioURL: URL, frameJPEG: Data) async {
        completedSteps = []
        sttDuration = nil
        defer {
            isProcessing = false
            activeStep = nil
        }

        do {
            activeStep = .stt
            let sttStarted = Date()
            guard let transcript = try await stt.transcribe(fileURL: audioURL) else {
                print("VoiceQueryController: empty transcript, stopping before Gemini")
                return
            }
            sttDuration = Date().timeIntervalSince(sttStarted)
            completedSteps.insert(.stt)
            lastQuestionText = transcript

            activeStep = .gemini
            let answer = try await gemini.answer(question: transcript, frameJPEG: frameJPEG)
            completedSteps.insert(.gemini)
            lastAnswerText = answer

            activeStep = .tts
            let audio = try await tts.synthesize(text: answer)
            completedSteps.insert(.tts)
            lastResponseAudio = audio

            activeStep = nil
            isSpeaking = true
            defer { isSpeaking = false }
            try await player.play(audio)
        } catch {
            report(error, context: "pipeline failed")
            playErrorTone()
        }
    }

    /// Plays the last response again, without re-running STT/Gemini/TTS. Same overlap guard
    /// as a fresh query, since it shares the same AudioPlayer/AVAudioSession.
    func replayLastResponse() {
        guard let audio = lastResponseAudio else { return }
        guard !isProcessing else {
            print("VoiceQueryController: query in flight, ignoring replay")
            return
        }

        isProcessing = true
        isSpeaking = true
        Task {
            defer {
                isProcessing = false
                isSpeaking = false
            }
            do {
                try await player.play(audio)
            } catch {
                report(error, context: "replay failed")
                playErrorTone()
            }
        }
    }

    /// Logs and shows an error with any API key removed. `lastError` is displayed on screen, and
    /// network errors can carry request details, so raw errors must never go straight to either.
    private func report(_ error: Error, context: String) {
        let message = ErrorText.safe(error, secrets: [Secrets.elevenLabsAPIKey, Secrets.geminiAPIKey])
        print("VoiceQueryController: \(context) — \(message)")
        lastError = message
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
