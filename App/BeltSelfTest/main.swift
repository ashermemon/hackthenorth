//
//  main.swift
//  BeltSelfTest
//
//  Tests for the belt's depth -> zone -> intensity logic, run on the Mac with run.sh.
//  Depth maps are rendered from small synthetic 3D scenes (walls, floor, boxes) through the
//  same pinhole model ARKit uses, so the tests exercise the real geometry, including a
//  phone that is pitched down and rolled into portrait.
//

import Foundation
import simd

// MARK: - Tiny test harness

setvbuf(stdout, nil, _IONBF, 0)
var failures = 0
var checks = 0

func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition {
        failures += 1
        print("  FAIL: \(message)")
    }
}

func describe(_ zones: [Float?]) -> String {
    "[" + zones.map { $0.map { String(format: "%.2f", $0) } ?? "nil" }.joined(separator: ", ") + "]"
}

func expectZone(_ zones: [Float?], _ index: Int, near expected: Float, tolerance: Float = 0.12, _ label: String) {
    if let value = zones[index] {
        check(abs(value - expected) <= tolerance, "\(label): zone \(index) = \(value), expected ~\(expected) (all: \(describe(zones)))")
    } else {
        check(false, "\(label): zone \(index) = nil, expected ~\(expected) (all: \(describe(zones)))")
    }
}

func expectNil(_ zones: [Float?], _ index: Int, _ label: String) {
    check(zones[index] == nil, "\(label): zone \(index) should be nil (all: \(describe(zones)))")
}

// MARK: - Synthetic scene rendering

let width = 256, height = 192
let fx: Float = 190, fy: Float = 190, cx: Float = 128, cy: Float = 96

/// Camera pose: `position` in world, pitch about world x (negative = looking down), roll about the
/// camera's own view axis (90 deg = phone held in portrait). World is y-up, camera looks along -z.
func cameraPose(position: SIMD3<Float>, pitchDegrees: Float = 0, rollDegrees: Float = 0) -> simd_float4x4 {
    let pitch = simd_quatf(angle: pitchDegrees * .pi / 180, axis: SIMD3<Float>(1, 0, 0))
    let roll = simd_quatf(angle: rollDegrees * .pi / 180, axis: SIMD3<Float>(0, 0, 1))
    var m = simd_float4x4(pitch * roll)
    m.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1)
    return m
}

/// An axis-aligned plane the ray may hit, limited to where `contains` says the surface exists.
struct Surface {
    var axis: Int
    var value: Float
    var contains: (SIMD3<Float>) -> Bool

    func hit(origin: SIMD3<Float>, direction: SIMD3<Float>) -> Float? {
        guard abs(direction[axis]) > 1e-6 else { return nil }
        let t = (value - origin[axis]) / direction[axis]
        guard t > 0.05 else { return nil }
        return contains(origin + t * direction) ? t : nil
    }
}

/// Renders what a LiDAR at `pose` would measure. Rays use z = -1 in camera space, so the hit
/// parameter t is exactly the z-depth ARKit reports.
func render(_ surfaces: [Surface], pose: simd_float4x4, confidence: UInt8? = 2) -> DepthSnapshot {
    let origin = SIMD3<Float>(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z)
    var depth = [Float](repeating: 0, count: width * height)
    for v in 0..<height {
        for u in 0..<width {
            let local = SIMD4<Float>((Float(u) - cx) / fx, -(Float(v) - cy) / fy, -1, 0)
            let world = pose * local
            let direction = SIMD3<Float>(world.x, world.y, world.z)
            depth[v * width + u] = surfaces.compactMap { $0.hit(origin: origin, direction: direction) }.min() ?? 0
        }
    }
    let geometry = DepthGeometry(fx: fx, fy: fy, cx: cx, cy: cy, cameraToWorld: pose)
    return DepthSnapshot(width: width, height: height, depth: depth,
                         confidence: confidence.map { [UInt8](repeating: $0, count: width * height) },
                         geometry: geometry)
}

func everywhere(_: SIMD3<Float>) -> Bool { true }
let floorSurface = Surface(axis: 1, value: 0, contains: everywhere)
func wall(zAt z: Float) -> Surface { Surface(axis: 2, value: z, contains: everywhere) }

let tuning = BeltTuning()
let eye = SIMD3<Float>(0, 1.2, 0)

// MARK: - Depth processing

print("Depth processing")

