import Foundation
import Observation

/// The task list, saved as JSON after each change.
@Observable
public final class TodoStore {
    public private(set) var todos: [Todo] = []
    private let url: URL

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Isle/todos.json")
    }

    public init(url: URL) {
        self.url = url
        load()
    }

    @discardableResult
    public func add(_ title: String, day: String?, minute: Int?) -> Todo? {
        guard let todo = Self.make(title, day: day, minute: minute, created: Date()) else { return nil }
        todos.append(todo)
        save()
        return todo
    }

    /// Adds the tasks in order with one save. Each one is created a second after the one before:
    /// the file keeps whole seconds (`.iso8601`), so closer times would tie on a reload and lose the order.
    @discardableResult
    public func add(_ items: [Parsed], now: Date = Date()) -> [Todo] {
        let start = now.timeIntervalSinceReferenceDate.rounded(.down)
        var added: [Todo] = []
        for item in items {
            let created = Date(timeIntervalSinceReferenceDate: start + Double(added.count))
            if let todo = Self.make(item.title, day: item.day, minute: item.minute, created: created) {
                added.append(todo)
            }
        }
        guard !added.isEmpty else { return [] }
        todos += added
        save()
        return added
    }

    /// A trimmed title, and no time on a task with no day. Nil for an empty title.
    private static func make(_ title: String, day: String?, minute: Int?, created: Date) -> Todo? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return Todo(title: title, day: day, minute: day == nil ? nil : minute, created: created)
    }

    public func update(_ id: UUID, _ change: (inout Todo) -> Void) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        change(&todos[i])
        save()
    }

    public func toggle(_ id: UUID, now: Date = Date()) {
        update(id) { $0.doneAt = $0.doneAt == nil ? now : nil }
    }

    @discardableResult
    public func delete(_ id: UUID) -> Todo? {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = todos.remove(at: i)
        save()
        return removed
    }

    /// Deletes these tasks with one save. Returns the ones it removed.
    @discardableResult
    public func delete(_ ids: Set<UUID>) -> [Todo] {
        let removed = todos.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return [] }
        todos.removeAll { ids.contains($0.id) }
        save()
        return removed
    }

    public func restore(_ todo: Todo) {
        todos.append(todo)
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            todos = try Self.decoder.decode([Todo].self, from: data)
            // One rolling copy of the last file that loaded, so a bad change can be undone by hand.
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".backup.json")
            try? data.write(to: backup, options: .atomic)
        } catch {
            // Keep the unreadable file. A save must never overwrite the user's data.
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("todos.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            NSLog("Isle: could not read \(url.path) (\(error)). Moved it to \(backup.lastPathComponent).")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(todos).write(to: url, options: .atomic)
        } catch {
            NSLog("Isle: could not save \(url.path): \(error)")
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
