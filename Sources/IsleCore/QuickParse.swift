import Foundation

/// The list the user is looking at. It decides where a task with no date goes.
public enum Bucket: Int, CaseIterable, Sendable {
    case today, upcoming, backlog
}

public struct Parsed: Equatable, Sendable {
    public var title: String
    public var day: String?
    public var minute: Int?

    public init(title: String, day: String? = nil, minute: Int? = nil) {
        self.title = title
        self.day = day
        self.minute = minute
    }
}

/// Reads a date and a time from the trailing words of a task:
/// "dentist fri 3:30pm" → "dentist", next Friday, 15:30.
/// Only trailing words count, so "Monday night football" stays a title.
public enum QuickParse {
    public static func parse(_ text: String, now: Date, calendar cal: Calendar = .current) -> Parsed {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        // The longest trailing run that reads fully as a date wins. The first word never
        // counts, so a task is never only date words ("Saturday" stays a title).
        for start in words.indices.dropFirst() {
            guard let w = read(words[start...].map { $0.lowercased() }, now: now, cal: cal) else { continue }
            let title = words[..<start].joined(separator: " ").trimmingCharacters(in: junk)
            if !title.isEmpty { return Parsed(title: title, day: w.day, minute: w.minute) }
        }
        return Parsed(title: words.joined(separator: " "))
    }

    /// Reads a phrase of only date and time words, like "fri 4pm". Nil if a word is unknown.
    public static func when(_ phrase: String, now: Date, calendar cal: Calendar = .current) -> (day: String?, minute: Int?)? {
        read(phrase.lowercased().split(whereSeparator: \.isWhitespace).map(String.init), now: now, cal: cal)
    }

    /// Parses, then fills what the text did not say from the bucket.
    /// A time with no day means today (tomorrow on Upcoming).
    public static func plan(_ text: String, bucket: Bucket, now: Date, calendar cal: Calendar = .current) -> Parsed {
        var p = parse(text, now: now, calendar: cal)
        if p.day == nil && (p.minute != nil || bucket != .backlog) {
            let today = Day.key(now, cal)
            p.day = bucket == .upcoming ? Day.adding(1, to: today, cal) : today
        }
        return p
    }

    /// A day plan: one task for each line that has a title, in order, as if typed on Today.
    public static func planLines(_ lines: [String], now: Date, calendar cal: Calendar = .current) -> [Parsed] {
        lines.map { plan(dropMarker($0), bucket: .today, now: now, calendar: cal) }.filter { !$0.title.isEmpty }
    }

    /// Removes one list marker that people type from habit: "- ", "* ", "• ", "1. ", "2) ", "[ ] ".
    static func dropMarker(_ line: String) -> String {
        line.replacing(#/^\s*(?:[-*•]|\d{1,3}[.)]|\[\s?\])(?:\s+|$)/#, with: "", maxReplacements: 1)
    }

    /// The words that `parse` reads back as `day` and `minute`, like "tomorrow 5:30pm".
    /// A chip writes them into the add field, so the field always shows what the task will get.
    public static func phrase(day: String?, minute: Int?, now: Date, calendar cal: Calendar = .current) -> String {
        var words: [String] = []
        if let day, let date = Day.date(day, cal), let today = Day.date(Day.key(now, cal), cal) {
            switch cal.dateComponents([.day], from: today, to: date).day ?? 0 {
            case 0: words.append("today")
            case 1: words.append("tomorrow")
            case 2...6: words.append(weekdayNames[cal.component(.weekday, from: date) - 1])
            default: words.append("\(monthNames[cal.component(.month, from: date) - 1]) \(cal.component(.day, from: date))")
            }
        }
        if let minute {
            let h = minute / 60, m = minute % 60
            let hour = h % 12 == 0 ? 12 : h % 12
            let ampm = h < 12 ? "am" : "pm"
            words.append(m == 0 ? "\(hour)\(ampm)" : String(format: "%d:%02d%@", hour, m, ampm))
        }
        return words.joined(separator: " ")
    }

    private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    private static let junk = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;:-–—"))
    private static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "weds": 4, "wednesday": 4, "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6, "sat": 7, "saturday": 7,
    ]
    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
        "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]
    /// Soft times: an explicit time in the same phrase wins.
    private static let dayParts = ["morning": 540, "noon": 720, "afternoon": 900, "evening": 1080]
    private static let units = ["day": 1, "days": 1, "d": 1, "week": 7, "weeks": 7, "w": 7, "wk": 7, "wks": 7]

