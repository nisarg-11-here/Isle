import AppKit
import IsleCore

/// Dev checks that drive the real panel, so no screen-recording or accessibility permission is needed.
enum Harness {
    /// `ISLE_SNAPSHOT=<dir>`: walks the panel through each state, saves a PNG of each, and quits.
    static func snapshot(model: IslandModel, panel: NSPanel, dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        isolate(panel, model)
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
        ]
        func step(_ i: Int) {
            guard i < steps.count else { return NSApp.terminate(nil) }
            steps[i].1()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
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
        var failures = 0
        func expect(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        func key(_ chars: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
            guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                           windowNumber: panel.windowNumber, context: nil, characters: chars,
                                           charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) else { return }
            NSApp.sendEvent(e)
        }
        func type(_ text: String) { text.forEach { key(String($0), 0) } }
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
        let esc = "\u{1b}"
        let steps: [() -> Void] = [
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
                print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
                exit(failures == 0 ? 0 : 1)
            },
        ]
        for (i, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 * Double(i + 1), execute: step)
        }
    }

    /// A run and a live user must not touch each other: hide the panel, drop clicks, hover, and focus.
    private static func isolate(_ panel: NSPanel, _ model: IslandModel) {
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0  // invisible: the layer still renders for snapshots
        model.isolated = true
        // The test build shares the app's UserDefaults. Start every run from the defaults (not saved).
        model.theme = .standard
        model.glassLook = .system
        model.reminderSound = true
        // A test run must never be the active app: the user's keys would land here.
        if NSApp.isActive { NSApp.deactivate() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { _ in NSApp.deactivate() }
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
