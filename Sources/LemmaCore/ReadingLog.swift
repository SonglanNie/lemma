import Foundation

/// Time spent reading, per page and per day, recorded while the reader window is in front and in use.
/// It powers the reading-progress shading in the overview ruler, chapter progress in the outline and the
/// week's reading time on the welcome page. Nothing leaves the Mac.
public struct ReadingLog: Codable, Equatable, Sendable {
    /// Seconds per physical page index. Stored with string keys, as JSON objects require.
    public var pageSeconds: [String: Double] = [:]
    /// Seconds per local calendar day, “2026-10-01”.
    public var daySeconds: [String: Double] = [:]
    public var lastReadAt: Date?

    public init() {}

    /// A page counts as read after this much attention.
    public static let readThreshold: Double = 20

    public func seconds(onPage pageIndex: Int) -> Double { pageSeconds[String(pageIndex)] ?? 0 }
    public func isRead(_ pageIndex: Int) -> Bool { seconds(onPage: pageIndex) >= Self.readThreshold }

    public mutating func record(_ seconds: Double, onPage pageIndex: Int, at date: Date = .now, calendar: Calendar = .current) {
        guard seconds > 0, seconds < 600 else { return }
        pageSeconds[String(pageIndex), default: 0] += seconds
        daySeconds[Self.dayKey(date, calendar: calendar), default: 0] += seconds
        lastReadAt = date
    }

    /// Pages read (above the threshold) among `range`.
    public func readCount(in range: Range<Int>) -> Int {
        pageSeconds.reduce(0) { total, item in
            guard let page = Int(item.key), range.contains(page), item.value >= Self.readThreshold else { return total }
            return total + 1
        }
    }

    public var totalSeconds: Double { daySeconds.values.reduce(0, +) }
    public var pagesRead: Int { pageSeconds.values.filter { $0 >= Self.readThreshold }.count }

    public func seconds(on date: Date, calendar: Calendar = .current) -> Double { daySeconds[Self.dayKey(date, calendar: calendar)] ?? 0 }

    /// The last `count` days, oldest first, including days without reading.
    public func days(_ count: Int, endingAt date: Date = .now, calendar: Calendar = .current) -> [(date: Date, seconds: Double)] {
        let today = calendar.startOfDay(for: date)
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, seconds(on: day, calendar: calendar))
        }
    }

    /// Consecutive days with at least a minute of reading, ending today (or yesterday, if today has none yet).
    public func streak(endingAt date: Date = .now, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: date)
        if seconds(on: day, calendar: calendar) < 60, let yesterday = calendar.date(byAdding: .day, value: -1, to: day) { day = yesterday }
        var count = 0
        while seconds(on: day, calendar: calendar) >= 60 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// “1 h 05”, “12 min”, “< 1 min”, for compact places such as the status bar.
    public static func describeShort(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded(.down))
        if minutes < 1 { return seconds > 0 ? "< 1 min" : "0 min" }
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    /// “1 h 05 min”, “12 min”, “40 s”.
    public static func describe(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d min", minutes / 60, minutes % 60)
    }
}

/// Sums reading across several books, for the welcome page.
public enum ReadingSummary {
    public static func days(_ logs: [ReadingLog], count: Int, endingAt date: Date = .now, calendar: Calendar = .current) -> [(date: Date, seconds: Double)] {
        var merged = ReadingLog()
        for log in logs { for (day, seconds) in log.daySeconds { merged.daySeconds[day, default: 0] += seconds } }
        return merged.days(count, endingAt: date, calendar: calendar)
    }

    public static func streak(_ logs: [ReadingLog], endingAt date: Date = .now, calendar: Calendar = .current) -> Int {
        var merged = ReadingLog()
        for log in logs { for (day, seconds) in log.daySeconds { merged.daySeconds[day, default: 0] += seconds } }
        return merged.streak(endingAt: date, calendar: calendar)
    }
}
