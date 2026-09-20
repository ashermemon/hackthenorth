//
//  VolumeEventClassifier.swift
//  Blind Sight
//
//  Decides whether a change in the system output volume was the wearer pressing a volume button
//  or just the app's own audio activity. Pure logic, so it can be tested on the Mac.
//

import Foundation

nonisolated enum VolumeEvent: Equatable {
    case down
    case up
    /// No change relative to the baseline; nothing to do.
    case unchanged
    /// Caused by the app's own audio session activity, not a button. Never acted on.
    case ignored
}

/// Compares each reported volume with a baseline, but only trusts changes that happen outside a
/// "quiet" window after the app touches the audio session itself. Switching category (record to
/// playback), starting a beep or finishing playback can all make `outputVolume` report a
/// different value, and without this every one of those looked like a button press: Volume Up
/// replayed the last answer while the mic was live, and Volume Down could stop a recording the
/// instant it began.
nonisolated struct VolumeEventClassifier {
    var baseline: Float

    init(baseline: Float) {
        self.baseline = baseline
    }

    /// While ignoring our own activity the baseline follows the new value: the volume the OS now
    /// reports is the level the wearer's next real press should be measured against, not the stale
    /// one from before our audio change.
    mutating func classify(newVolume: Float, now: Date, quietUntil: Date) -> VolumeEvent {
        if now < quietUntil {
            baseline = newVolume
            return .ignored
        }
        if newVolume < baseline { return .down }
        if newVolume > baseline { return .up }
        return .unchanged
    }
}

/// Where the app records that it is about to change, or has just changed, the audio session.
/// Everything that does so (recording, cues, playback) calls `mark()`; the volume watcher reads
/// `quietUntil`. All callers run on the main thread.
enum OwnAudioActivity {
    /// Long enough for the OS's volume notifications from a session change to arrive.
    static let quietSeconds: TimeInterval = 0.5
    private(set) static var quietUntil = Date.distantPast

    static func mark(now: Date = Date()) {
        quietUntil = max(quietUntil, now.addingTimeInterval(quietSeconds))
    }
}
