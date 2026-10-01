import Foundation

/// One column of the "last 7 days" chart: a Daily Log's Net Work Time, painted
/// with the heatmap's levels so overtime days stand out the same way in both.
struct WeekBar: Equatable, Identifiable {
    let date: String  // YYYY-MM-DD
    let netWorkTime: TimeInterval
    let startTime: Date
    /// `nil` while the Workday is still running.
    let endTime: Date?
    let level: HeatLevel
    /// Net Work Time past the daily goal; zero at or under it.
    let overtime: TimeInterval
    let isToday: Bool

    var id: String { date }
    var netHours: Double { netWorkTime / 3600 }

    init(
        date: String, netWorkTime: TimeInterval, startTime: Date, endTime: Date?,
        scale: HeatScale, today: String
    ) {
        self.date = date
        self.netWorkTime = netWorkTime
        self.startTime = startTime
        self.endTime = endTime
        self.level = scale.level(forHours: netWorkTime / 3600)
        self.overtime = max(0, netWorkTime - scale.goalHours * 3600)
        self.isToday = date == today
    }

    /// Whole hours and minutes of overtime, or `nil` when under a minute over.
    var overtimeHoursMinutes: (hours: Int, minutes: Int)? {
        let minutes = Int(overtime) / 60
        guard minutes > 0 else { return nil }
        return (minutes / 60, minutes % 60)
    }

    /// Oldest first, so the chart reads left to right.
    static func sortedChronologically(_ bars: [WeekBar]) -> [WeekBar] {
        bars.sorted { $0.date < $1.date }
    }

    /// The hours a full-height bar stands for: at least 10, the red line, or the longest day.
    static func chartMaxHours(for bars: [WeekBar], scale: HeatScale) -> Double {
        max(10, scale.redHours, bars.map(\.netHours).max() ?? 0)
    }
}
