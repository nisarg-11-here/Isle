import Foundation
import Testing
@testable import IsleCore

@Test func todaySplitsOverdueTimedAnytimeDone() throws {
    let list = [
        todo("old open", "2026-09-30"),
        todo("old done before", "2026-09-30", doneAt: now.addingTimeInterval(-86_400)),
        todo("old done today", "2026-10-01", doneAt: now),
        todo("soon", "2026-10-02", 1020),
        todo("late", "2026-10-02", 600),
        todo("anytime", "2026-10-02"),
        todo("done today", "2026-10-02", 700, doneAt: now),
        todo("tomorrow", "2026-10-03"),
        todo("someday", nil),
    ]
    let s = list.todaySections(now, cal)
    #expect(s.overdue.map(\.title) == ["old open"])
    #expect(s.timed.map(\.title) == ["late", "soon"])
    #expect(s.anytime.map(\.title) == ["anytime"])
    #expect(s.done.map(\.title) == ["old done today", "done today"])
    #expect(list.progress(now, cal) == DayProgress(done: 2, total: 6))
    #expect(try #require(list.nextTimed(now, cal)).title == "soon")
}

@Test func dueNowCoversTheLastFiveMinutes() {
    let list = [765, 766, 770, 771].map { (m: Int) in todo("t\(m)", "2026-10-02", m) }
    #expect(list.dueNow(now, cal).map(\.minute) == [766, 770])
}

@Test func upcomingGroupsByDay() {
    let list = [
        todo("b anytime", "2026-10-05"),
        todo("b timed", "2026-10-05", 600),
        todo("a", "2026-10-03"),
        todo("today", "2026-10-02"),
        todo("someday", nil),
    ]
    let groups = list.upcoming(now, cal)
    #expect(groups.map(\.day) == ["2026-10-03", "2026-10-05"])
    #expect(groups[1].items.map(\.title) == ["b timed", "b anytime"])
}

@Test func backlogNewestFirstThenDoneToday() {
    let list = [
        todo("older", nil, age: 100),
        todo("newer", nil, age: 10),
        todo("done today", nil, doneAt: now),
        todo("done before", nil, doneAt: now.addingTimeInterval(-86_400)),
        todo("planned", "2026-10-02"),
    ]
    #expect(list.backlog(now, cal).map(\.title) == ["newer", "older", "done today"])
}

@Test func midnightTurnsOpenTasksOverdue() {
    let list = [todo("carry", "2026-10-02", 1020)]
    #expect(list.todaySections(now.addingTimeInterval(86_400), cal).overdue.map(\.title) == ["carry"])
}

@Test func dayHelpers() {
    #expect(Day.key(now, cal) == "2026-10-02")
    #expect(Day.adding(30, to: "2026-10-02", cal) == "2026-11-01")
    #expect(Day.next(weekday: 6, after: now, cal) == "2026-10-09")  // Friday → next Friday
    #expect(Day.next(weekday: 2, after: now, cal) == "2026-10-05")
    #expect(Day.weekend(after: now, cal) == "2026-10-03")
    #expect(Day.minute(of: now, cal) == 770)
}

@Test func aTimedTaskIsSoonWithinTheHour() {
    // `now` is 12:50 (minute 770).
    #expect([todo("standup", "2026-10-02", 800)].timedSoon(now, cal))
    #expect([todo("standup", "2026-10-02", 830)].timedSoon(now, cal))
    #expect(![todo("standup", "2026-10-02", 831)].timedSoon(now, cal))
    #expect(![todo("anytime", "2026-10-02")].timedSoon(now, cal))
    #expect(![todo("done", "2026-10-02", 800, doneAt: now)].timedSoon(now, cal))
    #expect(![todo("tomorrow", "2026-10-03", 780)].timedSoon(now, cal))
    #expect(![todo("past", "2026-10-02", 700)].timedSoon(now, cal))
}
