//
//  AudioPlayer.swift
//  Blind Sight
//
//  Plays a TTS response through the speaker (PRD "Outputs" → "Spoken response").
//

import AVFoundation

final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    enum AudioPlayerError: Error {
        case failedToStart
        case decodeError(Error?)
    }

    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Error>?

    /// Plays `data` through the phone speaker and suspends until playback finishes (or fails).
    /// Switches the session to .playback rather than reusing .playAndRecord's earpiece-prone
    /// routing — without this, answers are nearly inaudible with no headphones plugged in.
    func play(_ data: Data) async throws {
        OwnAudioActivity.mark()
        defer { OwnAudioActivity.mark() } // playback ending changes the session too
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, options: [])
        try session.setActive(true)

        let newPlayer = try AVAudioPlayer(data: data)
        newPlayer.delegate = self
        player = newPlayer

        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            guard newPlayer.play() else {
                self.continuation = nil
                continuation.resume(throwing: AudioPlayerError.failedToStart)
                return
            }
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        continuation?.resume()
        continuation = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        continuation?.resume(throwing: AudioPlayerError.decodeError(error))
        continuation = nil
    }
}
