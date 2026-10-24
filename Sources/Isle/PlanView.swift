import IsleCore
import SwiftUI

/// The plan page: write the day, one task on each line, then add all of them at once.
struct PlanView: View {
    @Environment(IslandModel.self) private var model
    /// The line that takes the keyboard next. A new id asks again, even for the same line.
    @State private var focusRequest = FocusRequest(line: 0)
    @State private var contentHeight: CGFloat = 0
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
                            PlanLineRow(index: i, focusRequest: focusRequest, focus: focus, command: command).id(i)
                        }
                        AlreadyOnToday()
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .frame(height: min(contentHeight, maxHeight))
                .scrollDisabled(contentHeight <= maxHeight)
                .onChange(of: focusRequest) { _, request in
                    withAnimation(.snappy) { proxy.scrollTo(request.line) }
                }
            }
            footer(count)
        }
        // The last line, so a draft from earlier goes on where it stopped.
        .onAppear { focus(model.planLines.count - 1) }
    }

    private func focus(_ line: Int) {
        focusRequest = FocusRequest(line: line, id: focusRequest.id + 1)
    }

    /// Return, ↑, ↓, and Delete inside line `i`. False lets the field do its own thing.
    private func command(_ i: Int, _ command: PlanLineField.Command) -> Bool {
        switch command {
        case .newline:
            // Return never ends the line. On an empty line or a full plan it does nothing.
            if let next = model.insertPlanLine(after: i) { focus(next) }  // the new field asks once it exists
            return true
        case .up, .down:
            let target = command == .up ? i - 1 : i + 1
            guard model.planLines.indices.contains(target) else { return false }
            PlanLineField.focus(target, in: model.panel)
            focus(target)
            return true
        case .deleteBackward:
            // A held Delete stops at the start of a line, so it cannot run on through the whole plan.
            // (`isARepeat` raises on an event that is not a key event, so check the type first.)
            let held = NSApp.currentEvent.map { $0.type == .keyDown && $0.isARepeat } ?? false
            guard !held, i > 0, model.planLines.indices.contains(i), model.planLines[i].isEmpty else { return false }
            // The keyboard leaves first: a field removed while it edits leaves the window with none.
            PlanLineField.focus(i - 1, in: model.panel)
            _ = model.removePlanLine(i)
            focus(i - 1)
            return true
        }
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

struct FocusRequest: Equatable {
    var line: Int
    var id = 0
}

/// One line of the plan, drawn like the task it will become.
private struct PlanLineRow: View {
    @Environment(IslandModel.self) private var model
    let index: Int
    let focusRequest: FocusRequest
    let focus: (Int) -> Void
    let command: (Int, PlanLineField.Command) -> Bool

    /// Read when called, not when the row drew: a captured value can be stale when the field writes
    /// back, which wiped the line. A row can also outlive its line for one frame after a delete.
    private var text: String { model.planLines.indices.contains(index) ? model.planLines[index] : "" }

    var body: some View {
        let task = QuickParse.planLines([text], now: model.now).first
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(Color.ink.opacity(0.25), lineWidth: 1.5)
                .frame(width: 18, height: 18)
            PlanLineField(text: Binding(get: { text }, set: { write($0) }),
                          placeholder: index == 0 ? "One task on each line — try “call mom 6pm”" : nil,
                          line: index,
                          focusID: focusRequest.line == index ? focusRequest.id : nil,
                          command: { command(index, $0) })
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
        if last != index { focus(last) }
    }
}

/// A plan line as an AppKit text field. SwiftUI's `TextField` on macOS 14 cannot place the caret, so
/// focus from code selected the whole line and the next key replaced it. Its text editor also takes
/// ↑, ↓, and Delete before `onKeyPress` sees them. This field's delegate gets them as commands, after
/// an input method has had its turn.
struct PlanLineField: NSViewRepresentable {
    enum Command { case newline, up, down, deleteBackward }

    @Binding var text: String
    let placeholder: String?
    let line: Int
    /// Set on the line that should take the keyboard. A new value asks again.
    let focusID: Int?
    let command: (Command) -> Bool
    @Environment(\.colorScheme) private var scheme

    func makeNSView(context: Context) -> CaretAtEndField {
        let field = CaretAtEndField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: CaretAtEndField, context: Context) {
        context.coordinator.parent = self
        // The island sets its own scheme, and the dynamic ink color resolves against this appearance.
        field.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        field.textColor = NSColor(Color.ink).withAlphaComponent(0.92)
        field.placeholderAttributedString = placeholder.map {
            NSAttributedString(string: $0, attributes: [.foregroundColor: NSColor(Color.ink).withAlphaComponent(0.3),
                                                        .font: NSFont.systemFont(ofSize: 13)])
        }
        field.setAccessibilityLabel("Plan line \(line + 1)")
        field.tag = CaretAtEndField.tagBase + line
        if field.stringValue != text { field.stringValue = text }
        if let focusID, focusID != context.coordinator.appliedFocus {
            context.coordinator.appliedFocus = focusID
            field.wantsFocus = true
            DispatchQueue.main.async { field.takeFocusIfWanted() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// Moves the keyboard to a line that is on screen now, without waiting for a redraw.
    static func focus(_ line: Int, in window: NSWindow?) {
        guard let window, let field = window.contentView?.viewWithTag(CaretAtEndField.tagBase + line) else { return }
        window.makeFirstResponder(field)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PlanLineField
        var appliedFocus: Int?

        init(parent: PlanLineField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }  // an input method's keys stay its own
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): return parent.command(.newline)
            case #selector(NSResponder.moveUp(_:)): return parent.command(.up)
            case #selector(NSResponder.moveDown(_:)): return parent.command(.down)
            case #selector(NSResponder.deleteBackward(_:)): return parent.command(.deleteBackward)
            default: return false
            }
        }
    }
}

/// AppKit selects all of a field's text when it takes focus. A plan line puts the caret at the end.
/// A click still moves the caret to where the user clicked, after this.
final class CaretAtEndField: NSTextField {
    /// Plan line `n` has the tag `tagBase + n`, so the page finds a line's field at once.
    static let tagBase = 7_000
    /// A focus request that waits until SwiftUI has put the field in a window.
    var wantsFocus = false

    func takeFocusIfWanted() {
        guard wantsFocus, let window else { return }
        if window.makeFirstResponder(self) { wantsFocus = false }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        takeFocusIfWanted()
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        currentEditor()?.selectedRange = NSRange(location: (stringValue as NSString).length, length: 0)
        return true
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
