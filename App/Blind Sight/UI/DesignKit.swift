//
//  DesignKit.swift
//  Blind Sight
//
//  Shared dark theme for the Wearer/Demo screens (UI/). Kept in one place so the three
//  mockup screens read as one consistent system rather than three ad-hoc styles.
//

import SwiftUI

extension Color {
    static let bsBackground = Color(red: 0.035, green: 0.04, blue: 0.07)
    static let bsCard = Color(red: 0.09, green: 0.10, blue: 0.16)
    static let bsCardBorder = Color.white.opacity(0.08)
    static let bsAccent = Color(red: 0.29, green: 0.55, blue: 1.0)
    /// Ring/bar color at zero urgency (clear) — also the depth grid's "far/clear" swatch.
    static let bsZoneIdle = Color(red: 0.14, green: 0.17, blue: 0.29)
    /// Ring/bar color at max urgency (255, obstacle at the near limit) — also the depth grid's "near" swatch.
    static let bsZoneNear = Color(red: 0.62, green: 0.80, blue: 1.0)
    /// The depth grid's "mid" swatch (between `tuning.nearMeters` and `tuning.farMeters`).
    static let bsZoneMid = Color(red: 0.22, green: 0.32, blue: 0.52)
    static let bsTextSecondary = Color.white.opacity(0.55)
    static let bsTextTertiary = Color.white.opacity(0.35)

    /// Interpolates the ring/bar color for a 0...255 urgency value (0 clear -> 255 solid/near).
    static func bsUrgency(_ urgency: UInt8) -> Color {
        let t = Double(urgency) / 255.0
        return Color(
            red: 0.14 + (0.62 - 0.14) * t,
            green: 0.17 + (0.80 - 0.17) * t,
            blue: 0.29 + (1.0 - 0.29) * t
        )
    }
}

/// The rounded, bordered dark card every panel in these screens sits on.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.bsCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.bsCardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func bsCard(padding: CGFloat = 14) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

/// Small uppercase, letter-spaced caption used for section/field labels ("BELT LINK", "NEAREST"...).
struct BSCaption: View {
    var text: String
    var color: Color = .bsTextSecondary

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

/// Wearer/Demo top-bar switcher, shared by every screen so switching modes always looks the same.
struct ModePill: View {
    @Binding var mode: AppMode

    var body: some View {
        HStack(spacing: 2) {
            option("Wearer", .wearer)
            option("Demo", .demo)
        }
        .padding(3)
        .background(Capsule().fill(Color.bsCard))
        .overlay(Capsule().stroke(Color.bsCardBorder, lineWidth: 1))
    }

    private func option(_ title: String, _ value: AppMode) -> some View {
        let isSelected = mode == value
        return Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? .white : .bsTextSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? Color.bsAccent : Color.clear)
            )
            .onTapGesture { mode = value }
    }
}

extension AppMode: Equatable {}

/// A single "LABEL / value" chip, e.g. "BELT LINK / Linked" — the small status cards along the
/// top of the demo screens.
struct StatusChip: View {
    var label: String
    var value: String
    var valueColor: Color = .white
    var dotColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BSCaption(text: label)
            HStack(spacing: 6) {
                if let dotColor {
                    Circle().fill(dotColor).frame(width: 7, height: 7)
                }
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(valueColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bsCard(padding: 12)
    }
}

/// Repeating diagonal lines, clipped to whatever shape it's drawn under — used for "out of sensor
/// range" (the ring's rear half) and "low confidence" (a depth-grid cell) rather than a color, so
/// those states read as structurally different from "measured and clear."
struct HatchPattern: View {
    var color: Color = Color.white.opacity(0.18)
    var spacing: CGFloat = 7
    var lineWidth: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let diagonal = size.width + size.height
            var x: CGFloat = -size.height
            while x < diagonal {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(color), lineWidth: lineWidth)
                x += spacing
            }
        }
    }
}

/// Pill-shaped secondary button used for "Test belt", "Depth overlay", "Belt ring", "Overlay: on".
struct BSButton: View {
    var title: String
    var isProminent: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isProminent ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isProminent ? Color.bsAccent : Color.bsCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isProminent ? Color.clear : Color.bsCardBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
