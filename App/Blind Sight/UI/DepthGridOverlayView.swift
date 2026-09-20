//
//  DepthGridOverlayView.swift
//  Blind Sight
//
//  Demo screen: live camera passthrough (ARCameraPreview) with a 5x3 nearest-distance grid drawn
//  on top, fed by DepthGridSampler — a loop that's entirely separate from BeltController's, so
//  switching the overlay off here never touches belt behavior.
//

import SwiftUI

struct DepthGridOverlayView: View {
    @ObservedObject var belt: BeltController
    @ObservedObject var sender: BeltUDPSender
    var onShowRing: () -> Void

    @StateObject private var sampler = DepthGridSampler()
    @State private var overlayOn = true

    private static let columnLabels = ["LEFT", "C-LEFT", "CENTER", "C-RIGHT", "RIGHT"]
    private static let zoneAngleLabels = ["-70°", "-20°", "20°", "70°"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topBar
                cameraSection
                columnLabelsRow
                nearestSection
                legend
                Text("Overlay is heavy on GPU. Turn it off during long runs; the belt keeps working either way.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.bsTextTertiary)
                HStack(spacing: 12) {
                    BSButton(title: "Test belt", isProminent: true) { belt.runSweepTest() }
                    BSButton(title: overlayOn ? "Overlay: on" : "Overlay: off") { toggleOverlay() }
                }
            }
            .padding(20)
        }
        .background(Color.bsBackground.ignoresSafeArea())
        .onAppear { if overlayOn { sampler.start() } }
        .onDisappear { sampler.stop() }
    }

    private func toggleOverlay() {
        overlayOn.toggle()
        if overlayOn { sampler.start() } else { sampler.stop() }
    }

    private var topBar: some View {
        HStack {
            Text("Depth view")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button(action: onShowRing) {
                Text("Belt ring")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.bsCard))
                    .overlay(Capsule().stroke(Color.bsCardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var cameraSection: some View {
        ZStack {
            ARCameraPreview()
            gridOverlay
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var gridOverlay: some View {
        VStack(spacing: 1) {
            ForEach(0..<DepthGridSampler.rows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<DepthGridSampler.columns, id: \.self) { column in
                        cellView(sampler.cells[row * DepthGridSampler.columns + column])
                    }
                }
            }
        }
    }

    private func cellView(_ cell: DepthProcessor.GridCell) -> some View {
        ZStack {
            Rectangle().fill(cellColor(cell))
            if cell.lowConfidenceOnly {
                HatchPattern(color: .white.opacity(0.3), spacing: 5)
            }
            Text(cellLabel(cell))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .overlay(Rectangle().stroke(Color.black.opacity(0.5), lineWidth: 0.5))
    }

    private func cellColor(_ cell: DepthProcessor.GridCell) -> Color {
        if cell.lowConfidenceOnly { return .bsZoneIdle }
        guard let distance = cell.distance else { return .bsZoneIdle.opacity(0.6) }
        return distance <= belt.tuning.nearMeters ? .bsZoneNear : .bsZoneMid
    }

    private func cellLabel(_ cell: DepthProcessor.GridCell) -> String {
        if cell.lowConfidenceOnly { return "low conf." }
        guard let distance = cell.distance else { return "\(Int(belt.tuning.farMeters))+ m" }
        return String(format: "%.1f m", distance)
    }

    private var columnLabelsRow: some View {
        HStack(spacing: 1) {
            ForEach(Self.columnLabels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.bsTextTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var nearest: (distance: Float, angleLabel: String)? {
        var best: (Float, String)?
        for (index, distance) in belt.distances.enumerated() {
            guard let distance else { continue }
            if best == nil || distance < best!.0 {
                best = (distance, Self.zoneAngleLabels[index])
            }
        }
        return best.map { (distance: $0.0, angleLabel: $0.1) }
    }

    private var nearestSection: some View {
        HStack(spacing: 16) {
            RingDiagram(urgencies: belt.urgencies, showLabels: false)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                BSCaption(text: "Nearest")
                if let nearest {
                    Text(String(format: "%.1f m", nearest.distance))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text("AT \(nearest.angleLabel)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.bsTextSecondary)
                } else {
                    Text("Clear")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            Spacer()
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 28) {
                legendItem(color: .bsZoneNear, label: "Near")
                legendItem(color: .bsZoneMid, label: "Mid")
            }
            HStack(spacing: 28) {
                legendItem(color: .bsZoneIdle, label: "Far")
                legendItem(color: .bsZoneIdle, label: "Low confidence", hatched: true)
            }
        }
    }

    private func legendItem(color: Color, label: String, hatched: Bool = false) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color)
                if hatched {
                    HatchPattern(color: .white.opacity(0.35), spacing: 4)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            .frame(width: 14, height: 14)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.bsTextSecondary)
        }
    }
}

#Preview {
    DepthGridOverlayView(belt: .shared, sender: BeltController.shared.sender, onShowRing: {})
}
