import Foundation
import Testing
@testable import IsleCore

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}

@Test func storeSavesAndReloads() throws {
    let url = tempDir().appendingPathComponent("todos.json")
    let store = TodoStore(url: url)
    let milk = try #require(store.add("  buy milk ", day: "2026-10-02", minute: 1020))
    #expect(milk.title == "buy milk")
    #expect(store.add("   ", day: nil, minute: nil) == nil)
    store.toggle(milk.id, now: now)
    let extra = try #require(store.add("extra", day: nil, minute: nil))
    let removed = try #require(store.delete(extra.id))

    let reloaded = TodoStore(url: url)
    #expect(reloaded.todos.map(\.title) == ["buy milk"])
    #expect(reloaded.todos.first?.doneAt != nil)

    store.restore(removed)
    #expect(TodoStore(url: url).todos.count == 2)
}

@Test func corruptFileIsKeptAside() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("todos.json")
    try Data("not json".utf8).write(to: url)

    let store = TodoStore(url: url)
    #expect(store.todos.isEmpty)
    store.add("fresh", day: nil, minute: nil)

    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    let backup = try #require(files.first { $0.hasPrefix("todos.corrupt-") })
    #expect(try String(contentsOf: dir.appendingPathComponent(backup), encoding: .utf8) == "not json")
    #expect(TodoStore(url: url).todos.map(\.title) == ["fresh"])
}

@Test func launchKeepsABackupOfTheLastGoodFile() throws {
    let dir = tempDir()
    let url = dir.appendingPathComponent("todos.json")
    TodoStore(url: url).add("keep me", day: nil, minute: nil)

    _ = TodoStore(url: url)  // a relaunch
    let backup = dir.appendingPathComponent("todos.backup.json")
    #expect(try Data(contentsOf: backup) == Data(contentsOf: url))
    #expect(TodoStore(url: backup).todos.map(\.title) == ["keep me"])
}

@Test func aFreshStartWritesNoBackup() {
    let dir = tempDir()
    _ = TodoStore(url: dir.appendingPathComponent("todos.json"))
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("todos.backup.json").path))
}

@Test func batchAddKeepsOrderAfterAReload() throws {
    let url = tempDir().appendingPathComponent("todos.json")
    let store = TodoStore(url: url)
    let added = store.add([Parsed(title: "c", day: "2026-10-02"), Parsed(title: " ", day: "2026-10-02"),
                           Parsed(title: "a", day: "2026-10-02"), Parsed(title: "b", day: nil, minute: 600)], now: now)
    #expect(added.map(\.title) == ["c", "a", "b"])
    #expect(added.last?.minute == nil)
    let reloaded = TodoStore(url: url).todos
    #expect(Set(reloaded.map(\.created)).count == 3)  // still distinct after the file drops fractions
    #expect(reloaded.todaySections(now, cal).anytime.map(\.title) == ["c", "a"])
}

@Test func batchDeleteRemovesOnlyThoseIds() throws {
    let url = tempDir().appendingPathComponent("todos.json")
    let store = TodoStore(url: url)
    let added = store.add([Parsed(title: "x"), Parsed(title: "y"), Parsed(title: "z")], now: now)
    let removed = store.delete(Set(added.prefix(2).map(\.id)))
    #expect(Set(removed.map(\.title)) == ["x", "y"])
    #expect(TodoStore(url: url).todos.map(\.title) == ["z"])
}

private func permissions(_ url: URL) throws -> Int {
    try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

@Test func savedFilesAreOwnerOnly() throws {
    let dir = tempDir()
    let url = dir.appendingPathComponent("todos.json")
    TodoStore(url: url).add("secret", day: nil, minute: nil)
    _ = TodoStore(url: url)  // a relaunch writes the backup
    #expect(try permissions(url) == 0o600)
    #expect(try permissions(dir.appendingPathComponent("todos.backup.json")) == 0o600)
    #expect(try permissions(dir) == 0o700)  // the store made this folder
}

@Test func anExistingFolderKeepsItsPermissions() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o755])
    TodoStore(url: dir.appendingPathComponent("t.json")).add("x", day: nil, minute: nil)
    #expect(try permissions(dir) == 0o755)
}

@Test func aCorruptFileOfAnyNameIsKeptAside() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("notes.json")
    try Data("{".utf8).write(to: url)
    #expect(JSONFile<[Note]>(url: url).load() == nil)
    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(files.contains { $0.hasPrefix("notes.corrupt-") })
    #expect(!files.contains("notes.json"))
}
