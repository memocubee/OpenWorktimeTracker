import Foundation

/// One column of the "last 7 days" chart: a calendar day's Net Work Time,
/// painted with the heatmap's levels so overtime days stand out the same way in
/// both. A day without a Daily Log is still a column, just an empty one.
struct WeekBar: Equatable, Identifiable {
    /// What a column needs from a day's Daily Log.
    struct Log: Equatable {
        let netWorkTime: TimeInterval
        let startTime: Date
        /// `nil` while the Workday is still running.
        let endTime: Date?
    }

    let date: String  // YYYY-MM-DD
    /// `nil` when nobody worked that day.
    let log: Log?
    let level: HeatLevel
    /// Net Work Time past the daily goal; zero at or under it.
    let overtime: TimeInterval
    let isToday: Bool

    var id: String { date }
    var hasLog: Bool { log != nil }
    var netWorkTime: TimeInterval { log?.netWorkTime ?? 0 }
    var netHours: Double { netWorkTime / 3600 }

    init(date: String, log: Log?, scale: HeatScale, today: String) {
        self.date = date
        self.log = log
        let net = log?.netWorkTime ?? 0
        self.level = scale.level(forHours: net / 3600)
        self.overtime = max(0, net - scale.goalHours * 3600)
        self.isToday = date == today
    }

    init(
        date: String, netWorkTime: TimeInterval, startTime: Date, endTime: Date?,
        scale: HeatScale, today: String
    ) {
        self.init(
            date: date, log: Log(netWorkTime: netWorkTime, startTime: startTime, endTime: endTime),
            scale: scale, today: today)
    }

    /// Whole hours and minutes of overtime, or `nil` when under a minute over.
    var overtimeHoursMinutes: (hours: Int, minutes: Int)? {
        let minutes = Int(overtime) / 60
        guard minutes > 0 else { return nil }
        return (minutes / 60, minutes % 60)
    }

    /// The `count` calendar days ending on `today` (YYYY-MM-DD), oldest first.
    static func calendarDays(_ count: Int = 7, endingOn today: String, calendar: Calendar = .current) -> [String] {
        guard count > 0, let end = parser.date(from: today) else { return [] }
        // Noon keeps day arithmetic clear of DST transitions around midnight.
        let anchor = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: end) ?? end
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: anchor).map(TimeEntry.dateString(from:))
        }
    }

    /// The last seven calendar days ending on the effective day of `now`
    /// (before `newDayStartHour` still counts as yesterday), oldest first.
    /// Days `log` has nothing for become empty columns.
    static func lastSevenDays(
        now: Date, newDayStartHour: Int, scale: HeatScale, log: (String) -> Log?
    ) -> [WeekBar] {
        let today = WorkdayDetector(newDayStartHour: newDayStartHour).effectiveDateString(for: now)
        return calendarDays(7, endingOn: today).map { date in
            WeekBar(date: date, log: log(date), scale: scale, today: today)
        }
    }

    /// The hours a full-height bar stands for: at least 10, the red line, or the longest day.
    static func chartMaxHours(for bars: [WeekBar], scale: HeatScale) -> Double {
        max(10, scale.redHours, bars.map(\.netHours).max() ?? 0)
    }

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
