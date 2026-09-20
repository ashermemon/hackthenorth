//
//  DepthProcessor.swift
//  Blind Sight
//
//  Depth map -> nearest obstacle distance per belt zone. Deliberately free of ARKit so it can
//  be tested on the Mac (see App/BeltSelfTest); DepthSnapshot+ARKit.swift adapts an ARFrame.
//

import Foundation
import simd

/// Pinhole camera model for one depth map, plus the camera's pose in ARKit world space.
nonisolated struct DepthGeometry {
    /// Focal lengths and principal point in *depth-map* pixels (not the RGB image's).
    var fx: Float
    var fy: Float
    var cx: Float
    var cy: Float
    /// ARCamera.transform: columns 0/1/2 are the camera's right/up/back axes in world space
    /// (camera looks along -z; world y is up under ARKit's default gravity alignment).
    var cameraToWorld: simd_float4x4
}

/// A copy of one frame's depth data, safe to hand to a background queue.
nonisolated struct DepthSnapshot {
    var width: Int
    var height: Int
    /// Meters along the camera's optical axis, row-major (width * height).
    var depth: [Float]
    /// 0 low, 1 medium, 2 high per pixel, same layout as `depth`; nil = trust everything.
    var confidence: [UInt8]?
    var geometry: DepthGeometry
}

nonisolated enum DepthProcessor {
    static let zoneCount = 4
    /// Histogram resolution for the nearest-reading search.
    static let binMeters: Float = 0.05

    /// Nearest reliable obstacle distance (meters, horizontal) in each belt zone, ordered
    /// left hip -> right hip; nil where nothing is within `tuning.farMeters`.
    ///
    /// Each depth pixel is lifted to a 3D point, then judged in a gravity-aligned frame around
    /// the wearer rather than in image space. That is what makes the result independent of how
    /// the phone is tilted or rolled: floor and overhead points are rejected by height, and the
    /// left/right zone comes from the point's bearing relative to where the wearer is facing.
    static func zoneDistances(_ s: DepthSnapshot, tuning t: BeltTuning) -> [Float?] {
        var result = [Float?](repeating: nil, count: zoneCount)
        let g = s.geometry
        let m = g.cameraToWorld
        let rightAxis = SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z)
        let upAxis = SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z)
        let backAxis = SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)

        // The wearer's facing direction: the camera's view direction flattened onto the floor.
        // If the phone points almost straight up or down, "forward" is undefined.
        var forward = SIMD3<Float>(-backAxis.x, 0, -backAxis.z)
        let flatLength = simd_length(forward)
        guard flatLength > 0.2 else { return result }
        forward /= flatLength
        let side = SIMD3<Float>(-forward.z, 0, forward.x) // forward x up: to the wearer's right

        let minHeight = -(t.cameraHeightMeters - t.groundClearanceMeters)
        let maxHeight = t.overheadClearanceMeters
        // How far left/right the view reaches depends on the phone's roll (portrait or landscape):
        // weight the image's half-widths by how much each camera axis points sideways.
        let sidewaysOfRight = abs(simd_dot(rightAxis, side))
        let sidewaysOfUp = abs(simd_dot(upAxis, side))
        let halfViewTangent = (g.cx / g.fx) * sidewaysOfRight + (g.cy / g.fy) * sidewaysOfUp
        let edge = t.zoneOuterEdgeDegrees.map { $0 * .pi / 180 } ?? atan(halfViewTangent) / 2
        let bins = Int(t.farMeters / binMeters) + 1
        var counts = [Int32](repeating: 0, count: zoneCount * bins)
        let step = max(1, t.sampleStride)
        let columnFactor = (0..<s.width).map { (Float($0) - g.cx) / g.fx }

        for v in stride(from: 0, to: s.height, by: step) {
            let rowFactor = -(Float(v) - g.cy) / g.fy
            for u in stride(from: 0, to: s.width, by: step) {
                let index = v * s.width + u
                let z = s.depth[index]
                guard z.isFinite, z >= t.minRangeMeters else { continue }
                if let confidence = s.confidence, confidence[index] < t.minConfidence { continue }

                // Camera-space point -> offset from the camera in world axes.
                let offset = rightAxis * (columnFactor[u] * z) + upAxis * (rowFactor * z) - backAxis * z
                guard offset.y >= minHeight, offset.y <= maxHeight else { continue }
                let ahead = simd_dot(offset, forward)
                guard ahead > 0.05 else { continue }
                let lateral = simd_dot(offset, side)
                let distance = (ahead * ahead + lateral * lateral).squareRoot()
                guard distance < t.farMeters else { continue }

                let bearing = atan2(lateral, ahead)
                let zone = bearing < -edge ? 0 : bearing < 0 ? 1 : bearing < edge ? 2 : 3
                counts[zone * bins + Int(distance / binMeters)] += 1
            }
        }

        for zone in 0..<zoneCount {
            var cumulative = 0
            for bin in 0..<bins {
                cumulative += Int(counts[zone * bins + bin])
                if cumulative >= t.minSupportSamples {
                    result[zone] = (Float(bin) + 0.5) * binMeters
                    break
                }
            }
        }
        return result
    }
}
