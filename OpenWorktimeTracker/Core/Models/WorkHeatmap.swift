import Foundation

/// How heavily a single day was worked, as painted by the work heatmap.
///
/// Named by meaning, like `ThresholdLevel`; the view decides the colours.
enum HeatLevel: Int, CaseIterable, Comparable {
    /// Inside the range but nothing was worked.
    case none
    /// Under 4 hours.
    case light
    /// 4 to 6 hours.
    case medium
    /// 6 hours up to the daily goal.
    case deep
    /// Past the daily goal, up to the red threshold.
    case overtime
    /// Past the red threshold.
    case excessive

    static func < (lhs: HeatLevel, rhs: HeatLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Where the heatmap's colours change, read from the same settings as the rest
/// of the app: the daily goal is the normal notification, the red line is the
/// Threshold Ladder's critical step.
struct HeatScale: Equatable {

    static let mediumHours = 4.0
    static let deepHours = 6.0

    let goalHours: Double
    let redHours: Double

    func level(forHours hours: Double) -> HeatLevel {
        guard hours > 0 else { return .none }
        if hours > redHours { return .excessive }
        if hours > goalHours { return .overtime }
        if hours < Self.mediumHours { return .light }
        if hours < Self.deepHours { return .medium }
        return .deep
    }

    /// Resolved from user settings.
    static func resolved(from defaults: UserDefaults = .standard) -> HeatScale {
        HeatScale(
            goalHours: NotificationThresholds.resolved(from: defaults).normalHours,
            redHours: ThresholdLadder.resolved(from: defaults).criticalHours
        )
    }
}

/// One Daily Log reduced to what the heatmap needs.
struct HeatmapLog: Equatable {
    let date: String  // YYYY-MM-DD
    let netHours: Double
    let startTime: Date
    let endTime: Date?
}

/// One square of the heatmap.
struct HeatmapDay: Equatable, Identifiable {
    let date: Date
    /// `nil` for days outside the tracked range: in the future, or before the
    /// first Daily Log ever written.
    let log: HeatmapLog?
    let isTracked: Bool
    let level: HeatLevel
    /// The Public Holiday or make-up day off on this date, if any.
    var holiday: Holiday?

    var id: Date { date }
    var netHours: Double { log?.netHours ?? 0 }
}

/// Totals over every tracked day on the heatmap.
struct HeatmapStats: Equatable {
    let workedDays: Int
    let overtimeDays: Int
    let averageHours: Double
}

/// A contribution-style calendar of daily Net Work Time: one column per week,
/// Sunday on top, ending with the week that contains `today`.
struct WorkHeatmap {

    static let defaultWeekCount = 26

    let weeks: [[HeatmapDay]]
    let stats: HeatmapStats
    let scale: HeatScale

    init(
        logs: [HeatmapLog],
        scale: HeatScale,
        today: Date,
        weekCount: Int = defaultWeekCount,
        holidays: HolidayCalendar = .empty,
        calendar baseCalendar: Calendar = .current
    ) {
        var calendar = baseCalendar
        calendar.firstWeekday = 1  // Sunday
        self.scale = scale

        var hoursByDate: [String: HeatmapLog] = [:]
        for log in logs {
            if let existing = hoursByDate[log.date] {
                // Two logs on one date: add up the work, keep the widest span.
                hoursByDate[log.date] = HeatmapLog(
                    date: log.date,
                    netHours: existing.netHours + log.netHours,
                    startTime: min(existing.startTime, log.startTime),
                    endTime: [existing.endTime, log.endTime].compactMap { $0 }.max()
                )
            } else {
                hoursByDate[log.date] = log
            }
        }
        let firstLogDate = hoursByDate.keys.min()

        let todayStart = calendar.startOfDay(for: today)
        let todayString = TimeEntry.dateString(from: todayStart)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: todayStart)?.start ?? todayStart
        let firstDay =
            calendar.date(byAdding: .weekOfYear, value: -(max(1, weekCount) - 1), to: weekStart) ?? weekStart

        var weeks: [[HeatmapDay]] = []
        var tracked: [HeatmapDay] = []
        for weekIndex in 0..<max(1, weekCount) {
            var column: [HeatmapDay] = []
            for weekday in 0..<7 {
                guard
                    let date = calendar.date(byAdding: .day, value: weekIndex * 7 + weekday, to: firstDay)
                else { continue }
                let dateString = TimeEntry.dateString(from: date)
                let isTracked =
                    dateString <= todayString
                    && firstLogDate.map { dateString >= $0 } == true
                let log = isTracked ? hoursByDate[dateString] : nil
                let day = HeatmapDay(
                    date: date,
                    log: log,
                    isTracked: isTracked,
                    level: scale.level(forHours: log?.netHours ?? 0),
                    holiday: holidays.holiday(on: dateString)
                )
                column.append(day)
                if isTracked { tracked.append(day) }
            }
            weeks.append(column)
        }
        self.weeks = weeks
        self.stats = Self.stats(for: tracked, scale: scale)
    }

    static func stats(for days: [HeatmapDay], scale: HeatScale) -> HeatmapStats {
        let worked = days.filter { $0.netHours > 0 }
        let total = worked.reduce(0) { $0 + $1.netHours }
        return HeatmapStats(
            workedDays: worked.count,
            overtimeDays: worked.filter { $0.netHours > scale.goalHours }.count,
            averageHours: worked.isEmpty ? 0 : total / Double(worked.count)
        )
    }

    /// The columns that start a month, so a label can sit above them. The very
    /// first column is labelled too when the next month is far enough away not
    /// to collide with it.
    func monthLabelColumns(calendar: Calendar = .current, minimumGap: Int = 3) -> [(column: Int, date: Date)] {
        var labels: [(column: Int, date: Date)] = []
        for (index, week) in weeks.enumerated() {
            if let first = week.first(where: { calendar.component(.day, from: $0.date) == 1 }) {
                labels.append((index, first.date))
            }
        }
        if let firstDay = weeks.first?.first,
            labels.first?.column != 0,
            (labels.first?.column ?? Int.max) >= minimumGap {
            labels.insert((0, firstDay.date), at: 0)
        }
        return labels
    }
}
