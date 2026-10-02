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
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let todo = Todo(title: title, day: day, minute: day == nil ? nil : minute)
        todos.append(todo)
        save()
        return todo
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

    public func restore(_ todo: Todo) {
        todos.append(todo)
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            todos = try Self.decoder.decode([Todo].self, from: Data(contentsOf: url))
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
