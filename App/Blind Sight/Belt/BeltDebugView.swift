//
//  BeltDebugView.swift
//  Blind Sight
//
//  Developer-facing screen for the belt loop: live per-zone readings, link status, on-device
//  tuning, and a manual mode for testing the belt with no depth at all. Not the wearer's UI.
//

import SwiftUI

struct BeltDebugView: View {
    @ObservedObject var belt: BeltController
    @ObservedObject private var sender: BeltUDPSender
    @EnvironmentObject private var arSession: ARSessionManager
    @State private var hostText = ""

    private static let zoneNames = ["Left hip", "Left pocket", "Right pocket", "Right hip"]

    init(belt: BeltController) {
        self.belt = belt
        self.sender = belt.sender
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sensingSection
                zonesSection
                linkSection
                tuningSection
                manualSection
            }
            .padding(.horizontal)
        }
        .onAppear { hostText = sender.host }
    }

    // MARK: Sections

    private var sensingSection: some View {
        section("Sensing") {
            Text(arSession.isRunning ? "ARKit running, tracking: \(String(describing: arSession.trackingState))" : "ARKit not running")
            Text(belt.depthStatus)
        }
    }

    private var zonesSection: some View {
        section("Zones (distance, buzz strength sent)") {
            ForEach(0..<DepthProcessor.zoneCount, id: \.self) { zone in
                HStack {
                    Text(Self.zoneNames[zone]).frame(width: 96, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(.tint)
                                .frame(width: geometry.size.width * CGFloat(belt.duties[zone]) / 255)
                        }
                    }
                    .frame(height: 14)
                    Text(distanceText(belt.distances[zone]))
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                    Text("\(belt.duties[zone])")
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    private var linkSection: some View {
        section("Belt link") {
            Text(sender.status)
            Text("\(sender.packetsSent) packets sent")
            HStack {
                TextField("ESP32 host", text: $hostText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                Button("Apply") { belt.setHost(hostText) }
                    .buttonStyle(.bordered)
            }
            Text("Default \(AppConfig.esp32Host). To test without the belt, point this at a Mac running tools/belt_packet_listener.py.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var tuningSection: some View {
        section("Tuning") {
            slider("Full buzz at", value: floatBinding(\.nearMeters), range: 0.25...2, unit: "m", format: "%.2f")
            slider("Silent beyond", value: floatBinding(\.farMeters), range: 1...4, unit: "m", format: "%.2f")
            slider("Phone height above floor", value: floatBinding(\.cameraHeightMeters), range: 0.8...1.6, unit: "m", format: "%.2f")
            slider("Ignore above phone", value: floatBinding(\.overheadClearanceMeters), range: 0.3...1.2, unit: "m", format: "%.2f")
            Picker("Noise filter", selection: Binding(
                get: { belt.tuning.distanceWindow },
                set: { belt.tuning.distanceWindow = $0 }
            )) {
                Text("Off").tag(1)
                Text("3 readings").tag(3)
                Text("5 readings").tag(5)
            }
            .pickerStyle(.segmented)
            slider("Weakest felt buzz", value: Binding(
                get: { Double(belt.tuning.minFeltDuty) },
                set: { belt.tuning.minFeltDuty = UInt8($0) }
            ), range: 0...200, unit: "", format: "%.0f")
        }
    }

    private var manualSection: some View {
        section("Manual / test") {
            Toggle("Send these values, ignore depth", isOn: Binding(
                get: { belt.manualDuties != nil },
                set: { belt.manualDuties = $0 ? [0, 0, 0, 0] : nil }
            ))
            if belt.manualDuties != nil {
                ForEach(0..<DepthProcessor.zoneCount, id: \.self) { zone in
                    slider(Self.zoneNames[zone], value: Binding(
                        get: { Double(belt.manualDuties?[zone] ?? 0) },
                        set: {
                            var values = belt.manualDuties ?? [0, 0, 0, 0]
                            values[zone] = UInt8($0)
                            belt.manualDuties = values
                        }
                    ), range: 0...255, unit: "", format: "%.0f")
                }
            }
            Button("Sweep test (each motor 0 to full)") { belt.runSweepTest() }
                .buttonStyle(.bordered)
        }
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .font(.callout)
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label): \(String(format: format, value.wrappedValue)) \(unit)")
            Slider(value: value, in: range)
        }
    }

    private func floatBinding(_ keyPath: WritableKeyPath<BeltTuning, Float>) -> Binding<Double> {
        Binding(
            get: { Double(belt.tuning[keyPath: keyPath]) },
            set: { belt.tuning[keyPath: keyPath] = Float($0) }
        )
    }

    private func distanceText(_ distance: Float?) -> String {
        distance.map { String(format: "%.2f m", $0) } ?? "clear"
    }
}
