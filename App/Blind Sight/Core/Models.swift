//
//  Models.swift
//  Blind Sight
//
//  Shared data contract between the belt-processing loop (Belt/) and the ESP32 transport.
//

import Foundation

/// The 4 front-facing belt zones, left to right (PRD "Belt (ESP32)" zone layout).
enum BeltZone: Int, CaseIterable {
    case leftHip = 0     // -70°
    case leftPocket = 1  // -20°
    case rightPocket = 2 // +20°
    case rightHip = 3    // +70°
}

/// One update cycle's belt intensities. Mirrors the ESP32 packet shape from the PRD:
/// `{ zones: [z0, z1, z2, z3] }`, each a 0–255 urgency (0 off, 1–254 pulse faster, 255 solid), left hip → right hip.
struct BeltCommand {
    var intensities: [BeltZone: UInt8]

    static let allOff = BeltCommand(
        intensities: Dictionary(uniqueKeysWithValues: BeltZone.allCases.map { ($0, 0) })
    )

    /// Packed in wire order for the UDP packet to the ESP32.
    var orderedBytes: [UInt8] {
        BeltZone.allCases.map { intensities[$0] ?? 0 }
    }
}