do { // a flat wall 1 m ahead fills every zone
    let zones = DepthProcessor.zoneDistances(render([wall(zAt: -1)], pose: cameraPose(position: eye)), tuning: tuning)
    for z in 0..<4 { expectZone(zones, z, near: 1.0, tolerance: 0.15, "wall ahead") }
}

do { // an obstacle on the left half only lights only the left zones
    let leftHalf = Surface(axis: 2, value: -1, contains: { $0.x < 0 })
    let zones = DepthProcessor.zoneDistances(render([leftHalf], pose: cameraPose(position: eye)), tuning: tuning)
    expectZone(zones, 0, near: 1.0, tolerance: 0.15, "left half")
    expectZone(zones, 1, near: 1.0, tolerance: 0.15, "left half")
    expectNil(zones, 2, "left half")
    expectNil(zones, 3, "left half")
}

do { // a wall beyond the far threshold is ignored
    let zones = DepthProcessor.zoneDistances(render([wall(zAt: -4)], pose: cameraPose(position: eye)), tuning: tuning)
    for z in 0..<4 { expectNil(zones, z, "wall out of range") }
}

do { // open floor, camera pitched down 30 degrees: the ground must never read as an obstacle
    let zones = DepthProcessor.zoneDistances(render([floorSurface], pose: cameraPose(position: eye, pitchDegrees: -30)), tuning: tuning)
    for z in 0..<4 { expectNil(zones, z, "floor, pitched 30 down") }
}

do { // same for the slight downward tilt of a chest mount
    let zones = DepthProcessor.zoneDistances(render([floorSurface], pose: cameraPose(position: eye, pitchDegrees: -12)), tuning: tuning)
    for z in 0..<4 { expectNil(zones, z, "floor, pitched 12 down") }
}

do { // a box on the floor ahead of a downward-tilted camera is seen, the floor around it is not
    let box = Surface(axis: 2, value: -1.2, contains: { abs($0.x) < 0.3 && $0.y > 0 && $0.y < 1.0 })
    let zones = DepthProcessor.zoneDistances(render([floorSurface, box], pose: cameraPose(position: eye, pitchDegrees: -12)), tuning: tuning)
    expectZone(zones, 1, near: 1.2, tolerance: 0.2, "box ahead")
    expectZone(zones, 2, near: 1.2, tolerance: 0.2, "box ahead")
    expectNil(zones, 0, "box ahead")
    expectNil(zones, 3, "box ahead")
}

do { // portrait mount (rolled 90 deg), tilted down: a wall on the wearer's LEFT still lands in zone 0
    let leftWall = Surface(axis: 0, value: -0.6, contains: { $0.z < 0 })
    let pose = cameraPose(position: eye, pitchDegrees: -12, rollDegrees: 90)
    let zones = DepthProcessor.zoneDistances(render([floorSurface, leftWall], pose: pose), tuning: tuning)
    check(zones[0] != nil, "portrait left wall: zone 0 should see it (all: \(describe(zones)))")
    expectNil(zones, 2, "portrait left wall")
    expectNil(zones, 3, "portrait left wall")
    // and the mirror image on the right
    let rightWall = Surface(axis: 0, value: 0.6, contains: { $0.z < 0 })
    let mirrored = DepthProcessor.zoneDistances(render([floorSurface, rightWall], pose: pose), tuning: tuning)
    check(mirrored[3] != nil, "portrait right wall: zone 3 should see it (all: \(describe(mirrored)))")
    expectNil(mirrored, 0, "portrait right wall")
    expectNil(mirrored, 1, "portrait right wall")
}

