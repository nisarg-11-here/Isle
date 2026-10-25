import IsleCore
import SwiftUI

extension Color {
    static let isleGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
    /// The dark value is the original. On light glass a darker orange keeps times legible (about 4:1).
    static let isleOrange = Color(nsColor: NSColor(name: nil) {
        $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)
            : NSColor(srgbRed: 0.78, green: 0.40, blue: 0, alpha: 1)
    })
    static let isleRed = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let islePurple = Color(red: 0.75, green: 0.35, blue: 0.95)
    static let isleBlue = Color(red: 0.25, green: 0.6, blue: 1.0)
    /// The Notes color. On light glass a darker yellow keeps it legible.
    static let isleYellow = Color(nsColor: NSColor(name: nil) {
        $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0.84, blue: 0.04, alpha: 1)
            : NSColor(srgbRed: 0.66, green: 0.50, blue: 0, alpha: 1)
    })
}

extension Color {
    /// White in the dark scheme, black in the light one. Standard is always dark, so it keeps its exact whites.
    /// (`Color.primary` is the label color at 85 % opacity, so it would dim Standard.)
    static let ink = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black })
    /// The opposite of ink: text on an ink-filled chip or button.
    static let inkInverse = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white })
}

extension Animation {
    static let island = Animation.spring(response: 0.42, dampingFraction: 0.8)
}

extension Font {
    /// Rounded, with fixed-width digits, for times and counts.
    static func digits(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// The island outline: concave shoulders that blend into the top edge, round bottom corners.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set {
            top = newValue.first
            bottom = newValue.second
        }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + bottom, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - bottom), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Liquid Glass in the island shape (Apple: apply `glassEffect` after other appearance modifiers).
/// The Glass theme exists only on macOS 26 (`IslandTheme.isGlass`), so the else branch never draws.
struct GlassFill<S: Shape>: View {
    let shape: S

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        }
    }
}

struct ProgressRing: View {
    let progress: DayProgress
    var lineWidth: CGFloat = 2.5

    var body: some View {
        let f = progress.total == 0 ? 0 : CGFloat(progress.done) / CGFloat(progress.total)
        ZStack {
            Circle().stroke(Color.ink.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: f)
                .stroke(Color.isleGreen, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.island, value: f)
    }
}

struct CheckCircle: View {
    let done: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(Color.ink.opacity(done ? 0 : 0.35), lineWidth: 1.5)
                Circle().fill(Color.isleGreen).scaleEffect(done ? 1 : 0.01)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.black)
                    .scaleEffect(done ? 1 : 0.4)
                    .opacity(done ? 1 : 0)
            }
            .frame(width: 18, height: 18)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: done)
    }
}

struct Chip: View {
    let label: String
    let on: Bool
    let action: () -> Void

    init(_ label: String, on: Bool, action: @escaping () -> Void) {
        self.label = label
        self.on = on
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Color.inkInverse : Color.ink.opacity(0.75))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(on ? Color.ink : Color.ink.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct IconButton: View {
    let icon: String
    let help: String
    var tint: Color = .ink
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint.opacity(hover ? 1 : 0.6))
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.ink.opacity(hover ? 0.1 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
    }
}

/// "‹ Settings" or "‹ Plan" in the header, in place of the tabs.
struct BackButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.ink.opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PillButton: ButtonStyle {
    let fill: Color
    let text: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(fill))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy, value: configuration.isPressed)
    }
}
