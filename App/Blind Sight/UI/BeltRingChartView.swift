//
//  BeltRingChartView.swift
//  Blind Sight
//
//  The belt's 4 real zones (Core/Models.swift's BeltZone, left hip -> right hip) drawn as a ring
//  across the front semicircle, with the rear semicircle hatched "out of sensor range" — there is
//  only one forward-facing LiDAR, so the belt (and this diagram) never has anything to say about
//  what's behind the wearer. Deliberately 4 real wedges, not a fabricated 8-direction compass.
//

import SwiftUI

/// One annulus segment, built from scratch (not Path.addArc) so the angle convention is exactly
/// "degrees clockwise from straight up" everywhere in this file, matching how a wearer would
/// describe a bearing ("30 degrees to my right").
private struct RingWedge: Shape {
    var startDegrees: Double
    var endDegrees: Double
    /// Inner radius as a fraction of the outer radius (the ring's center hole).
    var innerFraction: CGFloat

    private func point(_ degrees: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * sin(radians), y: center.y - radius * cos(radians))
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerFraction
        let segments = 16
        let step = (endDegrees - startDegrees) / Double(segments)

        var path = Path()
        path.move(to: point(startDegrees, radius: outer, center: center))
        for i in 1...segments {
            path.addLine(to: point(startDegrees + step * Double(i), radius: outer, center: center))
        }
        for i in 0...segments {
            path.addLine(to: point(endDegrees - step * Double(i), radius: inner, center: center))
        }
        path.closeSubpath()
        return path
    }
}

/// The ring alone (no bar chart) — used full-size in the demo ring screen and shrunk down next to
/// "NEAREST" in the depth-view screen.
struct RingDiagram: View {
    /// 4 values in BeltZone order (leftHip, leftPocket, rightPocket, rightHip).
    var urgencies: [UInt8]
    var showLabels: Bool = true

    /// Wedge angle span and the real BeltZone bearing each one represents (Core/Models.swift).
    private static let wedges: [(range: ClosedRange<Double>, label: String)] = [
        (-90 ... -45, "-70°"),
        (-45 ... 0, "-20°"),
        (0 ... 45, "20°"),
        (45 ... 90, "70°")
    ]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                // Rear: hatched, always "out of sensor range" — there's no data that could ever fill it in.
                RingWedge(startDegrees: 90, endDegrees: 270, innerFraction: 0.4)
                    .fill(Color.bsZoneIdle)
                HatchPattern(color: .white.opacity(0.16))
                    .clipShape(RingWedge(startDegrees: 90, endDegrees: 270, innerFraction: 0.4))

                // Front: the 4 real zones.
                ForEach(Array(Self.wedges.enumerated()), id: \.offset) { index, wedge in
                    RingWedge(startDegrees: wedge.range.lowerBound, endDegrees: wedge.range.upperBound, innerFraction: 0.4)
                        .fill(Color.bsUrgency(urgencies[safe: index] ?? 0))
                        .overlay(
                            RingWedge(startDegrees: wedge.range.lowerBound, endDegrees: wedge.range.upperBound, innerFraction: 0.4)
                                .stroke(Color.bsBackground, lineWidth: 1.5)
                        )
                }

                Circle()
                    .fill(Color.bsBackground)
                    .frame(width: side * 0.4 * 2 - 4, height: side * 0.4 * 2 - 4)
                    .position(center)
                    .allowsHitTesting(false)

                if showLabels {
                    Text("FRONT")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Color.bsTextSecondary)
                        .position(x: center.x, y: center.y - side / 2 - 10)

                    ForEach(Array(Self.wedges.enumerated()), id: \.offset) { index, wedge in
                        let mid = (wedge.range.lowerBound + wedge.range.upperBound) / 2
                        Text(wedge.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.bsTextTertiary)
                            .position(labelPosition(degrees: mid, radius: side / 2 + 14, center: center))
                    }
                }
            }
        }
    }

    private func labelPosition(degrees: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * sin(radians), y: center.y - radius * cos(radians))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Ring + the matching 4-bar chart underneath, for the demo ring screen.
struct BeltRingChartView: View {
    var urgencies: [UInt8]

    private static let labels = ["-70°", "-20°", "20°", "70°"]

    var body: some View {
        VStack(spacing: 20) {
            RingDiagram(urgencies: urgencies)
                .frame(width: 260, height: 260)

            Text("REAR: OUT OF SENSOR RANGE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.bsTextTertiary)

            HStack(alignment: .bottom, spacing: 18) {
                ForEach(0..<4, id: \.self) { index in
                    let urgency = urgencies[safe: index] ?? 0
                    VStack(spacing: 6) {
                        Text("\(urgency)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.bsTextSecondary)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.bsUrgency(urgency))
                            .frame(width: 22, height: max(4, CGFloat(urgency) / 255 * 60))
                        Text(Self.labels[index])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.bsTextTertiary)
                    }
                }
            }
        }
    }
}
