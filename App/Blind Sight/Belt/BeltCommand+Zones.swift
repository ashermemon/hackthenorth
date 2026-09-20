//
//  BeltCommand+Zones.swift
//  Blind Sight
//

import Foundation

extension BeltCommand {
    /// Builds a command from four urgency values in wire order (leftHip, leftPocket, rightPocket, rightHip).
    init(zoneValues: [UInt8]) {
        self.init(intensities: Dictionary(uniqueKeysWithValues: zip(BeltZone.allCases, zoneValues)))
    }
}
