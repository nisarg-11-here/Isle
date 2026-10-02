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
                NSLog("snapshot \(steps[i].0): mode=\(model.mode) key=\(panel.isKeyWindow) frame=\(panel.frame) openHeight=\(model.openHeight)")
                save(panel, to: dir.appendingPathComponent("\(steps[i].0).png"))
                step(i + 1)
            }
        }
        step(0)
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
