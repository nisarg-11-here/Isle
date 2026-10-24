import Foundation
import Testing
@testable import IsleCore

private func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: now)! }

@Test func asksOncePerDayInTheWindowWhenTheUserIsThere() {
    #expect(Morning.shouldAsk(now: now, askedDay: nil, idleSeconds: 5, calendar: cal))
    #expect(Morning.shouldAsk(now: now, askedDay: "2026-10-01", idleSeconds: 30, calendar: cal))
    #expect(!Morning.shouldAsk(now: now, askedDay: "2026-10-02", idleSeconds: 5, calendar: cal))
    #expect(!Morning.shouldAsk(now: now, askedDay: nil, idleSeconds: 31, calendar: cal))
    #expect(!Morning.shouldAsk(now: at(4, 59), askedDay: nil, idleSeconds: 0, calendar: cal))
    #expect(Morning.shouldAsk(now: at(5, 0), askedDay: nil, idleSeconds: 0, calendar: cal))
    #expect(Morning.shouldAsk(now: at(17, 59), askedDay: nil, idleSeconds: 0, calendar: cal))
    #expect(!Morning.shouldAsk(now: at(18, 0), askedDay: nil, idleSeconds: 0, calendar: cal))
}

@Test func greetingFollowsTheClock() {
    #expect(Morning.greeting(at(9, 0), calendar: cal) == "Good morning")
    #expect(Morning.greeting(now, calendar: cal) == "Good afternoon")
    #expect(Morning.greeting(at(17, 0), calendar: cal) == "Good evening")
}
