import IsleCore
import SwiftUI

struct IslandView: View {
    @Environment(IslandModel.self) private var model
    /// The system's scheme, read before this view sets its own.
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let size = model.islandSize
        let open = model.mode == .open
        let closed = model.mode == .closed
        // The closed island is black in every theme, so it still hides in the notch.
        let glass = model.theme.isGlass && !closed
        let shape = NotchShape(top: open ? 10 : 6, bottom: open ? 24 : closed ? 10 : 16)
        ZStack(alignment: .top) {
            if glass { GlassFill(shape: shape).transition(.opacity) }
            // 1 % on glass, not 0. The window server sends a click on a fully transparent pixel to the
            // window below, and Liquid Glass leaves the island's own pixels transparent.
            Color.black.opacity(glass ? 0.01 : 1)
            content
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        // The whole island takes clicks. On glass the fill is clear, so without this a click on an
        // empty spot hit nothing and the island did not open.
        .contentShape(shape)
        .shadow(color: .black.opacity(open && !glass ? 0.5 : 0), radius: 18, y: 8)
        // A tap opens the island. Buttons inside (the alert's Done and Snooze) win over it.
        // When open, only the controls inside take taps.
        .gesture(TapGesture().onEnded { model.tap() }, including: open ? .subviews : .all)
        .contextMenu { IslandMenu() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, scheme)
        .tint(.isleOrange)
        .animation(.island, value: size)
        // The hidden harness panel never runs animations, so a transition would never end and leave views
        // half inserted or half removed. A test run applies every change at once.
        .transaction { if model.isolated { $0.disablesAnimations = true } }
    }

    /// Standard is black, so dark. Glass follows its look setting. The closed island sets dark itself,
    /// so the content that fades out on a close keeps its scheme.
    private var scheme: ColorScheme {
        guard model.theme.isGlass else { return .dark }
        switch model.glassLook {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .closed: ClosedView().environment(\.colorScheme, .dark).transition(.opacity)
        case .peek: PeekView().transition(.blurReplace)
        case .open: OpenView().transition(.blurReplace)
        case .alert: AlertView().transition(.blurReplace)
        case .morning: MorningView().transition(.blurReplace)
        }
    }
}

/// The wings beside the notch: today's progress and what comes next.
struct ClosedView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        if model.showsWings {
            HStack(spacing: 0) {
                ProgressRing(progress: model.progress)
                    .frame(width: 14, height: 14)
                    .frame(width: IslandModel.wing)
                Color.clear.frame(width: model.notch.width)
                NextLabel(compact: true).frame(width: IslandModel.wing)
            }
            .frame(height: model.notch.height)
        }
    }
}

/// Minutes to the next timed task, its time, a check when all is done, or the open count.
struct NextLabel: View {
    @Environment(IslandModel.self) private var model
    let compact: Bool

    var body: some View {
        let p = model.progress
        if let next = model.next, let m = next.minute {
            let left = m - Day.minute(of: model.now)
            Text(left == 0 ? "now" : left <= 60 ? "\(left)m" : Format.time(m, compact: compact))
                .font(.digits(compact ? 11 : 12))
                .foregroundStyle(Color.isleOrange)
        } else if p.total > 0 && p.done == p.total {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.isleGreen)
        } else if p.total > 0 {
            Text("\(p.total - p.done)")
                .font(.digits(compact ? 11 : 12))
                .foregroundStyle(Color.ink.opacity(0.7))
        }
    }
}

struct PeekView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let p = model.progress
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ProgressRing(progress: p).frame(width: 14, height: 14)
                Text("\(p.done)/\(p.total)")
                    .font(.digits(11))
                    .foregroundStyle(Color.ink.opacity(0.55))
                Spacer(minLength: model.notch.width)
                NextLabel(compact: false)
            }
            .padding(.horizontal, 20)
            .frame(height: model.notch.height)
            Text(line(p))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.ink.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 24)
                .frame(height: 26)
        }
    }

    private func line(_ p: DayProgress) -> String {
        if let next = model.next { return next.title }
        if p.total == 0 { return "Nothing today. Click to plan." }
        if p.done == p.total { return "All done for today" }
        return "\(p.total - p.done) left today"
    }
}

/// Shown at a task's time.
struct AlertView: View {
    @Environment(IslandModel.self) private var model
    @State private var ring = false

    var body: some View {
        if let todo = model.alertTodo {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.isleOrange)
                        .rotationEffect(.degrees(ring ? 14 : -14), anchor: .top)
                        .animation(.easeInOut(duration: 0.12).repeatCount(9, autoreverses: true), value: ring)
                    Spacer(minLength: model.notch.width)
                    Text(Format.time(todo.minute ?? 0))
                        .font(.digits(12))
                        .foregroundStyle(Color.isleOrange)
                }
                .padding(.horizontal, 20)
                .frame(height: model.notch.height)
                HStack(spacing: 8) {
                    Text(todo.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Snooze 10m") { model.snooze(todo) }
                        .buttonStyle(PillButton(fill: Color.ink.opacity(0.14), text: .ink))
                    Button("Done") { model.alertDone(todo) }
                        .buttonStyle(PillButton(fill: .isleGreen, text: .black))
                }
                .padding(.horizontal, 20)
                .frame(height: 50)
            }
            .onAppear { ring = true }
        }
    }
}

/// Once a day: asks the user to plan the day. A click anywhere but Later opens the plan page.
struct MorningView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.isleOrange)
                Spacer(minLength: model.notch.width)
                Text(model.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .frame(height: model.notch.height)
            HStack(spacing: 8) {
                Text("\(Morning.greeting(model.now)). Plan your \(model.now.formatted(.dateTime.weekday(.wide)))?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Later") { model.close() }
                    .buttonStyle(PillButton(fill: Color.ink.opacity(0.14), text: .ink))
                Button("Plan") { model.openPlan() }
                    .buttonStyle(PillButton(fill: .isleGreen, text: .black))
            }
            .padding(.horizontal, 20)
            .frame(height: 50)
        }
    }
}

struct IslandMenu: View {
    var body: some View {
        Text("Open or close: ⌃⌥T")
        Text("New note: ⌃⌥N")
        Toggle("Launch at Login", isOn: Binding(get: { LaunchAtLogin.isOn }, set: { LaunchAtLogin.set($0) }))
        Button("Show Data File") { NSWorkspace.shared.activateFileViewerSelecting([TodoStore.defaultURL]) }
        Divider()
        Button("Quit Isle") { NSApp.terminate(nil) }
    }
}
