import Foundation

public struct TodaySections: Equatable {
    public var overdue: [Todo] = []
    public var timed: [Todo] = []
    public var anytime: [Todo] = []
    public var done: [Todo] = []

    public var isEmpty: Bool { overdue.isEmpty && timed.isEmpty && anytime.isEmpty && done.isEmpty }
}

public struct DayGroup: Equatable, Identifiable {
    public let day: String
    public let items: [Todo]
    public var id: String { day }
}

public struct DayProgress: Equatable {
    public let done: Int
    public let total: Int
}

extension Array where Element == Todo {
    public func todaySections(_ now: Date, _ cal: Calendar = .current) -> TodaySections {
        let today = Day.key(now, cal)
        let items = filter { todo in
            guard let day = todo.day else { return false }
            if day == today { return true }
            // Overdue: an older day that is still open, or that was done today.
            return day < today && (todo.doneAt.map { done in Day.key(done, cal) == today } ?? true)
        }.sorted(by: Todo.order)
        let open = items.filter { !$0.isDone }
        return TodaySections(
            overdue: open.filter { $0.day! < today },
            timed: open.filter { $0.day == today && $0.minute != nil },
            anytime: open.filter { $0.day == today && $0.minute == nil },
            done: items.filter(\.isDone))
    }

    public func upcoming(_ now: Date, _ cal: Calendar = .current) -> [DayGroup] {
        let today = Day.key(now, cal)
        let items = filter { ($0.day ?? "") > today }.sorted(by: Todo.order)
        return Dictionary(grouping: items) { $0.day! }
            .sorted { $0.key < $1.key }
            .map { DayGroup(day: $0.key, items: $0.value) }
    }

    public func backlog(_ now: Date, _ cal: Calendar = .current) -> [Todo] {
        let today = Day.key(now, cal)
        let items = filter { todo in
            todo.day == nil && (todo.doneAt.map { done in Day.key(done, cal) == today } ?? true)
        }
        return items.filter { !$0.isDone }.sorted { $0.created > $1.created } + items.filter(\.isDone)
    }

    public func progress(_ now: Date, _ cal: Calendar = .current) -> DayProgress {
        let s = todaySections(now, cal)
        return DayProgress(done: s.done.count, total: s.overdue.count + s.timed.count + s.anytime.count + s.done.count)
    }

    /// The first open timed task today at or after now.
    public func nextTimed(_ now: Date, _ cal: Calendar = .current) -> Todo? {
        let m = Day.minute(of: now, cal)
        return todaySections(now, cal).timed.first { $0.minute! >= m }
    }

    /// True when the next open timed task today is at most `minutes` away.
    public func timedSoon(_ now: Date, within minutes: Int = 60, _ cal: Calendar = .current) -> Bool {
        guard let minute = nextTimed(now, cal)?.minute else { return false }
        return minute - Day.minute(of: now, cal) <= minutes
    }

    /// Open timed tasks today whose time is in the last 5 minutes, now included.
    public func dueNow(_ now: Date, _ cal: Calendar = .current) -> [Todo] {
        let m = Day.minute(of: now, cal)
        return todaySections(now, cal).timed.filter { (m - 4...m).contains($0.minute!) }
    }
}
