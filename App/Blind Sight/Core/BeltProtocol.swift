//
//  BeltProtocol.swift
//  Blind Sight
//
//  Wire format for phone -> ESP32 belt commands over UDP (AppConfig.esp32Host:esp32Port).
//  This is the one thing the app's sender and the ESP32 firmware must agree on byte-for-byte.
//

import Foundation

/// `[magic][seq][z0][z1][z2][z3]`, 6 bytes.
///
/// - `magic` (0xB7): constant tag so the ESP32 ignores stray/garbage UDP traffic on the port.
/// - `seq` (u8, wraps 0-255): increments every packet. The ESP32 should only apply a packet
///   whose seq is newer than the last one it applied — belt updates arrive a few times a
///   second and UDP doesn't guarantee order, so this stops a delayed/reordered packet from
///   overwriting newer belt state with stale data. Compare with wraparound in mind:
///   `(int8_t)(seq - lastAppliedSeq) > 0`, not a plain `>`. This is NOT a reliability/retry
///   mechanism — per the PRD, a dropped packet is simply superseded by the next update.
/// - `z0...z3`: urgency 0-255 per `BeltZone` (0 off, 1-254 pulse rate, 255 solid), in wire order (leftHip, leftPocket,
///   rightPocket, rightHip) — see `BeltCommand.orderedBytes`.
enum BeltProtocol {
    static let magic: UInt8 = 0xB7
    static let packetSize = 6
}

extension BeltCommand {
    /// Encodes this command as the 6-byte wire packet for the given sequence number.
    func packet(seq: UInt8) -> Data {
        Data([BeltProtocol.magic, seq] + orderedBytes)
    }
}

/// Hands out wrapping sequence numbers for outgoing belt packets. One instance per sender
/// (the belt UDP transport owns it) — not shared across threads.
final class BeltSequenceCounter {
    private var value: UInt8 = 0

    func next() -> UInt8 {
        defer { value = value &+ 1 }
        return value
    }
}
