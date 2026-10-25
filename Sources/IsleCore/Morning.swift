import Foundation

/// When the island asks the user to plan the day, and how it greets them.
public enum Morning {
    /// 5:00 AM. Earlier is still last night.
    public static let start = 5 * 60
    /// 6:00 PM. A first use after this is not the start of a day.
    public static let end = 18 * 60
    /// Seconds since the last key or mouse input. More means nobody is at the Mac.
    public static let maxIdle: Double = 30

    /// Once a day, inside the window, and only when the user is at the Mac.
    public static func shouldAsk(now: Date, askedDay: String?, idleSeconds: Double,
                                 calendar cal: Calendar = .current) -> Bool {
        let minute = Day.minute(of: now, cal)
        return askedDay != Day.key(now, cal) && (start..<end).contains(minute) && idleSeconds <= maxIdle
    }

    public static func greeting(_ now: Date, calendar cal: Calendar = .current) -> String {
        switch Day.minute(of: now, cal) {
        case ..<(12 * 60): "Good morning"
        case ..<(17 * 60): "Good afternoon"
        default: "Good evening"
        }
    }
}
