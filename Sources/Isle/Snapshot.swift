import AppKit
import IsleCore

/// `ISLE_SNAPSHOT=<dir>` walks the real panel through each state, saves a PNG of each,
/// and quits. It checks the layout without screen-recording permission and makes README images.
enum Snapshot {
    static func run(model: IslandModel, panel: NSPanel, dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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

    private static func save(_ panel: NSPanel, to url: URL) {
        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
