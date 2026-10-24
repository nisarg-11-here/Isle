import Foundation
import Testing
@testable import IsleCore

private func noteStore() -> (NoteStore, URL) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("notes.json")
    return (NoteStore(url: url), url)
}

private let later = now.addingTimeInterval(60)

@Test func titleIsTheFirstLineWithText() {
    #expect(Note(text: "\n  Wi-Fi for the lab \nnet: CS").title == "Wi-Fi for the lab")
    #expect(Note(text: " \n ").title == "New note")
    #expect(Note(text: " \n ").isEmpty)
    #expect(!Note(text: "x").isEmpty)
}

@Test func notesSurviveAReloadButEmptyOnesDoNot() {
    let (store, url) = noteStore()
    let keep = store.create(now: now)
    store.create(now: now)
    store.setText(keep.id, "keep", now: now)
    #expect(NoteStore(url: url).notes.map(\.text) == ["keep"])
}

@Test func setTextCapsAndStampsOnlyChanges() throws {
    let (store, _) = noteStore()
    let note = store.create(now: now)
    store.setText(note.id, String(repeating: "a", count: Note.maxLength + 1), now: now)
    #expect(store.notes.first?.text.count == Note.maxLength)
    store.setText(note.id, "same", now: now)
    store.setText(note.id, "same", now: later)
    #expect(store.notes.first?.updated == now)
    store.setText(note.id, "changed", now: later)
    #expect(store.notes.first?.updated == later)
}

@Test func deleteAndRestore() throws {
    let (store, url) = noteStore()
    let note = store.create(now: now)
    store.setText(note.id, "gone", now: now)
    let removed = try #require(store.delete(note.id))
    #expect(removed.text == "gone")
    #expect(NoteStore(url: url).notes.isEmpty)
    store.restore(removed)
    #expect(NoteStore(url: url).notes.map(\.text) == ["gone"])
}

@Test func discardIfEmptyKeepsNotesWithText() {
    let (store, _) = noteStore()
    let empty = store.create(now: now)
    let full = store.create(now: now)
    store.setText(full.id, "x", now: now)
    store.discardIfEmpty(empty.id)
    store.discardIfEmpty(full.id)
    #expect(store.notes.map(\.text) == ["x"])
}

@Test func dayNotesAreMadeChangedAndDeleted() {
    let (store, _) = noteStore()
    store.setDayNote("2026-10-02", "TA hours", now: now)
    #expect(store.dayNote("2026-10-02")?.text == "TA hours")
    store.setDayNote("2026-10-02", "TA hours moved", now: later)
    #expect(store.notes.count == 1)
    store.setDayNote("2026-10-02", "  ", now: later)
    #expect(store.dayNote("2026-10-02") == nil)
    #expect(store.notes.isEmpty)
    // A hand edit can leave two day notes for one day. The newest wins.
    store.restore(Note(text: "old", day: "2026-10-02", created: now))
    store.restore(Note(text: "new", day: "2026-10-02", created: later))
    #expect(store.dayNote("2026-10-02")?.text == "new")
}

@Test func taskNotesAreMadeChangedAndDeleted() {
    let (store, _) = noteStore()
    let task = UUID()
    store.setTaskNote(task, "Ask for 2 days", now: now)
    #expect(store.taskNote(task)?.text == "Ask for 2 days")
    #expect(store.taskIDsWithNotes == [task])
    store.setTaskNote(task, "Ask for 3 days", now: later)
    #expect(store.notes.count == 1)
    store.setTaskNote(task, "", now: later)
    #expect(store.taskNote(task) == nil)
    #expect(store.taskIDsWithNotes.isEmpty)
}

@Test func matchingIgnoresCaseAndDiacriticsAndSkipsTaskNotes() {
    let notes = [
        Note(text: "WiFi code", created: now),
        Note(text: "Café list", created: now.addingTimeInterval(10)),
        Note(text: "Wi-Fi", created: now.addingTimeInterval(20)),
        Note(text: "wifi day", day: "2026-10-02", created: now.addingTimeInterval(30)),
        Note(text: "wifi task", taskID: UUID(), created: now.addingTimeInterval(40)),
    ]
    #expect(notes.matching("wifi").map(\.text) == ["wifi day", "WiFi code"])
    #expect(notes.matching("cafe").map(\.text) == ["Café list"])
    #expect(notes.matching("  ").map(\.text) == ["wifi day", "Wi-Fi", "Café list", "WiFi code"])
}
