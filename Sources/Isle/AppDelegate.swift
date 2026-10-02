import AppKit
import Carbon.HIToolbox
import IsleCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    // ISLE_DATA points the app at another file, for demos and testing.
    private let model = IslandModel(store: TodoStore(url: ProcessInfo.processInfo.environment["ISLE_DATA"]
        .map { URL(fileURLWithPath: $0) } ?? TodoStore.defaultURL))
    private var panel: IslandPanel?
    private var clock: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = IslandPanel(model: model)
        registerHotKey(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey) { [model] in model.hotKey() }
        clock = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [model] _ in model.tick() }
        model.tick()
        let env = ProcessInfo.processInfo.environment
        if let dir = env["ISLE_SNAPSHOT"], let panel {
            Harness.snapshot(model: model, panel: panel, dir: URL(fileURLWithPath: dir))
        }
        if env["ISLE_SELFTEST"] != nil, let panel {
            // The self-test adds tasks. It must never touch the user's real list.
            guard env["ISLE_DATA"] != nil else {
                print("ISLE_SELFTEST needs ISLE_DATA=<scratch file>. It never runs on your real list.")
                exit(2)
            }
            Harness.selfTest(model: model, panel: panel)
        }
    }
}

private var hotKeyAction: (() -> Void)?

/// Registers one global hotkey with Carbon. It needs no Accessibility permission.
private func registerHotKey(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
    hotKeyAction = action
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        DispatchQueue.main.async { hotKeyAction?() }
        return noErr
    }, 1, &spec, nil, nil)
    var ref: EventHotKeyRef?
    let id = EventHotKeyID(signature: OSType(0x4953_4C45), id: 1)  // "ISLE"
    let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
    if status != noErr { NSLog("Isle: could not register ⌃⌥T (\(status)). Click the notch instead.") }
}
