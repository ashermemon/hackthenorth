//
//  VoiceQueryController.swift
//  Blind Sight
//
//  Voice query pipeline owner: build out this file (and others under Voice/).
//

import Foundation

/// Owns the push-to-talk voice query loop (PRD "Voice query (event-driven, on button press)"):
/// Volume Down press/release (`AVCaptureEventInteraction`) → record mic → grab the current RGB
/// frame from `ARSessionManager.shared.latestFrame` → ElevenLabs STT → Gemini
/// (`AppConfig.geminiModel` / `geminiSystemPrompt`) → ElevenLabs TTS → play through the speaker.
/// Runs independently of the belt loop — a slow or failed API call must never stall it.
final class VoiceQueryController {
    // TODO(voice): wire AVCaptureEventInteraction, then the STT → Gemini → TTS chain.
}
