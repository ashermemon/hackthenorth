//
//  BeltTuning.swift
//  Blind Sight
//
//  Every number that shapes belt behavior, in one place, so on-device tuning never means
//  hunting through the processing code. BeltController holds a live copy the debug screen edits.
//

import Foundation

nonisolated struct BeltTuning {
    // MARK: Distance -> urgency (PRD: min-distance threshold = max, far threshold = silent)
    //
    // What goes to the belt per zone is URGENCY, not motor strength: 0 = off, 255 = solid buzz,
    // and 1...254 = pulses that come faster the closer the obstacle (the ESP32 turns that into a
    // pulse rate; see firmware/belt_arduino/belt_pulse.h). Every pulse has the same strength, so
    // there is no weakest-felt-buzz to tune.

    /// At or closer than this, the zone buzzes solid (255).
    var nearMeters: Float = 0.5
    /// At or beyond this, the zone is silent (0).
    var farMeters: Float = 2.0
    /// Urgency at the far edge, where pulses are slowest. 1 uses the whole rate range.
    var minUrgency: UInt8 = 1
    /// 1 = urgency rises linearly with closeness (pulse rate then rises geometrically, which is
    /// what feels like even steps); >1 keeps it gentle until the obstacle is close.
    var intensityCurve: Float = 1.0
    /// A zone's distance is the median of its last N readings (one per belt tick; a clear reading
    /// counts as infinitely far), so a reading has to hold up over most of a short window before it
    /// buzzes, and one noisy frame can neither start nor cut a buzz. 1 turns this off. Costs about
    /// one tick (200 ms at 5 Hz) of extra reaction time when an obstacle first appears.
    var distanceWindow: Int = 3
    /// How fast urgency comes DOWN while an obstacle is still there but moving away (0...1 per
    /// tick; 1 = instant), which keeps the pulse rate from jittering. Rising urgency is not
    /// smoothed, and an obstacle that is gone switches the zone off at once: `distanceWindow`
    /// already stops one bad frame from doing that.
    var releaseFactor: Float = 0.5

    // MARK: Depth filtering

    /// LiDAR readings closer than this are unreliable.
    var minRangeMeters: Float = 0.25
    /// ARConfidenceLevel raw value: 0 low, 1 medium, 2 high. Pixels below this are discarded.
    var minConfidence: UInt8 = 1
    /// Look at every Nth depth pixel in each direction (2 = a quarter of the map).
    var sampleStride: Int = 2
    /// A zone only reports a distance once this many sampled pixels are at or closer than it,
    /// so a single noisy pixel can't trigger a buzz.
    var minSupportSamples: Int = 8

    // MARK: Zones and ground/overhead rejection

    /// Bearing edges between zones are -x, 0, +x degrees from where the wearer faces; the two
    /// outer zones extend to the edge of the camera's view. nil (default) splits the camera's actual
    /// left/right view into four equal strips, working out the view's width from how the phone is
    /// rolled: about +-27 degrees in portrait, +-34 in landscape. Set a number to force it. Note the
    /// belt's hip motors (-70/+70 in the PRD) map to the far left/right of the camera's view, not
    /// the actual hip direction.
    var zoneOuterEdgeDegrees: Float? = nil
    /// Assumed height of the phone above the floor (chest mount).
    var cameraHeightMeters: Float = 1.2
    /// Points within this distance of the assumed floor are treated as ground, not obstacles.
    var groundClearanceMeters: Float = 0.3
    /// Points higher than this above the phone are treated as overhead, not in the path. Chest-height
    /// phone + head is roughly 0.5 m above it, so keep some margin above that; door frames and
    /// ceilings sit around 0.8 m or more above the phone.
    var overheadClearanceMeters: Float = 0.7
}
