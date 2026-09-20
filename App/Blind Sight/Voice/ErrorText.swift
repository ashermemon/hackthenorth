//
//  ErrorText.swift
//  Blind Sight
//
//  Turns an error into text that is safe to print and to show on screen.
//

import Foundation

nonisolated enum ErrorText {
    /// On-screen space is small, and API error bodies can be long.
    static let maxLength = 300

    /// `String(describing:)` of the error with every secret replaced by "[redacted]" and the
    /// result shortened. Secrets under 8 characters are ignored, so an unset (empty) key can't
    /// turn into a replace-everything.
    static func safe(_ error: Error, secrets: [String]) -> String {
        var text = String(describing: error)
        for secret in secrets where secret.count >= 8 {
            text = text.replacingOccurrences(of: secret, with: "[redacted]")
        }
        return text.count > maxLength ? String(text.prefix(maxLength)) + "…" : text
    }
}
