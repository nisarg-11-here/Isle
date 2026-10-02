import Foundation
@testable import IsleCore

let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Regina")!
    c.locale = Locale(identifier: "en_US")
    return c
}()

/// Friday, 2026-10-02 at 12:50.
let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12, minute: 50))!

func todo(_ title: String, _ day: String?, _ minute: Int? = nil, doneAt: Date? = nil, age: Double = 0) -> Todo {
    Todo(title: title, day: day, minute: minute, doneAt: doneAt, created: now.addingTimeInterval(-age))
}
