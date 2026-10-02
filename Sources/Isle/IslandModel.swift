import AppKit
import IsleCore
import SwiftUI

enum Mode: Equatable {
    case closed, peek, open, alert(UUID)
}

/// A short message with an undo action at the bottom of the open island.
struct Toast: Equatable {
    let id = UUID()
    let text: String
}

/// UI state for the island. The views read it. The panel sizes itself from `windowSize`.
@Observable
final class IslandModel {
    let store: TodoStore
    private(set) var mode: Mode = .closed
    var bucket: Bucket = .today
    private(set) var now = Date()
    var notch = CGSize(width: 185, height: 32)
    var openHeight: CGFloat = 120
    var draft = ""
    var editing: UUID?
    var scheduling: UUID?
    private(set) var toast: Toast?
    /// Goes up by one each time the add field must take focus.
    private(set) var focusRequest = 0

    @ObservationIgnored weak var panel: NSPanel?
    @ObservationIgnored private var hovering = false
    @ObservationIgnored private var pending: DispatchWorkItem?
    @ObservationIgnored private var toastWork: DispatchWorkItem?
    @ObservationIgnored private var undoAction: (() -> Void)?
    @ObservationIgnored private var alerted = Set<UUID>()
    @ObservationIgnored private var previousApp: NSRunningApplication?

    static let wing: CGFloat = 44
    static let openMaxHeight: CGFloat = 480

    init(store: TodoStore) {
        self.store = store
    }

    // MARK: Derived state

    var today: String { Day.key(now) }
    var sections: TodaySections { store.todos.todaySections(now) }
    var progress: DayProgress { store.todos.progress(now) }
    var next: Todo? { store.todos.nextTimed(now) }
    var plan: Parsed { QuickParse.plan(draft, bucket: bucket, now: now) }

    var alertTodo: Todo? {
        guard case .alert(let id) = mode else { return nil }
        return store.todos.first { $0.id == id }
    }

    var islandSize: CGSize {
        switch mode {
        case .closed:
            CGSize(width: notch.width + 12 + (progress.total > 0 ? 2 * Self.wing : 0), height: notch.height)
        case .peek:
            CGSize(width: notch.width + 200, height: notch.height + 30)
        case .open:
            CGSize(width: notch.width + 460, height: min(openHeight, Self.openMaxHeight))
        case .alert:
            CGSize(width: max(notch.width + 260, 440), height: notch.height + 54)
        }
    }

    /// The panel leaves room for the shadow when open.
    var windowSize: CGSize {
        let s = islandSize
        return mode == .open ? CGSize(width: s.width + 60, height: s.height + 40) : s
    }

    // MARK: Island

    func hover(_ inside: Bool) {
        hovering = inside
        switch (inside, mode) {
        case (true, .closed):
            after(0.1) { [weak self] in
                guard let self, hovering, mode == .closed else { return }
                set(.peek)
                haptic()
            }
        case (true, _):
            pending?.cancel()  // keep an open island or an alert while the pointer is on it
        case (false, .peek):
            set(.closed)
        case (false, .open) where draft.isEmpty && editing == nil && scheduling == nil:
            after(0.7) { [weak self] in
                guard let self, !hovering else { return }
                set(.closed)
            }
        case (false, .alert):
            after(4) { [weak self] in self?.set(.closed) }
        default:
            break
        }
    }

    func tap() {
        if mode != .open { open() }
    }

    func open() {
        if case .alert = mode { bucket = .today }
        set(.open)
    }

    func close() { set(.closed) }

    func hotKey() { mode == .open ? close() : open() }

    func escape() {
        if editing != nil {
            editing = nil
        } else if scheduling != nil {
            withAnimation(.snappy) { scheduling = nil }
        } else if !draft.isEmpty {
            draft = ""
        } else {
            close()
        }
    }

    /// The user clicked outside the island.
    func resignedKey() {
        if mode == .open { close() }
    }