    static func read(_ raw: [String], now: Date, cal: Calendar) -> (day: String?, minute: Int?)? {
        let t = raw.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",.;!?")) }
        let today = Day.key(now, cal)
        var day: String?, minute: Int?, soft: Int?
        var afterAt = false
        var i = 0

        func number(_ s: String?) -> Int? {
            guard let s else { return nil }
            return Int(s.replacingOccurrences(of: "(st|nd|rd|th)$", with: "", options: .regularExpression))
        }

        while i < t.count {
            let w = t[i]
            let n1 = i + 1 < t.count ? t[i + 1] : nil
            let n2 = i + 2 < t.count ? t[i + 2] : nil
            let bare = afterAt
            var used = 1
            var newDay: String?
            var newMinute: Int?
            afterAt = false

            switch w {
            case "today":
                newDay = today
            case "tonight":
                newDay = today
                soft = soft ?? 1200
            case "tomorrow", "tmr", "tmrw", "tomorow":
                newDay = Day.adding(1, to: today, cal)
            case "weekend":
                newDay = Day.weekend(after: now, cal)
            case "next" where n1 == "week":
                newDay = Day.next(weekday: 2, after: now, cal)
                used = 2
            // Counts stop at 999, so a long number cannot overflow.
            case "in" where (1...999).contains(number(n1) ?? 0) && units[n2 ?? ""] != nil:
                newDay = Day.adding(number(n1)! * units[n2!]!, to: today, cal)
                used = 3
            // Fillers count only in front of the word they introduce.
            case "at", "@":
                guard let n = n1, time(n, bare: true) != nil || dayParts[n] != nil else { return nil }
                afterAt = true
            case "this":
                guard let n = n1, dayParts[n] != nil || weekdays[n] != nil || n == "weekend" else { return nil }
            case "next":
                guard let n = n1, weekdays[n] != nil else { return nil }
            case "on":
                guard let n = n1, weekdays[n] != nil || months[n] != nil || number(n) != nil else { return nil }
            case "by", "due":
                guard n1 != nil else { return nil }
            default:
                if let wd = weekdays[w] {
                    newDay = Day.next(weekday: wd, after: now, cal)
                } else if let mo = months[w], let d = number(n1) {
                    guard let key = monthDay(mo, d, now, cal) else { return nil }
                    newDay = key
                    used = 2
                } else if let d = number(w), let n = n1, let mo = months[n] {
                    guard let key = monthDay(mo, d, now, cal) else { return nil }
                    newDay = key
                    used = 2
                } else if let n = n1, n == "am" || n == "pm", let m = time(w + n, bare: false) {
                    newMinute = m
                    used = 2
                } else if let part = dayParts[w] {
                    soft = soft ?? part
                } else if let m = time(w, bare: bare) {
                    newMinute = m
                } else {
                    return nil
                }
            }
            if let newDay {
                guard day == nil else { return nil }
                day = newDay
            }
            if let newMinute {
                guard minute == nil else { return nil }
                minute = newMinute
            }
            i += used
        }
        guard day != nil || minute != nil || soft != nil else { return nil }
        return (day, minute ?? soft)
    }

    /// "5pm", "5:30pm", "5p", "17:00", "5:30". A bare "5" only after "at" or as "@5".
    /// With no am/pm, hours 1–6 mean PM.
    static func time(_ word: String, bare: Bool) -> Int? {
        var s = Substring(word)
        var bare = bare
        if s.hasPrefix("@") {
            s = s.dropFirst()
            bare = true
        }
        guard let m = s.wholeMatch(of: #/(\d{1,2})(?::(\d{2}))?(am|pm|a|p)?/#) else { return nil }
        var h = Int(m.1)!
        let min = m.2.map { Int($0)! } ?? 0
        guard min < 60 else { return nil }
        if let ap = m.3 {
            guard (1...12).contains(h) else { return nil }
            h = h % 12 + (ap.hasPrefix("p") ? 12 : 0)
        } else if m.2 != nil {
            guard h < 24 else { return nil }
            if (1...6).contains(h) { h += 12 }
        } else {
            guard bare, (1...12).contains(h) else { return nil }
            if h <= 6 { h += 12 }
        }
        return h * 60 + min
    }

    /// This year's date, or next year's if it passed. Nil for dates like Feb 30.
    static func monthDay(_ month: Int, _ d: Int, _ now: Date, _ cal: Calendar) -> String? {
        let today = Day.key(now, cal)
        let year = cal.component(.year, from: now)
        for y in [year, year + 1] {
            guard let date = cal.date(from: DateComponents(year: y, month: month, day: d)),
                  cal.component(.day, from: date) == d else { return nil }
            let key = Day.key(date, cal)
            if key >= today { return key }
        }
        return nil
    }
}
