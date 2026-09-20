//
//  BeltController.swift
//  Blind Sight
//
//  Sensing & belt control loop owner: build out this file (and others under Belt/).
//

import Foundation

/// Owns the depth → belt zone/intensity loop (PRD "Processing" → "Depth → belt zone/intensity"):
/// reads `ARSessionManager.shared.latestFrame` for `sceneDepth`, computes a `BeltCommand`
/// a few times per second (`AppConfig.beltUpdateHz`), and sends it to the ESP32 over UDP at
/// `AppConfig.esp32Host:esp32Port`. Must never block on the voice pipeline.
final class BeltController {
    // TODO(belt): downsample depth → per-zone nearest reading → intensity, then transmit.
}
