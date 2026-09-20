//
//  IntensityMapper.swift
//  Blind Sight
//
//  Zone distance -> PWM duty (0-255, the packet's scale), plus per-zone smoothing.
//

import Foundation

nonisolated enum IntensityMapper {
    /// Closer = stronger. nil or >= far -> 0. <= near -> 255. In between, a ramp that starts at
    /// `minFeltDuty` (not 1), because below that the motors don't produce a felt buzz.
    static func duty(forDistance distance: Float?, tuning t: BeltTuning) -> UInt8 {
        guard let distance, distance < t.farMeters else { return 0 }
        if distance <= t.nearMeters { return 255 }
        let closeness = (t.farMeters - distance) / (t.farMeters - t.nearMeters) // 0 far ... 1 near
        let shaped = Float(pow(Double(closeness), Double(t.intensityCurve)))
        let floor = Float(t.minFeltDuty)
        return UInt8(max(floor, min(255, floor + (255 - floor) * shaped)))
    }
}

/// Fast attack, slow release: a new or closer obstacle shows up on the belt immediately, but a
/// buzz fades instead of cutting out, which stops single-frame dropouts from flickering.
nonisolated struct ZoneSmoother {
    private var levels = [Float](repeating: 0, count: DepthProcessor.zoneCount)

    mutating func apply(_ targets: [UInt8], tuning t: BeltTuning) -> [UInt8] {
        for i in 0..<levels.count {
            let target = Float(targets[i])
            if target >= levels[i] {
                levels[i] = target
            } else {
                levels[i] += (target - levels[i]) * t.releaseFactor
                // Below the felt threshold a fading buzz is just silence; stop cleanly.
                if target == 0 && levels[i] < Float(t.minFeltDuty) { levels[i] = 0 }
            }
        }
        return levels.map { UInt8(max(0, min(255, $0.rounded()))) }
    }

    mutating func reset() {
        levels = [Float](repeating: 0, count: levels.count)
    }
}
