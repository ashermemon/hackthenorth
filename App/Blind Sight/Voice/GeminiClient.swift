//
//  GeminiClient.swift
//  Blind Sight
//
//  Gemini scene understanding (PRD "External API Calls" → "2. Scene understanding").
//

import Foundation
import UIKit

struct GeminiClient {
    enum GeminiError: Error {
        case noFrameAvailable
        case imageEncodingFailed
        case invalidResponse
        case emptyAnswer
        case httpError(status: Int, body: String)
    }

    private let apiKey: String
    private let model: String
    private let systemPrompt: String
    private let session: URLSession

    /// FrameProviding.latestJPEG (ARSessionManager) already returns a JPEG at full ARKit
    /// capture resolution and 0.8 quality — plenty for a human, far more than Gemini needs
    /// for a quick scene-description call. Re-encoding down to this long edge/quality before
    /// sending keeps the request small and fast without a visible accuracy cost at this task's
    /// granularity.
    private let maxLongEdge: CGFloat = 1024
    private let jpegQuality: CGFloat = 0.7

    init(
        apiKey: String = Secrets.geminiAPIKey,
        model: String = AppConfig.geminiModel,
        systemPrompt: String = AppConfig.geminiSystemPrompt,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.session = session
    }

    /// Compresses `frameJPEG` and asks Gemini the question with `AppConfig.geminiSystemPrompt` as
    /// system instruction — sent verbatim, per the PRD's note that the uncertainty-handling
    /// clause is load-bearing. The caller captures the frame when the button is released and
    /// passes it in, so the answer is about what the camera saw then, not whatever it sees by
    /// the time speech-to-text has finished.
    func answer(question: String, frameJPEG sourceJPEG: Data) async throws -> String {
        guard let compressedJPEG = Self.recompress(jpegData: sourceJPEG, maxLongEdge: maxLongEdge, quality: jpegQuality) else {
            throw GeminiError.imageEncodingFailed
        }

        // The key goes in a header, never the URL: a URL's query string is copied into URLError text
        // (NSErrorFailingURLStringKey), which this app prints and shows on screen when a request fails.
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!

        let body = RequestBody(
            systemInstruction: .init(parts: [.init(text: systemPrompt)]),
            contents: [
                .init(role: "user", parts: [
                    .init(text: question),
                    .init(inlineData: .init(mimeType: "image/jpeg", data: compressedJPEG.base64EncodedString()))
                ])
            ]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GeminiError.httpError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let text = decoded.candidates?.first?.content?.parts?.first?.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw GeminiError.emptyAnswer
        }
        return text
    }

    private static func recompress(jpegData: Data, maxLongEdge: CGFloat, quality: CGFloat) -> Data? {
        guard let image = UIImage(data: jpegData) else { return nil }
        let size = image.size
        let longEdge = max(size.width, size.height)

        guard longEdge > maxLongEdge else {
            return image.jpegData(compressionQuality: quality)
        }

        let scale = maxLongEdge / longEdge
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

// MARK: - Wire types (Gemini generateContent v1beta REST shape)

private struct RequestBody: Encodable {
    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
    }

    struct SystemInstruction: Encodable { let parts: [Part] }
    struct Content: Encodable { let role: String; let parts: [Part] }

    struct Part: Encodable {
        var text: String?
        var inlineData: InlineData?

        enum CodingKeys: String, CodingKey {
            case text
            case inlineData = "inline_data"
        }

        init(text: String) { self.text = text }
        init(inlineData: InlineData) { self.inlineData = inlineData }
    }

    struct InlineData: Encodable {
        let mimeType: String
        let data: String
        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case data
        }
    }

    let systemInstruction: SystemInstruction
    let contents: [Content]
}

private struct ResponseBody: Decodable {
    struct Candidate: Decodable { let content: Content? }
    struct Content: Decodable { let parts: [Part]? }
    struct Part: Decodable { let text: String? }
    let candidates: [Candidate]?
}