do { // zone strips stay equal however the phone is held: landscape sees wider, so its zone edges widen
    let atRight = { (x0: Float, x1: Float) in Surface(axis: 2, value: -1, contains: { $0.x > x0 && $0.x < x1 }) }
    let landscape = cameraPose(position: eye)
    let portrait = cameraPose(position: eye, rollDegrees: 90)
    // ~20-24 degrees right of centre: the outer-right zone in both orientations
    for (name, pose) in [("landscape", landscape), ("portrait", portrait)] {
        let zones = DepthProcessor.zoneDistances(render([atRight(0.36, 0.45)], pose: pose), tuning: tuning)
        check(zones[3] != nil && zones[2] == nil && zones[0] == nil, "\(name): object 20-24 degrees right -> outer right zone (all: \(describe(zones)))")
    }
    // ~6-11 degrees right: the inner-right zone in both
    for (name, pose) in [("landscape", landscape), ("portrait", portrait)] {
        let zones = DepthProcessor.zoneDistances(render([atRight(0.1, 0.2)], pose: pose), tuning: tuning)
        check(zones[2] != nil && zones[3] == nil && zones[1] == nil, "\(name): object 6-11 degrees right -> inner right zone (all: \(describe(zones)))")
    }
    // ~29-34 degrees right is inside landscape's view but outside portrait's
    let wide = DepthProcessor.zoneDistances(render([atRight(0.55, 0.75)], pose: landscape), tuning: tuning)
    check(wide[3] != nil, "landscape sees 29-34 degrees right (all: \(describe(wide)))")
    let narrow = DepthProcessor.zoneDistances(render([atRight(0.55, 0.75)], pose: portrait), tuning: tuning)
    check(narrow.allSatisfy { $0 == nil }, "portrait can't see 29-34 degrees right (all: \(describe(narrow)))")
}

do { // level camera (no downward tilt), portrait: the floor is in range but must still be rejected
    let zones = DepthProcessor.zoneDistances(render([floorSurface], pose: cameraPose(position: eye, rollDegrees: 90)), tuning: tuning)
    for z in 0..<4 { expectNil(zones, z, "level portrait, floor in view") }
}

do { // a chest-high obstacle is seen by a level camera in either orientation
    let post = Surface(axis: 2, value: -1.5, contains: { abs($0.x) < 0.2 && $0.y > 0.9 && $0.y < 1.6 })
    for (name, roll): (String, Float) in [("landscape", 0), ("portrait", 90)] {
        let zones = DepthProcessor.zoneDistances(render([floorSurface, post], pose: cameraPose(position: eye, rollDegrees: roll)), tuning: tuning)
        check(zones[1] != nil && zones[2] != nil, "\(name), level: chest-high post ahead seen in the middle zones (all: \(describe(zones)))")
    }
}

do { // low-confidence pixels are discarded
    let zones = DepthProcessor.zoneDistances(render([wall(zAt: -1)], pose: cameraPose(position: eye), confidence: 0), tuning: tuning)
    for z in 0..<4 { expectNil(zones, z, "low confidence") }
}

do { // a lone noisy pixel does not register, a real object does
    var snapshot = render([wall(zAt: -3)], pose: cameraPose(position: eye))
    snapshot.depth[96 * width + 128] = 0.6
    let zones = DepthProcessor.zoneDistances(snapshot, tuning: tuning)
    for z in 0..<4 { expectNil(zones, z, "single noisy pixel") }
}

do { // camera pointing straight down has no defined forward: report nothing rather than garbage
    let zones = DepthProcessor.zoneDistances(render([floorSurface], pose: cameraPose(position: eye, pitchDegrees: -90)), tuning: tuning)
    for z in 0..<4 { expectNil(zones, z, "pointing straight down") }
}

// MARK: - Intensity mapping

print("Intensity mapping")

check(IntensityMapper.duty(forDistance: nil, tuning: tuning) == 0, "nil distance -> 0")
check(IntensityMapper.duty(forDistance: tuning.farMeters, tuning: tuning) == 0, "at far threshold -> 0")
check(IntensityMapper.duty(forDistance: 9, tuning: tuning) == 0, "beyond far -> 0")
check(IntensityMapper.duty(forDistance: tuning.nearMeters, tuning: tuning) == 255, "at near threshold -> 255")
check(IntensityMapper.duty(forDistance: 0.1, tuning: tuning) == 255, "closer than near -> 255")
check(IntensityMapper.duty(forDistance: tuning.farMeters - 0.01, tuning: tuning) >= tuning.minFeltDuty, "just inside far starts at the felt threshold")
do {
    var previous: UInt8 = 0
    var monotonic = true
    for d in stride(from: tuning.farMeters - 0.1, through: tuning.nearMeters, by: -0.05) {
        let duty = IntensityMapper.duty(forDistance: d, tuning: tuning)
        if duty < previous { monotonic = false }
        previous = duty
    }
    check(monotonic, "closer never gives a weaker buzz")
}
check(IntensityMapper.duty(forDistance: 1.2, tuning: tuning) > tuning.minFeltDuty
      && IntensityMapper.duty(forDistance: 1.2, tuning: tuning) < 255, "mid distance is strictly between min and max")

// MARK: - Smoothing

print("Smoothing")

