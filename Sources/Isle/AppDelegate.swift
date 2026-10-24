import AppKit
import Carbon.HIToolbox
import IsleCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    // ISLE_DATA points the app at another file, for demos and testing. Notes live beside it.
    private static let dataURL = ProcessInfo.processInfo.environment["ISLE_DATA"]
        .map { URL(fileURLWithPath: $0) } ?? TodoStore.defaultURL
    private let model = IslandModel(store: TodoStore(url: dataURL), notes: NoteStore(url: NoteStore.url(beside: dataURL)))
    private var panel: IslandPanel?
    private var clock: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.editMenu()
        panel = IslandPanel(model: model)
        let env = ProcessInfo.processInfo.environment
        if let dir = env["ISLE_SNAPSHOT"], let panel {
            Harness.snapshot(model: model, panel: panel, dir: URL(fileURLWithPath: dir))
        }
        if env["ISLE_SELFTEST"] != nil, let panel {
            Harness.selfTest(model: model, panel: panel)
        }
        // After the harness, so a test run is isolated before the first tick can ask or write a setting.
        model.tick()
        // A harness run calls `tick` and the hot key actions itself. A clock would redraw the island at
        // random moments, and the hot keys would take ⌃⌥T and ⌃⌥N from the installed Isle.
        guard !Harness.isRunning else { return }
        clock = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [model] _ in model.tick() }
        registerHotKey(id: 1, "⌃⌥T", keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey) { [model] in model.hotKey() }
        registerHotKey(id: 2, "⌃⌥N", keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey) { [model] in model.noteHotKey() }
    }

    /// An accessory app shows no menu bar, but its menu still gives text fields the standard keys.
    /// Without it, ⌘Z, ⌘X, ⌘C, ⌘V, and ⌘A do nothing in Isle.
    private static func editMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let menu = NSMenu()
        menu.addItem(NSMenuItem())  // the app menu's place: AppKit treats the first item as the app menu
        let item = NSMenuItem()
        item.submenu = edit
        menu.addItem(item)
        return menu
    }
}

/// The action of each hot key, by its id.
private var hotKeyActions: [UInt32: () -> Void] = [:]

/// Registers a global hot key with Carbon. It needs no Accessibility permission.
private func registerHotKey(id: UInt32, _ name: String, keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
    if hotKeyActions.isEmpty {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var key = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard status == noErr else { return status }
            DispatchQueue.main.async { hotKeyActions[key.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
    hotKeyActions[id] = action
    var ref: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: OSType(0x4953_4C45), id: id)  // "ISLE"
    let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    if status != noErr { NSLog("Isle: could not register \(name) (\(status)). Click the notch instead.") }
}
