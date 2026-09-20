//
//  VoiceQueryController.swift
//  Blind Sight
//
//  Voice query pipeline owner: build out this file (and others under Voice/).
//

import Foundation

/// Owns the push-to-talk voice query loop (PRD "Voice query (event-driven, on button press)"):
/// Volume Down press/release (`AVCaptureEventInteraction`) → grab a JPEG frame from a
/// `FrameProviding` → ElevenLabs STT → Gemini (`AppConfig.geminiModel` / `geminiSystemPrompt`)
/// → ElevenLabs TTS → play through the speaker. Runs independently of the belt loop — a slow
/// or failed API call must never stall it.
final class VoiceQueryController {
    /// Inject `ARSessionManager.shared` for the real app, `MockFrameProvider()` to build/test
    /// this whole pipeline in Simulator without ARKit (which never runs sceneDepth there).
    private let frameProvider: FrameProviding

    init(frameProvider: FrameProviding = ARSessionManager.shared) {
        self.frameProvider = frameProvider
    }

    // TODO(voice): wire AVCaptureEventInteraction, then the STT → Gemini → TTS chain.
    // A hardcoded transcript string in place of real STT output is a fine way to test the
    // Gemini/TTS half before STT is wired up — no shared scaffolding needed for that part.
}
