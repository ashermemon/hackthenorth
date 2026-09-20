//
//  ElevenLabsSTT.swift
//  Blind Sight
//
//  ElevenLabs speech-to-text (PRD "External API Calls" → "1. Speech-to-Text").
//

import Foundation

struct ElevenLabsSTT {
    enum STTError: Error {
        case invalidResponse
        case httpError(status: Int, body: String)
    }

    private let apiKey: String
    private let session: URLSession

    /// ElevenLabs' STT model. Distinct from eleven_flash_v2_5 (a text-to-speech voice model,
    /// used in ElevenLabsTTS.swift) — that ID is not valid on this endpoint.
    private let model = "scribe_v1"

    init(apiKey: String = Secrets.elevenLabsAPIKey, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Transcribes the recorded file. Returns nil for an empty/whitespace-only transcript —
    /// callers should treat that as "nothing to do," not call Gemini with an empty question.
    func transcribe(fileURL: URL) async throws -> String? {
        let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fields: ["model_id": model],
            fileField: "file",
            fileName: fileURL.lastPathComponent,
            fileMimeType: "audio/m4a",
            fileData: audioData
        )

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw STTError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw STTError.httpError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func multipartBody(
        boundary: String,
        fields: [String: String],
        fileField: String,
        fileName: String,
        fileMimeType: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(string.data(using: .utf8)!)
        }

        for (key, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(fileMimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n")

        append("--\(boundary)--\r\n")
        return body
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}
