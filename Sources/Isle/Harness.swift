import AppKit
import IsleCore

/// Dev checks that drive the real panel, so no screen-recording or accessibility permission is needed.
enum Harness {
    /// `ISLE_SELFTEST` or `ISLE_SNAPSHOT` is set.
    static var isRunning: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["ISLE_SELFTEST"] != nil || env["ISLE_SNAPSHOT"] != nil
    }

    /// `ISLE_SNAPSHOT=<dir>`: walks the panel through each state, saves a PNG of each, and quits.
    static func snapshot(model: IslandModel, panel: NSPanel, dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        isolate(panel, model)
        if model.notes.notes.isEmpty {
            model.notes.setDayNote(model.today, "TA office hours moved to Wed. Bring the charger.")
            for text in ["Book list\nThe Pragmatic Programmer", "Wi-Fi for the lab\nnetwork CS-Lab, ask the TA for the guest code"] {
                model.notes.setText(model.notes.create().id, text)
            }
        }
        let steps: [(String, () -> Void)] = [
            ("1-closed", { model.set(.closed) }),
            ("2-peek", { model.set(.peek) }),
            ("3-today", { model.bucket = .today; model.set(.open) }),
            ("4-draft", { model.draft = "dentist fri 3:30pm" }),
            ("5-upcoming", { model.draft = ""; model.bucket = .upcoming }),
            ("6-backlog", { model.bucket = .backlog }),
            ("7-schedule", { model.scheduling = model.store.todos.backlog(model.now).first?.id }),
            ("8-alert", {
                model.scheduling = nil
                model.set(.closed)
                if let t = model.next { model.set(.alert(t.id)) }
            }),
            ("9-glass-dark", {
                model.set(.closed)
                model.theme = .glass  // isolated: not saved
                model.glassLook = .dark
                model.bucket = .today
                model.set(.open)
            }),
            ("10-glass-light", { model.glassLook = .light }),
            ("11-settings", {
                model.theme = .standard
                model.page = .settings
            }),
            ("12-glass-settings", {
                model.theme = .glass
                model.glassLook = .dark
            }),
            ("13-glass-light-settings", { model.glassLook = .light }),
            ("14-plan", {
                model.theme = .standard
                // Set, not animated: the hidden test panel does not run animations, so a transition never ends.
                model.page = .plan
                model.planLines = ["finish A1 phase 2", "- call mom 6pm", "dentist fri 3pm", ""]
            }),
            ("14-plan-undo", {
                if let laundry = model.store.todos.first(where: { $0.title == "Laundry" }) { model.delete(laundry) }
            }),
            ("15-morning", {
                model.planLines = [""]
                model.page = .tasks
                model.set(.closed)
                model.set(.morning)
            }),
            ("16-plan-setting", {
                model.set(.open)
                model.page = .settings
            }),
            ("17-notes", { model.page = .notes }),
            ("18-note-editor", {
                model.shownNote = model.notes.notes.first { $0.title == "Wi-Fi for the lab" }?.id
            }),
        ]
        func step(_ i: Int) {
            guard i < steps.count else { return NSApp.terminate(nil) }
            steps[i].1()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                // A hidden window draws only when asked.
                panel.contentView?.layoutSubtreeIfNeeded()
                panel.displayIfNeeded()
                save(panel, to: dir.appendingPathComponent("\(steps[i].0).png"))
                step(i + 1)
            }
        }
        step(0)
    }

    /// `ISLE_SELFTEST=1`: sends real key events through AppKit, checks the result, and exits 0 or 1.
    /// Use it with `ISLE_DATA` pointing at a scratch file.
    static func selfTest(model: IslandModel, panel: NSPanel) {
        isolate(panel, model)
        let askedAtStart = UserDefaults.standard.string(forKey: "planAskedDay")
        var failures = 0
        func expect(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        func key(_ chars: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
            guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                           windowNumber: panel.windowNumber, context: nil, characters: chars,
                                           charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) else { return }
            // Straight to the panel: it is never key in a test run, and the app drops keys for a window that is not.
            panel.sendEvent(e)
        }
        func type(_ text: String) { text.forEach { key(String($0), 0) } }
        let up = String(UnicodeScalar(NSUpArrowFunctionKey)!), down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        let backspace = "\u{7F}"
        /// The window's text editor, where typed keys land.
        func editor() -> NSTextView? { panel.firstResponder as? NSTextView }
        func draw() {
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
        }
        func shownText() -> String? {
            model.shownNote.flatMap { id in model.notes.notes.first { $0.id == id }?.text }
        }
        /// A ⌘ key equivalent, the way AppKit offers it to the window before any view sees the key.
        func shortcut(_ chars: String, _ code: UInt16) {
            guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                           windowNumber: panel.windowNumber, context: nil, characters: chars,
                                           charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) else { return }
            _ = panel.performKeyEquivalent(with: e)
        }
        /// A real click through AppKit and SwiftUI hit testing, at a point in window coordinates.
        func click(_ point: NSPoint) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { continue }
                panel.sendEvent(e)
            }
        }
        /// An empty spot in the lower left of the island, away from any text.
        func emptySpot() -> NSPoint { NSPoint(x: panel.frame.width * 0.12, y: panel.frame.height * 0.3) }
        func nineToday() -> Date { Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())! }
        let esc = "\u{1b}"
        let steps: [() -> Void] = [
            {},  // the panel's first draw after launch
            { model.hotKey() },
            {
                expect(model.mode == .open, "hotkey opens the island")
                // macOS grants key status only after real input, so this is a note, not a check.
                print("INFO  key window: \(panel.isKeyWindow), app active: \(NSApp.isActive)")
                type("groceries 5pm")
            },
            {
                expect(model.draft == "groceries 5pm", "typing goes to the add field")
                key("\r", 36)
            },
            {
                let t = model.store.todos.first { $0.title == "groceries" }
                expect(t?.day == model.today && t?.minute == 1020 && model.draft.isEmpty, "Return adds groceries today at 5 PM")
                if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                            windowNumber: panel.windowNumber, context: nil, characters: "3",
                                            charactersIgnoringModifiers: "3", isARepeat: false, keyCode: 20) {
                    _ = panel.performKeyEquivalent(with: e)
                }
            },
            {
                expect(model.bucket == .backlog, "⌘3 shows Backlog")
                type("x")
                key(esc, 53)
            },
            {
                expect(model.draft.isEmpty && model.mode == .open, "the first Esc clears the draft")
                key(esc, 53)
            },
            { expect(model.mode == .closed, "the second Esc closes the island") },
            {
                expect(!panel.isKeyWindow && !NSApp.isActive, "the closed island gives the keyboard back")
                model.hover(true)
            },
            {
                expect(model.mode == .peek, "hover peeks")
                model.hover(false)
            },
            {
                expect(model.mode == .closed, "leaving the peek closes it")
                // The user leaves the island and starts to type before the close delay ends.
                model.open()
                model.hover(true)
                model.hover(false)
                model.draft = "buy"
            },
            {
                expect(model.mode == .open, "typing keeps the island open after the pointer leaves")
                model.draft = ""
                model.close()
                let m = Day.minute(of: Date())
                // "groceries 5pm" is due too from 5:00 to 5:04 PM, and it would alert first.
                if let groceries = model.store.todos.first(where: { $0.title == "groceries" }) {
                    model.store.update(groceries.id) { $0.minute = nil }
                }
                model.store.add("ping", day: model.today, minute: m)
                model.tick()
            },
            {
                let ping = model.store.todos.first { $0.title == "ping" }
                expect(model.alertTodo?.title == "ping", "a task alerts at its time")
                if let ping, let m = ping.minute { model.move(ping, day: model.today, minute: max(m - 1, 0)) }
                model.close()
                model.tick()
            },
            {
                expect(model.alertTodo?.title == "ping", "a moved task alerts again")
                model.close()
                model.open()
            },
            {
                // The header with the ⌘, button exists only after the open step has rendered.
                if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                            windowNumber: panel.windowNumber, context: nil, characters: ",",
                                            charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43) {
                    _ = panel.performKeyEquivalent(with: e)
                }
            },
            {
                expect(model.page == .settings, "⌘, opens settings")
                key(esc, 53)
            },
            {
                expect(model.page == .tasks && model.mode == .open, "Esc goes back from settings to the tasks")
                let saved = UserDefaults.standard.string(forKey: "theme")
                model.theme = saved == "glass" ? .standard : .glass  // a value that differs from the saved one
                expect(UserDefaults.standard.string(forKey: "theme") == saved, "an isolated run does not save settings")
                model.theme = .standard
                model.close()
            },
            { model.set(.peek) },
            {
                click(emptySpot())
            },
            {
                expect(model.mode == .open, "Standard: a click on the peek opens the island")
                model.close()
                model.theme = .glass
            },
            { model.set(.peek) },
            {
                click(emptySpot())
            },
            {
                expect(model.mode == .open, "Glass: a click on the peek opens the island")
                model.bucket = .backlog
            },
            { type("glass task") },
            {
                expect(model.draft == "glass task", "Glass: typing goes to the add field")
                model.draft = ""
                model.close()
                model.theme = .standard
                model.open()
            },
            {},  // the theme change and the open draw the header first; its ⌘P exists only then
            { shortcut("p", 35) },
            {
                expect(model.page == .plan, "⌘P opens the plan page")
                type("a1 phase 2")
                key("\r", 36)
            },
            { type("call mom 6pm") },
            {
                expect(model.planLines == ["a1 phase 2", "call mom 6pm"], "Return starts a new plan line")
                key(esc, 53)
            },
            {
                expect(model.page == .tasks && model.planLines.count == 2, "Esc keeps the plan draft")
                shortcut("p", 35)
            },
            {
                expect(model.page == .plan && model.planLines == ["a1 phase 2", "call mom 6pm"], "⌘P shows the draft again")
                shortcut("\r", 36)
            },
            {
                let a = model.store.todos.first { $0.title == "a1 phase 2" }
                let c = model.store.todos.first { $0.title == "call mom" }
                expect(a?.day == model.today && a?.minute == nil && c?.day == model.today && c?.minute == 1080
                       && (a?.created ?? .distantFuture) < (c?.created ?? .distantPast)
                       && model.page == .tasks && model.planLines == [""], "⌘Return adds the plan in order")
                expect(!model.showsPlanBanner, "an added plan hides the Plan your day button")
                // The morning question came and went unseen: Today keeps a way in until the plan is done.
                model.planDoneDay = nil  // isolated: not saved
                expect(model.showsPlanBanner, "a missed morning question leaves a Plan your day button")
                model.dismissPlanBanner()
                expect(!model.showsPlanBanner, "the Plan your day button closes for today")
                model.planDoneDay = nil
                model.undoLast()
            },
            {
                expect(!model.store.todos.contains { $0.title == "a1 phase 2" || $0.title == "call mom" },
                       "Undo removes the whole plan")
                _ = model.setPlanLine(0, (1...150).map(String.init).joined(separator: "\n"))
                expect(model.planLines.count == IslandModel.planLineLimit, "a huge paste keeps 100 lines")
                model.planLines = [""]
                _ = model.setPlanLine(0, "a\r\nb")
                expect(model.planLines == ["a", "b"], "a CRLF paste splits clean")
                model.planLines = ["one", "two"]
                model.togglePlan()  // the page focuses the last line
            },
            { key("\r", 36) },
            {
                expect(model.planLines == ["one", "two", ""], "Return on the last line adds a line")
                key("\u{7F}", 51)
            },
            {
                expect(model.planLines == ["one", "two"], "Delete on an empty line removes it")
                type("X")
            },
            {
                expect(model.planLines == ["one", "twoX"], "Delete puts the caret at the end of the line above")
                key(up, 126)
            },
            { type("!") },
            {
                expect(model.planLines == ["one!", "twoX"], "↑ moves to the end of the line above")
                key(down, 125)
            },
            { key("\r", 36) },
            {
                expect(model.planLines == ["one!", "twoX", ""], "↓ then Return adds a line under the second")
                // An input method composing on the empty line owns the Delete key.
                editor()?.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0),
                                        replacementRange: NSRange(location: NSNotFound, length: 0))
                key(backspace, 51)
            },
            {
                expect(model.planLines.count == 3, "Delete while an input method composes keeps the line")
                editor()?.unmarkText()
            },
            {
                // A real paste through the field, from a private pasteboard, so the user's clipboard stays.
                let board = NSPasteboard(name: NSPasteboard.Name("isle-selftest-\(UUID().uuidString)"))
                board.clearContents()
                board.setString("p\r\nq\nr", forType: .string)
                _ = editor()?.readSelection(from: board)
                board.releaseGlobally()
                expect(model.planLines == ["one!", "twoX", "p", "q", "r"], "a paste through the field splits into lines")
                let edit = NSApp.mainMenu?.items.first { $0.submenu?.title == "Edit" }?.submenu
                let wanted: [(Selector, String)] = [(Selector(("undo:")), "z"), (#selector(NSText.cut(_:)), "x"),
                                                   (#selector(NSText.copy(_:)), "c"), (#selector(NSText.paste(_:)), "v"),
                                                   (#selector(NSText.selectAll(_:)), "a")]
                expect(wanted.allSatisfy { action, key in
                    edit?.items.contains { $0.action == action && $0.keyEquivalent == key } == true
                }, "the Edit menu gives ⌘Z ⌘X ⌘C ⌘V ⌘A")
                // Esc first closes an open editor on the plan page, then leaves the page.
                model.scheduling = model.store.todos.first { $0.title == "groceries" }?.id
                key(esc, 53)
            },
            {
                expect(model.scheduling == nil && model.page == .plan, "Esc on the plan page first closes an editor")
                model.scheduling = model.store.todos.first { $0.title == "groceries" }?.id
                model.togglePlan()
                expect(model.scheduling == nil && model.page == .tasks, "leaving the plan page ends an edit")
                model.planLines = [""]
                model.close()
                expect(model.planAskedDay == model.today, "an added plan counts as asked for today")
                model.planAskedDay = nil  // isolated: not saved
                // A fixed 9 AM, so the check does not depend on when the test runs.
                expect(model.askToPlan(now: nineToday(), idleSeconds: 0) && model.mode == .morning,
                       "the morning question shows")
                model.tap()
            },
            {
                expect(model.mode == .open && model.page == .plan, "a tap on the question opens the plan page")
                model.close()
                expect(!model.askToPlan(now: nineToday(), idleSeconds: 0), "the question shows once a day")
                expect(UserDefaults.standard.string(forKey: "planAskedDay") == askedAtStart,
                       "a test run never saves planAskedDay")
                model.open()
            },
            { shortcut("4", 21) },
            {
                expect(model.page == .notes && model.shownNote == nil, "⌘4 shows Notes")
                shortcut("n", 45)
            },
            {
                expect(model.shownNote != nil, "⌘N opens a new note")
                type("Wi-Fi for the lab")
            },
            {
                expect(shownText() == "Wi-Fi for the lab", "typing goes into the note")
                key(esc, 53)
            },
            {
                expect(model.shownNote == nil && model.page == .notes && model.mode == .open
                       && model.notes.notes.contains { $0.title == "Wi-Fi for the lab" }, "Esc goes back to the list")
                expect(model.notes.notes.matching("LAB").count == 1, "search finds the note")
                model.newNote()
            },
            {
                // Leave with the new note still empty: a click on the Today tab.
                model.bucket = .today
                model.page = .tasks
                expect(!model.notes.notes.contains(where: \.isEmpty), "an empty note is gone when you leave it")
                model.showNotes()
                if let lab = model.notes.notes.first(where: { $0.title == "Wi-Fi for the lab" }) { model.deleteNote(lab.id) }
                expect(!model.notes.notes.contains { $0.title == "Wi-Fi for the lab" } && model.toast != nil,
                       "a deleted note goes, with an undo bar")
                model.undoLast()
                expect(model.notes.notes.contains { $0.title == "Wi-Fi for the lab" }, "Undo brings a deleted note back")
                model.close()
                model.noteHotKey()
            },
            {
                expect(model.mode == .open && model.page == .notes && model.shownNote != nil, "⌃⌥N opens a new note")
                model.noteHotKey()
            },
            {
                expect(model.mode == .closed && !model.notes.notes.contains(where: \.isEmpty),
                       "⌃⌥N again closes, and the empty note is gone")
                model.notes.setDayNote(model.today, "")
                model.planLines = ["call mom"]
                model.togglePlan()  // opens the island on the plan page, keyboard on the last line
            },
            { key("\t", 48) },
            { type("TA hours") },
            {
                expect(model.notes.dayNote(model.today)?.text == "TA hours", "Tab moves from the plan into the day note")
                expect(model.notes.notes.matching("TA hours").count == 1, "the day note shows in Notes")
                key(esc, 53)
            },
            {
                expect(model.page == .tasks && model.planLines == ["call mom"], "Esc in the day note leaves the plan page")
                model.planLines = [""]
                model.store.add("email prof", day: model.today, minute: nil)
            },
            { if let task = model.store.todos.first(where: { $0.title == "email prof" }) { model.toggleNote(task) } },
            { type("Ask for 2 days") },
            { key(esc, 53) },
            {
                let task = model.store.todos.first { $0.title == "email prof" }
                expect(model.noting == nil && task.flatMap { model.notes.taskNote($0.id)?.text } == "Ask for 2 days",
                       "a task note saves on Esc")
                if let task { model.delete(task) }
                model.undoLast()
                let back = model.store.todos.first { $0.title == "email prof" }
                expect(back != nil && back.flatMap { model.notes.taskNote($0.id)?.text } == "Ask for 2 days",
                       "a task note survives delete and Undo")
                // A search left in Notes must not keep the island open on another page.
                model.showNotes()
                model.noteQuery = "x"
                model.bucket = .today
                model.page = .tasks
                model.hover(true)
                model.hover(false)
            },
            {},  // the island closes 0.7 s after the pointer leaves
            {
                expect(model.mode == .closed, "a search left in Notes does not keep the island open")
                model.open()
            },
            { if let task = model.store.todos.first(where: { $0.title == "email prof" }) { model.toggleNote(task) } },
            {
                if let task = model.store.todos.first(where: { $0.title == "email prof" }) { model.delete(task) }
                expect(model.noting == nil, "deleting a task closes its note editor")
                model.undoLast()
                // The day note's text view is the one every note uses.
                model.notes.setDayNote(model.today, "")
                model.planLines = ["x"]
                model.togglePlan()
            },
            { key("\t", 48) },
            {
                type(" ")
                model.tick()  // any redraw (here the clock) must keep a space the store does not keep
            },
            {
                expect(editor()?.string == " ", "a note can start with a space")
                if let view = editor() {
                    let opened = view.delegate?.textView?(view, clickedOnLink: URL(string: "https://example.com")!, at: 0)
                    expect(opened == true, "a link in a note never opens")
                }
                key(esc, 53)
                model.planLines = [""]
                model.close()
                print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
                exit(failures == 0 ? 0 : 1)
            },
        ]
        for (i, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 * Double(i + 1)) {
                step()
                // A hidden window draws only when asked. Draw now, and again once the views' own deferred
                // work (a focus asked for one moment later) has run, so the next step meets the views this one made.
                draw()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: draw)
            }
        }
    }

    /// A run and a live user must not touch each other: hide the panel, drop clicks, hover, and focus.
    private static func isolate(_ panel: NSPanel, _ model: IslandModel) {
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0  // invisible: the layer still renders for snapshots
        model.isolated = true
        // A debug build uses the "Isle" defaults domain, as `swift run Isle` does. Start every run from the
        // defaults, not saved, so a run neither reads nor changes what a debug session left there.
        model.theme = .standard
        model.glassLook = .system
        model.reminderSound = true
        model.morningPlan = true
        model.planAskedDay = nil
        model.planDoneDay = nil
        // A test run must never be the active app: the user's keys would land here. On macOS 27 a launch from
        // a shell activates the app, and `deactivate()` no longer gives it up. Hiding does, and the panel comes
        // back without activation.
        func stepBack() {
            guard NSApp.isActive else { return }
            NSApp.hide(nil)
            NSApp.unhideWithoutActivation()
        }
        stepBack()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { _ in stepBack() }
    }

    private static func save(_ panel: NSPanel, to url: URL) {
        guard let layer = panel.contentView?.layer else { return }
        let scale = panel.backingScaleFactor
        let size = layer.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return }
        ctx.translateBy(x: 0, y: size.height * scale)
        ctx.scaleBy(x: scale, y: -scale)
        layer.render(in: ctx)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
