import Carbon.HIToolbox
import IsleCore
import SwiftUI

/// The plan page: write the day, one task on each line, then add all of them at once.
struct PlanView: View {
    @Environment(IslandModel.self) private var model
    @FocusState private var focused: Int?
    @State private var contentHeight: CGFloat = 0
    @State private var keyMonitor: Any?
    private let maxHeight: CGFloat = 300

    var body: some View {
        let count = model.planned.count
        VStack(alignment: .leading, spacing: 8) {
            Text("What do you want to get done today?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink.opacity(0.9))
                .padding(.leading, 10)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.planLines.indices, id: \.self) { i in
                            PlanLineRow(index: i, focused: $focused).id(i)
                        }
                        AlreadyOnToday()
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .frame(height: min(contentHeight, maxHeight))
                .scrollDisabled(contentHeight <= maxHeight)
                .onChange(of: focused) { _, line in
                    if let line { withAnimation(.snappy) { proxy.scrollTo(line) } }
                }
            }
            footer(count)
        }
        .onAppear {
            // The last line, so a draft from earlier goes on where it stopped.
            DispatchQueue.main.async { focused = model.planLines.count - 1 }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: lineKey)
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        }
    }

    /// ↑ and ↓ move between lines. Delete on an empty line removes it. The field's own text editor
    /// takes these keys before SwiftUI's `onKeyPress` sees them, so the page watches them while it shows.
    private func lineKey(_ event: NSEvent) -> NSEvent? {
        guard let line = focused, event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]) else {
            return event
        }
        let target: Int?
        switch Int(event.keyCode) {
        case kVK_UpArrow: target = line - 1
        case kVK_DownArrow: target = line + 1
        case kVK_Delete: target = model.removePlanLine(line)  // nil unless the line is empty
        default: return event
        }
        guard let target, model.planLines.indices.contains(target) else { return event }
        focused = target
        return nil
    }

    private func footer(_ count: Int) -> some View {
        HStack {
            Text(count == 0 ? "Write one task on each line" : "\(count) new \(count == 1 ? "task" : "tasks") · Return for a new line")
                .font(.system(size: 11))
                .foregroundStyle(Color.ink.opacity(0.45))
            Spacer()
            Button { model.commitPlan() } label: {
                HStack(spacing: 6) {
                    Text(count == 0 ? "Add" : "Add \(count)")
                    Text("⌘↩").opacity(0.6)
                }
            }
            .buttonStyle(PillButton(fill: .isleGreen, text: .black))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(count == 0)
            .opacity(count == 0 ? 0.4 : 1)
        }
        .padding(.horizontal, 10)
    }
}

/// One line of the plan, drawn like the task it will become.
private struct PlanLineRow: View {
    @Environment(IslandModel.self) private var model
    let index: Int
    var focused: FocusState<Int?>.Binding

    /// Read when called, not when the row drew: on Return the field reads its binding once more, and a
    /// captured value can be stale, which wiped the line. A row can also outlive its line for one frame.
    private var text: String { model.planLines.indices.contains(index) ? model.planLines[index] : "" }

    var body: some View {
        let task = QuickParse.planLines([text], now: model.now).first
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(Color.ink.opacity(0.25), lineWidth: 1.5)
                .frame(width: 18, height: 18)
            TextField("", text: Binding(get: { text }, set: { write($0) }),
                      prompt: index == 0 ? Text("One task on each line — try “call mom 6pm”").foregroundColor(Color.ink.opacity(0.3)) : nil)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Color.ink.opacity(0.92))
                .focused(focused, equals: index)
                .onSubmit { focused.wrappedValue = model.insertPlanLine(after: index) ?? index }
            if let task {
                WhenChip(day: task.day, minute: task.minute, now: model.now)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    /// A paste with line breaks fills the lines below, and the keyboard follows it.
    private func write(_ text: String) {
        let last = model.setPlanLine(index, text)
        if last != index { focused.wrappedValue = last }
    }
}

/// The open tasks already on Today, so the user does not write them again.
/// Collapsed, the titles still show on one line, so a user on the keyboard reads them too.
private struct AlreadyOnToday: View {
    @Environment(IslandModel.self) private var model
    @State private var expanded = false

    var body: some View {
        let s = model.sections
        let open = s.overdue + s.timed + s.anytime
        if !open.isEmpty {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Text("ALREADY ON TODAY (\(open.count))")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    if !expanded {
                        Text(open.map(\.title).joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ink.opacity(0.45))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.ink.opacity(0.35))
                .padding(.leading, 10)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(open) { todo in
                    TaskRow(todo: todo, meta: (todo.day ?? "") < model.today ? .day : .time)
                }
            }
        }
    }
}
