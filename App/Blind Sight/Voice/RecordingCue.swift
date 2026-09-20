//
//  RecordingCue.swift
//  Blind Sight
//
//  The cue played the instant recording starts: a firm haptic tap plus a short beep. Distinct
//  from the lighter tap + chime VoiceQueryController plays on release, so the wearer can tell
//  "mic is on" from "question sent".
//

import AVFoundation
import UIKit

final class RecordingCue {
    private let tone = ToneSynth.beepWAV()
    private var player: AVAudioPlayer?

    /// Call after the audio session is active (AudioRecorder sets it up first) so the beep goes
    /// out the speaker and the haptic isn't suppressed by the recording session.
    func play() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        do {
            let beep = try AVAudioPlayer(data: tone)
            beep.volume = 0.7
            beep.play()
            player = beep // keep it alive until it finishes
        } catch {
            print("RecordingCue: couldn't play start tone — \(error)")
        }
    }
}
