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
    var page: Page = .tasks
    /// The day plan being written, one string for each line. It stays when the page or the island closes.
    var planLines = [""]

    // MARK: Settings, kept in UserDefaults

    var theme = IslandTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .standard {
        didSet { remember(theme.rawValue, "theme") }
    }
    var glassLook = GlassLook(rawValue: UserDefaults.standard.string(forKey: "glassLook") ?? "") ?? .system {
        didSet { remember(glassLook.rawValue, "glassLook") }
    }
    var reminderSound = UserDefaults.standard.object(forKey: "reminderSound") as? Bool ?? true {
        didSet { remember(reminderSound, "reminderSound") }
    }
    /// The day the morning question showed or a plan was added, so the question comes once a day.
    var planAskedDay = UserDefaults.standard.string(forKey: "planAskedDay") {
        didSet { remember(planAskedDay ?? "", "planAskedDay") }
    }

    /// A harness run shares the app's UserDefaults, so an isolated island never writes them.
    private func remember(_ value: Any, _ key: String) {
        if !isolated { UserDefaults.standard.set(value, forKey: key) }
    }

    @ObservationIgnored weak var panel: NSPanel?
    /// Set by the dev harness. The panel stops forwarding live hover and focus loss, and the island
    /// never takes focus, rings, or taps the trackpad, so a run and the user cannot disturb each other.
    @ObservationIgnored var isolated = false
    @ObservationIgnored private var hovering = false
    @ObservationIgnored private var pending: DispatchWorkItem?
    @ObservationIgnored private var toastWork: DispatchWorkItem?
    @ObservationIgnored private var undoAction: (() -> Void)?
    @ObservationIgnored private var alerted = Set<UUID>()
    @ObservationIgnored private var previousApp: NSRunningApplication?
    /// The day `planLines` was written for. A draft from an earlier day is not today's plan.
    @ObservationIgnored private var planDay: String?

    static let wing: CGFloat = 44
    static let openMaxHeight: CGFloat = 480
    /// A paste of thousands of lines must not make thousands of fields.
    static let planLineLimit = 100

    init(store: TodoStore) {
        self.store = store
    }

    // MARK: Derived state

    var today: String { Day.key(now) }
    var sections: TodaySections { store.todos.todaySections(now) }
    var progress: DayProgress { store.todos.progress(now) }
    var next: Todo? { store.todos.nextTimed(now) }
    var plan: Parsed { QuickParse.plan(draft, bucket: bucket, now: now) }
    /// The tasks the plan page will add.
    var planned: [Parsed] { QuickParse.planLines(planLines, now: now) }

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

    /// The largest window any mode needs. The SwiftUI canvas always has this size.
    var canvasSize: CGSize {
        CGSize(width: notch.width + 460 + 60, height: Self.openMaxHeight + 40)
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
                if !isolated { haptic() }
            }
        case (true, _):
            pending?.cancel()  // keep an open island or an alert while the pointer is on it
        case (false, .peek):
            set(.closed)
        case (false, .open) where isIdle:
            after(0.7) { [weak self] in
                // Check again: the user may have started to type after the pointer left.
                guard let self, !hovering, isIdle else { return }
                set(.closed)
            }
        case (false, .alert):
            after(4) { [weak self] in self?.set(.closed) }
        default:
            break
        }
    }

    /// Nothing typed, nothing in edit, and no plan page, so the island may close by itself.
    private var isIdle: Bool { draft.isEmpty && editing == nil && scheduling == nil && page != .plan }

    func tap() {
        if mode != .open { open() }
    }

    /// `activate` is only for the hotkey. A click reaches the panel without activating the app,
    /// but typed keys after a hotkey press need the app active. That press is user input, so macOS allows it.
    func open(activate: Bool = false) {
        if case .alert = mode { bucket = .today }
        if activate && !isolated {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate()
        }
        set(.open)
    }

    func close() { set(.closed) }

    /// The hotkey is for capture, so it always opens on Today.
    func hotKey() {
        if mode == .open { return close() }
        bucket = .today
        open(activate: true)
    }

    func escape() {
        if page == .settings {
            toggleSettings()
        } else if page == .plan {
            togglePlan()
        } else if editing != nil || scheduling != nil {
            endEditing()
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

    func toggleSettings() {
        endEditing()
        withAnimation(.snappy) { page = page == .settings ? .tasks : .settings }
    }

    /// Ends a rename or a schedule edit. The row saves its rename when `editing` clears.
    /// The keyboard goes back to the add field.
    func endEditing() {
        guard editing != nil || scheduling != nil else { return }
        editing = nil
        withAnimation(.snappy) { scheduling = nil }
        focusRequest += 1
    }

    func set(_ new: Mode) {
        pending?.cancel()
        guard new != mode else { return }
        let wasOpen = mode == .open
        withAnimation(.island) { mode = new }
        if new == .open {
            page = .tasks  // here, not on close, so a fading settings page does not swap to the list
            // An isolated (harness) island must never take the user's keys.
            if !isolated { panel?.makeKeyAndOrderFront(nil) }
            focusRequest += 1
            return
        }
        if wasOpen {
            editing = nil
            scheduling = nil
        }
        // At once, so no key typed after Esc or after a click on an alert button is lost.
        if NSApp.isActive || panel?.isKeyWindow == true { giveBackKeyboard() }
    }

    /// Returns focus to the app the user was in before the island opened.
    private func giveBackKeyboard() {
        defer { previousApp = nil }
        if NSApp.isActive {
            if let previousApp, previousApp != .current {
                NSApp.yieldActivation(to: previousApp)
                if previousApp.activate(from: .current, options: []) { return }
            }
            NSApp.deactivate()
        } else if let panel, panel.isKeyWindow {
            panel.makeFirstResponder(nil)
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
        if !isolated {
            haptic()
            if reminderSound { NSSound(named: "Glass")?.play() }
        }
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

    /// Saves a new title. An empty or unchanged title changes nothing.
    func rename(_ todo: Todo, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != todo.title else { return }
        store.update(todo.id) { $0.title = title }
    }

    func delete(_ todo: Todo) {
        withAnimation(.snappy) { _ = store.delete(todo.id) }
        if scheduling == todo.id { endEditing() }
        showToast("Deleted “\(todo.title)”") { [weak self] in self?.store.restore(todo) }
    }

    /// Moves a task. A task with no day has no time.
    func move(_ todo: Todo, day: String?, minute: Int?) {
        let minute = day == nil ? nil : minute
        guard day != todo.day || minute != todo.minute else { return }
        alerted.remove(todo.id)  // a new time gets a new reminder
        withAnimation(.snappy) {
            store.update(todo.id) {
                $0.day = day
                $0.minute = minute
            }
        }
        guard destination(day) != bucket else { return }
        if scheduling == todo.id { endEditing() }
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

    // MARK: Draft chips

    /// A day chip under the add field. It rewrites the draft's trailing words, so the field
    /// always shows what the task will get. Nil means Backlog, which has no words: the list decides.
    func pickDay(_ day: String?) {
        let p = QuickParse.parse(draft, now: now)
        if day == nil { bucket = .backlog }
        rewriteDraft(p.title, day: day, minute: day == nil ? nil : p.minute)
    }

    /// A time chip under the add field. Nil means Anytime.
    func pickTime(_ minute: Int?) {
        let p = QuickParse.parse(draft, now: now)
        rewriteDraft(p.title, day: p.day, minute: minute)
    }

    private func rewriteDraft(_ title: String, day: String?, minute: Int?) {
        let words = QuickParse.phrase(day: day, minute: minute, now: now)
        draft = words.isEmpty ? title : "\(title) \(words)"
        focusRequest += 1  // keep typing after a click
    }

    // MARK: Day plan

    /// Shows the plan page, and opens the island first if it is closed.
    func openPlan() {
        endEditing()
        if planDay != today {
            planLines = [""]
            planDay = today
        }
        if mode != .open { open() }
        withAnimation(.snappy) { page = .plan }
    }

    /// The plan button and ⌘P: the plan page, or back to the tasks from it.
    func togglePlan() {
        if page == .plan {
            withAnimation(.snappy) { page = .tasks }
        } else {
            openPlan()
        }
    }

    /// Writes line `i`. Text with line breaks (a paste) fills lines from `i` on, up to the limit.
    /// Returns the last line written, so the keyboard can follow a paste.
    @discardableResult
    func setPlanLine(_ i: Int, _ text: String) -> Int {
        guard planLines.indices.contains(i) else { return i }
        guard text.contains(where: \.isNewline) else {
            planLines[i] = text
            return i
        }
        // `\r\n` is one Character, so Windows line ends split clean.
        let room = Self.planLineLimit - planLines.count + 1
        let parts = text.split(whereSeparator: \.isNewline).prefix(max(room, 1)).map(String.init)
        planLines.replaceSubrange(i...i, with: parts.isEmpty ? [""] : parts)
        return i + max(parts.count, 1) - 1
    }

    /// Return: a new empty line under line `i`. Nil on an empty line or a full plan.
    func insertPlanLine(after i: Int) -> Int? {
        guard planLines.indices.contains(i), !planLines[i].trimmingCharacters(in: .whitespaces).isEmpty,
              planLines.count < Self.planLineLimit else { return nil }
        planLines.insert("", at: i + 1)
        return i + 1
    }

    /// Delete on an empty line: removes it and returns the line above. The first line stays.
    func removePlanLine(_ i: Int) -> Int? {
        guard i > 0, planLines.indices.contains(i), planLines[i].isEmpty else { return nil }
        planLines.remove(at: i)
        return i - 1
    }

    /// ⌘Return: every line with a title becomes a task, in order. One undo removes them all.
    func commitPlan() {
        let items = planned
        guard !items.isEmpty else { return }
        var added: [Todo] = []
        withAnimation(.snappy) {
            added = store.add(items)
            planLines = [""]
            page = .tasks
            bucket = .today
        }
        planAskedDay = today
        let ids = Set(added.map(\.id))
        showToast("Added \(added.count) \(added.count == 1 ? "task" : "tasks")") { [weak self] in
            _ = self?.store.delete(ids)
        }
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
