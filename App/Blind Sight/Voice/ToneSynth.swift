//
//  ToneSynth.swift
//  Blind Sight
//
//  Generates the short beep used as an audio cue, so the app needs no bundled sound file and
//  doesn't depend on undocumented system sound IDs (which also go silent on the ringer switch).
//

import Foundation

nonisolated enum ToneSynth {
    /// A sine beep as a complete 16-bit mono PCM WAV file. Each end fades over ~10 ms so it
    /// starts and stops without a click.
    static func beepWAV(frequency: Double = 880, duration: Double = 0.12,
                        amplitude: Double = 0.5, sampleRate: Int = 44_100) -> Data {
        let count = Int(duration * Double(sampleRate))
        let fade = max(1, min(count / 4, Int(0.010 * Double(sampleRate))))

        var samples = [Int16]()
        samples.reserveCapacity(count)
        for i in 0..<count {
            var envelope = 1.0
            if i < fade {
                envelope = Double(i) / Double(fade)
            } else if i >= count - fade {
                envelope = Double(count - 1 - i) / Double(fade)
            }
            let value = sin(2 * Double.pi * frequency * Double(i) / Double(sampleRate)) * amplitude * envelope
            samples.append(Int16(value * Double(Int16.max)))
        }

        var wav = Data()
        func text(_ string: String) { wav.append(contentsOf: Array(string.utf8)) }
        func uint32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        func uint16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }

        let dataBytes = count * 2
        text("RIFF"); uint32(UInt32(36 + dataBytes)); text("WAVE")
        text("fmt "); uint32(16); uint16(1) /* PCM */; uint16(1) /* mono */
        uint32(UInt32(sampleRate)); uint32(UInt32(sampleRate * 2)); uint16(2); uint16(16)
        text("data"); uint32(UInt32(dataBytes))
        for sample in samples { uint16(UInt16(bitPattern: sample)) }
        return wav
    }
}
