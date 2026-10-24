import AppKit
import IsleCore

// A test run must never read or write the user's real tasks, notes, or settings. It needs ISLE_DATA in a
// scratch folder, checked here, before any store opens a file. Notes go beside that file.
if Harness.isRunning {
    let data = ProcessInfo.processInfo.environment["ISLE_DATA"].map { URL(fileURLWithPath: $0) }
    guard let data, !TodoStore.isInRealFolder(data) else {
        print("ISLE_SELFTEST and ISLE_SNAPSHOT need ISLE_DATA=<file in a scratch folder>. They never run on your real data.")
        exit(2)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
