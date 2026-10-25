import Foundation

/// Shanghai A-share continuous trading sessions; scheduler uses half-open intervals.
/// Calendar source: https://www.sse.com.cn/disclosure/announcement/general/c/c_20251222_10802507.shtml
public enum TradingSchedule {
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private static let holidays2026: Set<String> = {
        let ranges: [(Int, ClosedRange<Int>)] = [(1, 1...3), (2, 15...23), (4, 4...6), (5, 1...5), (6, 19...21), (9, 25...27), (10, 1...7)]
        return Set(ranges.flatMap { month, days in days.map { String(format: "2026-%02d-%02d", month, $0) } })
    }()
    public static func isCalendarSupported(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite && calendar.component(.year, from: date) == 2026
    }
    public static func isTradingDay(_ date: Date) -> Bool {
        guard isCalendarSupported(date) else { return false }
        return (2...6).contains(calendar.component(.weekday, from: date)) && !holidays2026.contains(MarketClock.day(date))
    }
    private static func sessions(_ date: Date) -> [(Date, Date)] {
        guard isTradingDay(date) else { return [] }
        let day = calendar.startOfDay(for: date)
        return [(570, 690), (780, 900)].map { start, end in
            (day.addingTimeInterval(Double(start * 60)), day.addingTimeInterval(Double(end * 60)))
        }
    }
    public static func isOpen(_ date: Date) -> Bool {
        sessions(date).contains { date >= $0.0 && date < $0.1 }
    }
    /// Closing boundaries wake the app to change its display and schedule the next open,
    /// without sending another quote request. Unsupported calendars deliberately pause.
    public static func nextWake(after date: Date, interval: Int) -> Date? {
        guard isCalendarSupported(date) else { return nil }
        for (start, end) in sessions(date) {
            if date < start { return start }
            if date < end { return min(date.addingTimeInterval(Double(max(5, min(300, interval)))), end) }
        }
        for offset in 1...370 {
            guard let next = calendar.date(byAdding: .day, value: offset, to: date), isCalendarSupported(next) else { return nil }
            if let open = sessions(next).first?.0 { return open }
        }
        return nil
    }
}
