import XCTest

@testable import OpenWorktimeTracker

/// Tests the "last 7 days" bars: they borrow the heatmap's colour levels,
/// report only the time past the daily goal as overtime, and always cover the
/// seven calendar days ending on the effective today, oldest first.
final class WeekBarTests: XCTestCase {

    private let scale = HeatScale(goalHours: 8, redHours: 9.5)
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func bar(
        _ date: String = "2026-09-30", seconds: TimeInterval, today: String = "2026-10-01"
    ) -> WeekBar {
        WeekBar(
            date: date, netWorkTime: seconds, startTime: start,
            endTime: start.addingTimeInterval(seconds), scale: scale, today: today)
    }

    private func hours(_ value: Double) -> TimeInterval {
        value * 3600
    }

    // MARK: - Colour levels

    func testBarsUseTheHeatmapLevels() {
        for value in [0, 2, 4.5, 6, 7.5, 8, 8.5, 9.5, 9.75, 12] {
            XCTAssertEqual(bar(seconds: hours(value)).level, scale.level(forHours: value), "\(value)h")
        }
        XCTAssertEqual(bar(seconds: 0).level, .none)
        XCTAssertEqual(bar(seconds: hours(3)).level, .light)
        XCTAssertEqual(bar(seconds: hours(5)).level, .medium)
        XCTAssertEqual(bar(seconds: hours(8)).level, .deep, "Exactly on the goal is not overtime")
        XCTAssertEqual(bar(seconds: hours(8.5)).level, .overtime)
        XCTAssertEqual(bar(seconds: hours(10)).level, .excessive)
    }

    // MARK: - Overtime

    func testOvertimeIsOnlyThePartPastTheGoal() {
        XCTAssertEqual(bar(seconds: hours(7)).overtime, 0)
        XCTAssertNil(bar(seconds: hours(7)).overtimeHoursMinutes)
        XCTAssertNil(bar(seconds: hours(8)).overtimeHoursMinutes)

        let late = bar(seconds: 9 * 3600 + 35 * 60)
        XCTAssertEqual(late.overtime, 3600 + 35 * 60)
        XCTAssertEqual(late.overtimeHoursMinutes?.hours, 1)
        XCTAssertEqual(late.overtimeHoursMinutes?.minutes, 35)

        let short = bar(seconds: 8 * 3600 + 20 * 60)
        XCTAssertEqual(short.overtimeHoursMinutes?.hours, 0)
        XCTAssertEqual(short.overtimeHoursMinutes?.minutes, 20)
    }

    func testUnderAMinuteOverIsNotReportedAsOvertime() {
        let barely = bar(seconds: 8 * 3600 + 30)
        XCTAssertEqual(barely.level, .overtime)
        XCTAssertNil(barely.overtimeHoursMinutes)
    }

    // MARK: - Layout data

    func testOnlyTodaysBarIsMarked() {
        XCTAssertTrue(bar("2026-10-01", seconds: hours(5)).isToday)
        XCTAssertFalse(bar("2026-09-30", seconds: hours(5)).isToday)
    }

    private func localDate(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func week(
        now: Date, newDayStartHour: Int = 4, logs: [String: TimeInterval]
    ) -> [WeekBar] {
        WeekBar.lastSevenDays(now: now, newDayStartHour: newDayStartHour, scale: scale) { date in
            logs[date].map { WeekBar.Log(netWorkTime: $0, startTime: self.start, endTime: nil) }
        }
    }

    func testWeekAlwaysHasSevenCalendarDaysEndingToday() {
        let bars = week(now: localDate(2026, 10, 1, hour: 10), logs: [:])
        XCTAssertEqual(
            bars.map(\.date),
            ["2026-09-25", "2026-09-26", "2026-09-27", "2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01"])
        XCTAssertEqual(bars.filter(\.isToday).map(\.date), ["2026-10-01"])
        XCTAssertTrue(bars.last?.isToday == true, "Today is the last slot")
        XCTAssertFalse(bars.contains(where: \.hasLog))
    }

    func testDaysWithoutALogStayAsEmptySlots() {
        let bars = week(
            now: localDate(2026, 10, 1, hour: 10),
            logs: ["2026-09-26": hours(7), "2026-09-30": hours(9), "2026-08-01": hours(5)])
        XCTAssertEqual(bars.count, 7)
        XCTAssertEqual(bars.filter(\.hasLog).map(\.date), ["2026-09-26", "2026-09-30"])
        XCTAssertEqual(bars.map(\.netHours), [0, 7, 0, 0, 0, 9, 0])

        let gap = bars[2]
        XCTAssertNil(gap.log)
        XCTAssertEqual(gap.level, .none)
        XCTAssertEqual(gap.overtime, 0)
        XCTAssertNil(gap.overtimeHoursMinutes)

        let total = bars.reduce(0) { $0 + $1.netWorkTime }
        XCTAssertEqual(total, hours(16), "Older logs outside the window do not count")
    }

    func testBeforeTheNewDayStartHourStillCountsAsYesterday() {
        let bars = week(now: localDate(2026, 10, 2, hour: 2), newDayStartHour: 4, logs: ["2026-10-01": hours(3)])
        XCTAssertEqual(bars.last?.date, "2026-10-01")
        XCTAssertTrue(bars.last?.isToday == true)
        XCTAssertEqual(bars.first?.date, "2026-09-25")

        let afterBoundary = week(now: localDate(2026, 10, 2, hour: 4), newDayStartHour: 4, logs: [:])
        XCTAssertEqual(afterBoundary.last?.date, "2026-10-02")
    }

    func testWeekCrossesMonthAndYearBoundaries() {
        XCTAssertEqual(
            WeekBar.calendarDays(endingOn: "2027-01-03"),
            ["2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02", "2027-01-03"])
        XCTAssertEqual(WeekBar.calendarDays(endingOn: "2028-03-01").first, "2028-02-24")
        XCTAssertEqual(WeekBar.calendarDays(endingOn: "2028-03-01")[5], "2028-02-29")
    }

    func testFullHeightCoversTheLongestDayAndTheRedLine() {
        XCTAssertEqual(WeekBar.chartMaxHours(for: [], scale: scale), 10)
        let allEmpty = week(now: localDate(2026, 10, 1, hour: 10), logs: [:])
        XCTAssertEqual(WeekBar.chartMaxHours(for: allEmpty, scale: scale), 10, "An empty week still has a scale")
        XCTAssertEqual(WeekBar.chartMaxHours(for: [bar(seconds: hours(7))], scale: scale), 10)
        XCTAssertEqual(WeekBar.chartMaxHours(for: [bar(seconds: hours(12))], scale: scale), 12, accuracy: 0.001)
        let lateRedLine = HeatScale(goalHours: 9, redHours: 11)
        XCTAssertEqual(WeekBar.chartMaxHours(for: [], scale: lateRedLine), 11)
    }
}
