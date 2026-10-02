import Foundation

public enum Format {
    /// "5:00 PM", or "17:00" in a 24-hour locale. Compact drops the AM/PM marker: "5:00".
    public static func time(_ minute: Int, compact: Bool = false, calendar cal: Calendar = .current) -> String {
        let f = formatter(cal, "j:mm")
        if compact {
            f.dateFormat = f.dateFormat.replacingOccurrences(of: "a", with: "").trimmingCharacters(in: .whitespaces)
        }
        let date = cal.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: minute / 60, minute: minute % 60))!
        return f.string(from: date)
    }

    /// "Today", "Tomorrow", "Yesterday", a weekday name within the week, else "Tue, Oct 20".
    public static func day(_ key: String, now: Date, calendar cal: Calendar = .current) -> String {
        let today = Day.key(now, cal)
        if key == today { return "Today" }
        if key == Day.adding(1, to: today, cal) { return "Tomorrow" }
        if key == Day.adding(-1, to: today, cal) { return "Yesterday" }
        guard let date = Day.date(key, cal), let base = Day.date(today, cal) else { return key }
        let ahead = cal.dateComponents([.day], from: base, to: date).day ?? 0
        let template = (2...6).contains(ahead) ? "EEEE" : key.prefix(4) == today.prefix(4) ? "EEEMMMd" : "MMMdyyyy"
        return formatter(cal, template).string(from: date)
    }

    /// "Backlog", "Tomorrow", or "Fri, Oct 9 · 3:00 PM".
    public static func when(day: String?, minute: Int?, now: Date, calendar cal: Calendar = .current) -> String {
        guard let day else { return "Backlog" }
        let d = self.day(day, now: now, calendar: cal)
        guard let minute else { return d }
        return "\(d) · \(time(minute, calendar: cal))"
    }

    private static func formatter(_ cal: Calendar, _ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = cal
        f.locale = cal.locale
        f.timeZone = cal.timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
}
