//
//  AppConfig.swift
//  Blind Sight
//
//  Non-secret, shared configuration. API keys live in Secrets.swift (gitignored) instead.
//

import Foundation

enum AppConfig {
    // MARK: - ESP32 / belt link (PRD "Data Flow & Communication Protocol")

    /// TODO(belt): set to the ESP32's address on the phone↔ESP32 local WiFi link.
    static let esp32Host = "192.168.4.1"
    static let esp32Port: UInt16 = 4210

    /// PRD: "a few times per second — fast enough to feel responsive, not so fast it floods the WiFi link."
    static let beltUpdateHz: Double = 5

    // MARK: - Gemini (PRD "External API Calls")

    /// Confirm this model ID is still current at build time (PRD note).
    static let geminiModel = "gemini-3.5-flash-lite"

    /// Exact system prompt from the PRD — the uncertainty instruction is load-bearing, don't trim it for brevity.
    static let geminiSystemPrompt = """
    You are a visual assistant for a blind or low-vision user wearing a chest-mounted camera. \
    You receive one photo and one spoken question at a time. Answer in 1–2 short sentences \
    suitable for being read aloud — no preamble, no restating the question. Answer the specific \
    question directly and first. For yes/no questions, start with "yes" or "no" before any detail. \
    If asked to read text (a sign, label, screen), transcribe it exactly rather than summarizing \
    it. If you're not confident about something, say so plainly ("I can't tell clearly, but...") \
    rather than guessing with false confidence — an inaccurate answer stated confidently could put \
    the user at risk. The camera may be close to held objects or angled from chest height, not eye \
    level, so framing may be unusual.
    """
}
