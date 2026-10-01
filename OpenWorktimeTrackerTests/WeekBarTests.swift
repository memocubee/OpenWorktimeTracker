import XCTest

@testable import OpenWorktimeTracker

/// Tests the "last 7 days" bars: they borrow the heatmap's colour levels,
/// report only the time past the daily goal as overtime, and read oldest first.
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

    func testChartReadsOldestFirst() {
        let newestFirst = ["2026-10-01", "2026-09-30", "2026-09-28", "2026-09-25"].map {
            bar($0, seconds: hours(7))
        }
        XCTAssertEqual(
            WeekBar.sortedChronologically(newestFirst).map(\.date),
            ["2026-09-25", "2026-09-28", "2026-09-30", "2026-10-01"])
    }

    func testFullHeightCoversTheLongestDayAndTheRedLine() {
        XCTAssertEqual(WeekBar.chartMaxHours(for: [], scale: scale), 10)
        XCTAssertEqual(WeekBar.chartMaxHours(for: [bar(seconds: hours(7))], scale: scale), 10)
        XCTAssertEqual(WeekBar.chartMaxHours(for: [bar(seconds: hours(12))], scale: scale), 12, accuracy: 0.001)
        let lateRedLine = HeatScale(goalHours: 9, redHours: 11)
        XCTAssertEqual(WeekBar.chartMaxHours(for: [], scale: lateRedLine), 11)
    }
}
