import Foundation

/// One task. `day` nil means backlog. `minute` nil means anytime that day.
public struct Todo: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    /// Local calendar day, "yyyy-MM-dd". Floating, so 5 PM stays 5 PM across time zones.
    public var day: String?
    /// Minutes after midnight.
    public var minute: Int?
    public var doneAt: Date?
    public var created: Date

    public init(id: UUID = UUID(), title: String, day: String? = nil, minute: Int? = nil,
                doneAt: Date? = nil, created: Date = Date()) {
        self.id = id
        self.title = title
        self.day = day
        self.minute = minute
        self.doneAt = doneAt
        self.created = created
    }

    public var isDone: Bool { doneAt != nil }

    /// Open before done, then by day, then timed before anytime, then oldest first.
    public static func order(_ a: Todo, _ b: Todo) -> Bool {
        (a.isDone ? 1 : 0, a.day ?? "", a.minute ?? Int.max, a.created)
            < (b.isDone ? 1 : 0, b.day ?? "", b.minute ?? Int.max, b.created)
    }
}

/// Day keys are "yyyy-MM-dd" strings in local time. String order is date order.
public enum Day {
    public static func key(_ date: Date, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func date(_ key: String, _ cal: Calendar = .current) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    public static func adding(_ days: Int, to key: String, _ cal: Calendar = .current) -> String {
        Self.key(cal.date(byAdding: .day, value: days, to: date(key, cal)!)!, cal)
    }

    /// The next `weekday` (1 = Sunday … 7 = Saturday) strictly after the day of `now`.
    public static func next(weekday: Int, after now: Date, _ cal: Calendar = .current) -> String {
        let ahead = (weekday - cal.component(.weekday, from: now) + 7) % 7
        return adding(ahead == 0 ? 7 : ahead, to: key(now, cal), cal)
    }

    /// Saturday of this weekend: today on a Saturday, else the next Saturday.
    public static func weekend(after now: Date, _ cal: Calendar = .current) -> String {
        cal.component(.weekday, from: now) == 7 ? key(now, cal) : next(weekday: 7, after: now, cal)
    }

    public static func minute(of date: Date, _ cal: Calendar = .current) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return c.hour! * 60 + c.minute!
    }
}
