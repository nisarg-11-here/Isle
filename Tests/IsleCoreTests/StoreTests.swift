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
