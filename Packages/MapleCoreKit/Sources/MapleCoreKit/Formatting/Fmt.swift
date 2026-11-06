import Foundation

/// Display formatting used across the app. Canadian English: "$1,808.00", "9:40 AM".
public enum Fmt {
    public static let locale = Locale(identifier: "en_CA")

    // MARK: Money

    public static func money(_ value: Decimal) -> String {
        value.formatted(.currency(code: "CAD").locale(locale).presentation(.narrow))
    }

    public static func moneyWhole(_ value: Decimal) -> String {
        value.formatted(.currency(code: "CAD").locale(locale).presentation(.narrow).precision(.fractionLength(0)))
    }

    public static func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    public static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    // MARK: Dates

    private static func style(_ base: Date.FormatStyle) -> Date.FormatStyle {
        var s = base
        s.locale = locale
        s.timeZone = .current
        return s
    }

    /// "9:40 AM"
    public static func time(_ date: Date) -> String {
        date.formatted(style(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute()))
            .replacingOccurrences(of: "a.m.", with: "AM").replacingOccurrences(of: "p.m.", with: "PM")
    }

    /// "9:40" — no AM/PM, for dense rows where context is obvious.
    public static func clock(_ date: Date) -> String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date) % 12
        let m = cal.component(.minute, from: date)
        return String(format: "%d:%02d", h == 0 ? 12 : h, m)
    }

    /// "10:14:52 AM"
    public static func timeWithSeconds(_ date: Date) -> String {
        date.formatted(style(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute().second()))
            .replacingOccurrences(of: "a.m.", with: "AM").replacingOccurrences(of: "p.m.", with: "PM")
    }

    /// "Monday, October 26"
    public static func longDay(_ date: Date) -> String {
        date.formatted(style(Date.FormatStyle().weekday(.wide).month(.wide).day()))
    }

    /// "Tue, Oct 27"
    public static func shortDay(_ date: Date) -> String {
        date.formatted(style(Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()))
            .replacingOccurrences(of: ".", with: "")
    }

    /// "Oct 19"
    public static func shortDate(_ date: Date) -> String {
        date.formatted(style(Date.FormatStyle().month(.abbreviated).day()))
            .replacingOccurrences(of: ".", with: "")
    }

    /// "October 2026"
    public static func monthYear(_ date: Date) -> String {
        date.formatted(style(Date.FormatStyle().month(.wide).year()))
    }

    /// "Mon"
    public static func weekdayShort(_ date: Date) -> String {
        date.formatted(style(Date.FormatStyle().weekday(.abbreviated))).replacingOccurrences(of: ".", with: "")
    }

    /// Inbox-style stamp: "9:12" today, "Yesterday", "Fri" this week, else "Oct 19".
    public static func stamp(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return clock(date) }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: date, to: now).day, days < 7 { return weekdayShort(date) }
        return shortDate(date)
    }

    /// "Today", "Yesterday", "Tomorrow" or "Tue, Oct 27".
    public static func relativeDay(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return "Today" }
        if let d = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: d) { return "Yesterday" }
        if let d = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: d) { return "Tomorrow" }
        return shortDay(date)
    }

    /// "12 min ago", "just now", "2 h ago"
    public static func ago(_ date: Date, now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h ago" }
        return shortDate(date)
    }

    // MARK: Durations

    /// "45 min", "1 h 10 min", "6 h"
    public static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "2 h 01 m", "37 m"
    public static func compactDuration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) m" }
        return String(format: "%d h %02d m", minutes / 60, minutes % 60)
    }

    /// "2 h 38 m"
    public static func shiftDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        return "\(minutes / 60) h \(minutes % 60) m"
    }

    /// Timer face: "42:18", "1:24:07".
    public static func timer(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Always three fields: "00:42:18".
    public static func timerLong(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// For VoiceOver: "42 minutes 18 seconds".
    public static func spokenDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if m > 0 || h > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        parts.append("\(s) second\(s == 1 ? "" : "s")")
        return parts.joined(separator: " ")
    }

    /// "18.4 MB"
    public static func bytes(_ count: Int) -> String {
        let mb = Double(count) / 1_000_000
        return mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%d KB", max(1, count / 1000))
    }

    public static func plural(_ count: Int, _ singular: String, _ pluralForm: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : (pluralForm ?? singular + "s"))"
    }
}