    func set(_ new: Mode) {
        pending?.cancel()
        guard new != mode else { return }
        let wasOpen = mode == .open
        withAnimation(.island) { mode = new }
        if new == .open {
            // A panel takes the keyboard only when the app is active. The hotkey is user input,
            // so macOS lets us activate. Remember who had focus to hand it back on close.
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate()
            panel?.makeKeyAndOrderFront(nil)
            focusRequest += 1
        } else if wasOpen {
            editing = nil
            scheduling = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, mode != .open else { return }
                giveBackKeyboard()
            }
        }
    }

    /// Returns focus to the app the user was in before the island opened.
    private func giveBackKeyboard() {
        if NSApp.isActive, let previousApp, previousApp != .current {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate(options: [])
        } else if let panel, panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        pending?.cancel()
        let item = DispatchWorkItem(block: work)
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    // MARK: Clock and alerts

    func tick() {
        now = Date()
        guard mode == .closed || mode == .peek,
              let due = store.todos.dueNow(now).first(where: { !alerted.contains($0.id) }) else { return }
        alerted.insert(due.id)
        set(.alert(due.id))
        haptic()
        NSSound(named: "Glass")?.play()
        after(12) { [weak self] in self?.set(.closed) }
    }

    func alertDone(_ todo: Todo) {
        store.toggle(todo.id)
        set(.closed)
    }

    func snooze(_ todo: Todo) {
        store.update(todo.id) {
            $0.day = Day.key(now)
            $0.minute = min(Day.minute(of: now) + 10, 24 * 60 - 1)
        }
        alerted.remove(todo.id)
        set(.closed)
    }

    // MARK: Tasks

    func addDraft() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let p = plan
        withAnimation(.snappy) {
            store.add(p.title, day: p.day, minute: p.minute)
            bucket = destination(p.day)
        }
        draft = ""
    }

    /// The list a task with this day shows in.
    func destination(_ day: String?) -> Bucket {
        guard let day else { return .backlog }
        return day <= today ? .today : .upcoming
    }

    func toggle(_ todo: Todo) {
        withAnimation(.snappy) { store.toggle(todo.id) }
    }

    func rename(_ todo: Todo, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { store.update(todo.id) { $0.title = title } }
        editing = nil
    }

    func delete(_ todo: Todo) {
        withAnimation(.snappy) { _ = store.delete(todo.id) }
        if scheduling == todo.id { scheduling = nil }
        showToast("Deleted “\(todo.title)”") { [weak self] in self?.store.restore(todo) }
    }

    /// Moves a task. A task with no day has no time.
    func move(_ todo: Todo, day: String?, minute: Int?) {
        let minute = day == nil ? nil : minute
        guard day != todo.day || minute != todo.minute else { return }
        withAnimation(.snappy) {
            store.update(todo.id) {
                $0.day = day
                $0.minute = minute
            }
        }
        guard destination(day) != bucket else { return }
        if scheduling == todo.id { scheduling = nil }
        showToast("Moved to \(Format.when(day: day, minute: minute, now: now))") { [weak self] in
            self?.store.update(todo.id) {
                $0.day = todo.day
                $0.minute = todo.minute
            }
        }
    }

    func setDay(_ todo: Todo, _ day: String?) { move(todo, day: day, minute: todo.minute) }

    func setTime(_ todo: Todo, _ minute: Int?) { move(todo, day: todo.day ?? today, minute: minute) }

    /// Applies a typed phrase like "fri 4pm". False if the phrase has no date or time.
    func reschedule(_ todo: Todo, phrase: String) -> Bool {
        guard let w = QuickParse.when(phrase, now: now) else { return false }
        move(todo, day: w.day ?? todo.day ?? today, minute: w.minute ?? todo.minute)
        return true
    }

    func undoLast() {
        withAnimation(.snappy) { undoAction?() }
        dismissToast()
    }

    private func showToast(_ text: String, undo: @escaping () -> Void) {
        undoAction = undo
        withAnimation(.snappy) { toast = Toast(text: text) }
        toastWork?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.dismissToast() }
        toastWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: item)
    }

    private func dismissToast() {
        undoAction = nil
        withAnimation(.snappy) { toast = nil }
    }
}

func haptic() {
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
}