do {
    var smoother = ZoneSmoother()
    var out = smoother.apply([0, 200, 0, 255], tuning: tuning)
    check(out == [0, 200, 0, 255], "rising intensity applies immediately (got \(out))")
    out = smoother.apply([0, 0, 0, 0], tuning: tuning)
    check(out[1] > 0 && out[1] < 200, "a vanished obstacle fades rather than cutting out (got \(out))")
    for _ in 0..<10 { out = smoother.apply([0, 0, 0, 0], tuning: tuning) }
    check(out == [0, 0, 0, 0], "fade ends in clean silence (got \(out))")
}

// MARK: - Persistence filter

print("Persistence filter")

do {
    var f = DistanceFilter()
    var out = f.apply([1.0, nil, nil, nil], window: 3)
    check(out[0] == nil, "one reading alone does not register (got \(describe(out)))")
    out = f.apply([1.1, nil, nil, nil], window: 3)
    check(out[0] == 1.1, "second matching reading registers, at the further of the two (got \(describe(out)))")
    out = f.apply([nil, nil, nil, nil], window: 3)
    check(out[0] == 1.1, "one dropout does not cut a held obstacle (got \(describe(out)))")
    out = f.apply([nil, nil, nil, nil], window: 3)
    check(out[0] == nil, "two clears in a row release it (got \(describe(out)))")
}

do { // a one-frame spike (a noisy reading in a clear zone) never gets through, however often it happens
    var f = DistanceFilter()
    var everNonNil = false
    for tick in 0..<30 {
        let out = f.apply([tick % 3 == 0 ? 0.6 : nil, nil, nil, nil], window: 3)
        if out[0] != nil { everNonNil = true }
    }
    check(!everNonNil, "spike every third tick is filtered out")
}

do { // a real obstacle drifting closer registers steadily
    var f = DistanceFilter()
    var out: [Float?] = []
    for d in [Float(1.8), 1.7, 1.6, 1.5, 1.4] { out = f.apply([nil, d, nil, nil], window: 3) }
    check(out[1] != nil && abs(out[1]! - 1.5) < 0.001, "approaching obstacle tracks the middle reading (got \(describe(out)))")
}

do { // zones are filtered independently, window 1 passes readings straight through, reset forgets
    var f = DistanceFilter()
    _ = f.apply([1.0, 2.0, nil, nil], window: 3)
    let out = f.apply([1.0, nil, nil, nil], window: 3)
    check(out[0] == 1.0 && out[1] == nil, "zones don't affect each other (got \(describe(out)))")
    var raw = DistanceFilter()
    check(raw.apply([0.7, nil, nil, nil], window: 1)[0] == 0.7, "window 1 is a pass-through")
    f.reset()
    check(f.apply([1.0, nil, nil, nil], window: 3)[0] == nil, "reset forgets history")
}

// MARK: - End to end: obstacle -> belt packet bytes

print("Wire packet")

do { // an obstacle on the left at 1 m becomes the exact bytes the ESP32 firmware will parse
    let leftHalf = Surface(axis: 2, value: -1, contains: { $0.x < 0 })
    let zones = DepthProcessor.zoneDistances(render([leftHalf], pose: cameraPose(position: eye)), tuning: tuning)
    let duties = zones.map { IntensityMapper.duty(forDistance: $0, tuning: tuning) }
    let packet = [UInt8](BeltCommand(zoneValues: duties).packet(seq: 7))
    check(packet.count == 6, "packet is 6 bytes (got \(packet.count))")
    check(packet[0] == 0xB7, "byte 0 is the magic 0xB7")
    check(packet[1] == 7, "byte 1 carries the sequence number")
    check(packet[2] > tuning.minFeltDuty && packet[2] == packet[3], "left hip / left pocket buzz equally (got \(packet))")
    check(packet[4] == 0 && packet[5] == 0, "right hip / right pocket are silent (got \(packet))")
    // Wire order is leftHip, leftPocket, rightPocket, rightHip: a right-only command must land in the last bytes.
    let rightOnly = [UInt8](BeltCommand(zoneValues: [0, 0, 111, 222]).packet(seq: 255))
    check(rightOnly == [0xB7, 255, 0, 0, 111, 222], "zone order on the wire (got \(rightOnly))")
}

// MARK: - Result

print(failures == 0 ? "\nAll \(checks) checks passed." : "\n\(failures) of \(checks) checks FAILED.")
exit(failures == 0 ? 0 : 1)
