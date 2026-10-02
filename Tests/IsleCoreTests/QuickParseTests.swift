import Foundation
import Testing
@testable import IsleCore

private func p(_ s: String) -> Parsed { QuickParse.parse(s, now: now, calendar: cal) }

@Test func timeOnly() {
    #expect(p("get groceries 5pm") == Parsed(title: "get groceries", minute: 1020))
    #expect(p("standup 9 am") == Parsed(title: "standup", minute: 540))
    #expect(p("gym 5:30") == Parsed(title: "gym", minute: 1050))
    #expect(p("deploy 17:00") == Parsed(title: "deploy", minute: 1020))
    #expect(p("sleep 12am") == Parsed(title: "sleep", minute: 0))
}

@Test func bareHourNeedsAt() {
    #expect(p("gym at 7") == Parsed(title: "gym", minute: 420))
    #expect(p("dinner at 6") == Parsed(title: "dinner", minute: 1080))
    #expect(p("lunch @12") == Parsed(title: "lunch", minute: 720))
    #expect(p("lunch at noon") == Parsed(title: "lunch", minute: 720))
}

@Test func dayWords() {
    #expect(p("call mom tomorrow") == Parsed(title: "call mom", day: "2026-10-03"))
    #expect(p("call mom tmr") == Parsed(title: "call mom", day: "2026-10-03"))
    #expect(p("call mom tomorrow at 5pm") == Parsed(title: "call mom", day: "2026-10-03", minute: 1020))
    #expect(p("dentist fri 3:30pm") == Parsed(title: "dentist", day: "2026-10-09", minute: 930))
    #expect(p("pay rent on monday") == Parsed(title: "pay rent", day: "2026-10-05"))
    #expect(p("report due tomorrow") == Parsed(title: "report", day: "2026-10-03"))
}

@Test func namedTimes() {
    #expect(p("movie tonight") == Parsed(title: "movie", day: "2026-10-02", minute: 1200))
    #expect(p("movie tonight 9pm") == Parsed(title: "movie", day: "2026-10-02", minute: 1260))
    #expect(p("run tomorrow morning") == Parsed(title: "run", day: "2026-10-03", minute: 540))
    #expect(p("call this evening") == Parsed(title: "call", minute: 1080))
}

@Test func relativeAndCalendarDays() {
    #expect(p("renew passport in 3 days").day == "2026-10-05")
    #expect(p("review in 2 weeks").day == "2026-10-16")
    #expect(p("review next week").day == "2026-10-05")
    #expect(p("hike this weekend").day == "2026-10-03")
    #expect(p("submit report oct 12").day == "2026-10-12")
    #expect(p("taxes 30 apr").day == "2027-04-30")
    #expect(p("anniversary sep 1st").day == "2027-09-01")
}

@Test func titleWordsSurvive() {
    for s in ["Monday night football", "read 1984", "finish chapter 3", "call tom", "call tod", "look at",
              "Saturday", "x feb 30", "pay rent on", "buy 2 eggs"] {
        #expect(p(s) == Parsed(title: s), "\(s)")
    }
    #expect(p("read this 5pm") == Parsed(title: "read this", minute: 1020))
    #expect(p("groceries, tomorrow") == Parsed(title: "groceries", day: "2026-10-03"))
}

@Test func planFillsFromTheBucket() {
    func plan(_ s: String, _ b: Bucket) -> Parsed { QuickParse.plan(s, bucket: b, now: now, calendar: cal) }
    #expect(plan("read", .today) == Parsed(title: "read", day: "2026-10-02"))
    #expect(plan("read", .upcoming) == Parsed(title: "read", day: "2026-10-03"))
    #expect(plan("read", .backlog) == Parsed(title: "read"))
    #expect(plan("read 5pm", .backlog) == Parsed(title: "read", day: "2026-10-02", minute: 1020))
    #expect(plan("read 5pm", .upcoming) == Parsed(title: "read", day: "2026-10-03", minute: 1020))
    #expect(plan("read fri", .backlog) == Parsed(title: "read", day: "2026-10-09"))
}

@Test func whenReadsAPhrase() throws {
    let w = try #require(QuickParse.when("fri 4pm", now: now, calendar: cal))
    #expect(w.day == "2026-10-09")
    #expect(w.minute == 960)
    #expect(QuickParse.when("banana", now: now, calendar: cal) == nil)
}

@Test func formats() {
    #expect(Format.time(17 * 60, calendar: cal).hasPrefix("5:00"))
    #expect(Format.time(17 * 60, calendar: cal).hasSuffix("PM"))
    #expect(Format.time(17 * 60 + 30, compact: true, calendar: cal) == "5:30")
    #expect(Format.day("2026-10-02", now: now, calendar: cal) == "Today")
    #expect(Format.day("2026-10-03", now: now, calendar: cal) == "Tomorrow")
    #expect(Format.day("2026-10-01", now: now, calendar: cal) == "Yesterday")
    #expect(Format.day("2026-10-06", now: now, calendar: cal) == "Tuesday")
    #expect(Format.day("2026-10-20", now: now, calendar: cal) == "Tue, Oct 20")
    #expect(Format.when(day: nil, minute: nil, now: now, calendar: cal) == "Backlog")
}

@Test func hugeCountsDoNotParseOrCrash() {
    #expect(p("x in 2000000000000000000 w") == Parsed(title: "x in 2000000000000000000 w"))
    #expect(p("x in 3000000 days") == Parsed(title: "x in 3000000 days"))
    #expect(p("x in 999 days").day == "2029-06-27")
}

/// A chip writes words into the add field. Those words must read back as the same day and time.
@Test func phraseRoundTrips() throws {
    for ahead in 0...45 {
        let day = Day.adding(ahead, to: "2026-10-02", cal)
        for minute in [nil, 0, 540, 720, 765, 1020, 1439] as [Int?] {
            let words = QuickParse.phrase(day: day, minute: minute, now: now, calendar: cal)
            let back = p("buy milk \(words)")
            #expect(back == Parsed(title: "buy milk", day: day, minute: minute), "\(day) \(String(describing: minute)) → \(words)")
        }
    }
    #expect(QuickParse.phrase(day: nil, minute: 1050, now: now, calendar: cal) == "5:30pm")
    #expect(QuickParse.phrase(day: "2026-10-03", minute: nil, now: now, calendar: cal) == "tomorrow")
    #expect(QuickParse.phrase(day: nil, minute: nil, now: now, calendar: cal) == "")
}
