//
//  IntensityMapper.swift
//  Blind Sight
//
//  Zone distance -> urgency (0-255, the packet's scale), plus per-zone smoothing.
//  Urgency is what the belt turns into a pulse rate: 0 off, 1...254 pulses (faster = higher),
//  255 solid. See BeltTuning.
//

import Foundation

nonisolated enum IntensityMapper {
    static let solid: UInt8 = 255
    /// The fastest pulsing value: one below solid, which is reserved for "obstacle at the near limit".
    static let fastestPulse: UInt8 = 254

    /// Closer = more urgent. nil or >= far -> 0 (silent). <= near -> 255 (solid). In between, a ramp
    /// from `minUrgency` (slowest pulses, at the far edge) up to 254 (fastest pulses, just outside near).
    static func urgency(forDistance distance: Float?, tuning t: BeltTuning) -> UInt8 {
        guard let distance, distance < t.farMeters else { return 0 }
        if distance <= t.nearMeters { return solid }
        let closeness = (t.farMeters - distance) / (t.farMeters - t.nearMeters) // 0 far ... 1 near
        let shaped = Float(pow(Double(closeness), Double(t.intensityCurve)))
        let floor = Float(max(1, t.minUrgency)) // 0 means "off", so a real obstacle never maps to it
        let top = Float(fastestPulse)
        return UInt8(max(floor, min(top, floor + (top - floor) * shaped)))
    }
}

/// Fast attack, slow release. A closer obstacle shows up on the belt immediately. An obstacle that
/// is still there but moving away lowers the urgency gradually, so the pulse rate doesn't jitter.
/// An obstacle that is gone silences the zone at once: a fading tail would keep the belt pulsing
/// for a second after the way is clear, and a single bad frame is already filtered out upstream
/// (DistanceFilter).
nonisolated struct ZoneSmoother {
    private var levels = [Float](repeating: 0, count: DepthProcessor.zoneCount)

    mutating func apply(_ targets: [UInt8], tuning t: BeltTuning) -> [UInt8] {
        for i in 0..<levels.count {
            let target = Float(targets[i])
            if target == 0 {
                levels[i] = 0
            } else if target >= levels[i] {
                levels[i] = target
            } else {
                levels[i] += (target - levels[i]) * t.releaseFactor
            }
        }
        return levels.map { UInt8(max(0, min(255, $0.rounded()))) }
    }

    mutating func reset() {
        levels = [Float](repeating: 0, count: levels.count)
    }
}
