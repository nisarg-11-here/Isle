import Foundation
import Observation

/// A plain text note: free, the note of a day, or the note of a task.
public struct Note: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    /// The day this is the note of, "yyyy-MM-dd". Nil for a free note or a task note.
    public var day: String?
    /// The task this is the note of. Nil for a free note or a day note.
    public var taskID: UUID?
    public var created: Date
    public var updated: Date

    public init(id: UUID = UUID(), text: String = "", day: String? = nil, taskID: UUID? = nil,
                created: Date = Date(), updated: Date? = nil) {
        self.id = id
        self.text = text
        self.day = day
        self.taskID = taskID
        self.created = created
        self.updated = updated ?? created
    }

    /// A paste far longer than any real note would slow every save.
    public static let maxLength = 100_000

    /// The first line with text, trimmed.
    public var title: String {
        text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "New note"
    }

    public var isEmpty: Bool { text.allSatisfy(\.isWhitespace) }
}

/// The notes, saved as JSON beside the task file after each change. A note with no text is never written.
@Observable
public final class NoteStore {
    public private(set) var notes: [Note] = []
    private let file: JSONFile<[Note]>

    /// "notes.json" in the folder of the task file, so a test run's `ISLE_DATA` keeps its notes apart.
    public static func url(beside dataFile: URL) -> URL {
        dataFile.deletingLastPathComponent().appendingPathComponent("notes.json")
    }

    public init(url: URL) {
        file = JSONFile(url: url)
        notes = file.load() ?? []
    }

    /// An empty free note. It reaches the file with its first text.
    @discardableResult
    public func create(now: Date = Date()) -> Note {
        let note = Note(created: now)
        notes.append(note)
        return note
    }

    /// Cut at `Note.maxLength`. `updated` moves only when the text changes.
    public func setText(_ id: UUID, _ text: String, now: Date = Date()) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let text = String(text.prefix(Note.maxLength))
        guard text != notes[i].text else { return }
        notes[i].text = text
        notes[i].updated = now
        save()
    }

    @discardableResult
    public func delete(_ id: UUID) -> Note? {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = notes.remove(at: i)
        save()
        return removed
    }

    public func restore(_ note: Note) {
        notes.append(note)
        save()
    }

    /// A note the user left with no text goes away.
    public func discardIfEmpty(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }), note.isEmpty else { return }
        delete(id)
    }

    /// The newest, if a hand edit left two.
    public func dayNote(_ day: String) -> Note? {
        notes.filter { $0.day == day }.max { $0.updated < $1.updated }
    }

    public func setDayNote(_ day: String, _ text: String, now: Date = Date()) {
        setAttached(dayNote(day), text, now: now) { Note(day: day, created: now) }
    }

    public func taskNote(_ taskID: UUID) -> Note? {
        notes.filter { $0.taskID == taskID }.max { $0.updated < $1.updated }
    }

    public func setTaskNote(_ taskID: UUID, _ text: String, now: Date = Date()) {
        setAttached(taskNote(taskID), text, now: now) { Note(taskID: taskID, created: now) }
    }

    /// For the note icon on task rows: one set per draw, not one search per row.
    public var taskIDsWithNotes: Set<UUID> {
        Set(notes.compactMap { $0.isEmpty ? nil : $0.taskID })
    }

    /// Makes the note on the first text, changes it, and deletes it when the text is emptied.
    private func setAttached(_ existing: Note?, _ text: String, now: Date, make: () -> Note) {
        let blank = text.allSatisfy(\.isWhitespace)
        if let existing {
            if blank { delete(existing.id) } else { setText(existing.id, text, now: now) }
        } else if !blank {
            var note = make()
            note.text = String(text.prefix(Note.maxLength))
            notes.append(note)
            save()
        }
    }

    // ponytail: saves the whole file on each change; debounce if notes ever reach megabytes.
    private func save() {
        file.save(notes.filter { !$0.isEmpty })
    }
}

extension Array where Element == Note {
    /// Free and day notes that contain `query`, case and diacritics ignored, newest edit first.
    /// An empty query matches them all. Task notes stay with their tasks.
    public func matching(_ query: String) -> [Note] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return filter { note in
            note.taskID == nil && !note.isEmpty
                && (query.isEmpty || note.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
        .sorted { $0.updated > $1.updated }
    }
}
