import Foundation

/// One column of the week chart: a calendar day's Net Work Time, painted with
/// the heatmap's levels so overtime days stand out the same way in both. A day
/// without a Daily Log is still a column, just an empty one.
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
    /// After today, so nobody could have worked it yet.
    let isFuture: Bool
    /// The Public Holiday or make-up day off on this date, if any.
    let holiday: Holiday?
    /// Whether the holiday calendar expects work on this date.
    let isWorkingDay: Bool

    var id: String { date }
    var hasLog: Bool { log != nil }
    var netWorkTime: TimeInterval { log?.netWorkTime ?? 0 }
    var netHours: Double { netWorkTime / 3600 }

    init(date: String, log: Log?, scale: HeatScale, today: String, holidays: HolidayCalendar = .empty) {
        self.date = date
        self.log = log
        let net = log?.netWorkTime ?? 0
        self.level = scale.level(forHours: net / 3600)
        self.overtime = max(0, net - scale.goalHours * 3600)
        self.isToday = date == today
        self.isFuture = date > today
        self.holiday = holidays.holiday(on: date)
        self.isWorkingDay = holidays.isWorkingDay(date)
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

    /// The hours a full-height bar stands for: at least 10, the red line, or the longest day.
    static func chartMaxHours(for bars: [WeekBar], scale: HeatScale) -> Double {
        max(10, scale.redHours, bars.map(\.netHours).max() ?? 0)
    }
}

/// One Monday-to-Sunday week measured against its Expected Hours: the daily
/// goal for every day the holiday calendar expects work.
struct WorkWeek: Equatable {
    /// Monday first.
    let bars: [WeekBar]
    /// Weeks from the current one: 0 is this week, -1 last week.
    let offset: Int
    let expected: TimeInterval

    var firstDate: String { bars.first?.date ?? "" }
    var lastDate: String { bars.last?.date ?? "" }
    var workingDays: Int { bars.filter(\.isWorkingDay).count }
    var worked: TimeInterval { bars.reduce(0) { $0 + $1.netWorkTime } }
    /// Past the Expected Hours when positive, short of them when negative.
    var balance: TimeInterval { worked - expected }
    /// Days off the calendar names this week, weekends included.
    var holidays: [Holiday] { bars.compactMap(\.holiday) }

    /// The week `offset` weeks from the one containing `today` (YYYY-MM-DD, the
    /// effective day, so before the new-day hour still counts as yesterday).
    static func week(
        offset: Int, today: String, scale: HeatScale, holidays: HolidayCalendar, log: (String) -> WeekBar.Log?
    ) -> WorkWeek {
        let monday = DayString.monday(of: today).flatMap { DayString.adding(offset * 7, to: $0) }
        let days = monday.map { start in (0..<7).compactMap { DayString.adding($0, to: start) } } ?? []
        let bars = days.map { date in
            WeekBar(date: date, log: log(date), scale: scale, today: today, holidays: holidays)
        }
        return WorkWeek(
            bars: bars, offset: offset,
            expected: Double(bars.filter(\.isWorkingDay).count) * scale.goalHours * 3600)
    }

    /// Expected Hours for the working days from `first` through `last`.
    static func expectedHours(
        from first: String, through last: String, goalHours: Double, holidays: HolidayCalendar
    ) -> TimeInterval {
        var day = first
        var workingDays = 0
        while day <= last {
            if holidays.isWorkingDay(day) { workingDays += 1 }
            guard let next = DayString.adding(1, to: day) else { break }
            day = next
        }
        return Double(workingDays) * goalHours * 3600
    }
}
