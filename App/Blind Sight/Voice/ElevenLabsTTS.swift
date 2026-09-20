//
//  ElevenLabsTTS.swift
//  Blind Sight
//
//  ElevenLabs text-to-speech (PRD "External API Calls" → "3. Text-to-Speech").
//

import Foundation

struct ElevenLabsTTS {
    enum TTSError: Error {
        case invalidResponse
        case httpError(status: Int, body: String)
    }

    /// Default ElevenLabs premade voice ("Rachel"). Swap for a project-specific voice ID if
    /// you have one — nothing else in the pipeline depends on which voice this is.
    static let defaultVoiceID = "21m00Tcm4TlvDq8ikWAM"

    private let apiKey: String
    private let voiceID: String
    private let model: String
    private let session: URLSession

    init(
        apiKey: String = Secrets.elevenLabsAPIKey,
        voiceID: String = ElevenLabsTTS.defaultVoiceID,
        model: String = "eleven_flash_v2_5",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.model = model
        self.session = session
    }

    func synthesize(text: String) async throws -> Data {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(RequestBody(text: text, modelID: model))

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TTSError.httpError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private struct RequestBody: Encodable {
        let text: String
        let modelID: String
        enum CodingKeys: String, CodingKey {
            case text
            case modelID = "model_id"
        }
    }
}
