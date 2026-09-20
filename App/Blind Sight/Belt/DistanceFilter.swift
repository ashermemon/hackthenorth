//
//  DistanceFilter.swift
//  Blind Sight
//
//  Persistence filter for the per-zone obstacle distances, so the belt only buzzes for readings
//  that hold up over time rather than for whatever a single noisy depth frame happened to show.
//

import Foundation

nonisolated struct DistanceFilter {
    /// Each zone's most recent raw readings, oldest first. `.infinity` = nothing detected.
    private var history = [[Float]](repeating: [], count: DepthProcessor.zoneCount)

    /// Adds this tick's raw readings and returns the median of each zone's last `window` ones.
    /// Readings that haven't happened yet count as "clear", so after a reset (or at launch) an
    /// obstacle has to be seen on most of a window before it registers, the same as any other time.
    mutating func apply(_ zones: [Float?], window: Int) -> [Float?] {
        let size = max(1, window)
        var filtered = [Float?](repeating: nil, count: zones.count)
        for (zone, reading) in zones.enumerated() {
            var recent = history[zone]
            if recent.count < size {
                recent.insert(contentsOf: [Float](repeating: .infinity, count: size - recent.count), at: 0)
            }
            recent.append(reading ?? .infinity)
            if recent.count > size { recent.removeFirst(recent.count - size) }
            history[zone] = recent

            let median = recent.sorted()[size / 2]
            filtered[zone] = median.isFinite ? median : nil
        }
        return filtered
    }

    mutating func reset() {
        history = [[Float]](repeating: [], count: DepthProcessor.zoneCount)
    }
}
