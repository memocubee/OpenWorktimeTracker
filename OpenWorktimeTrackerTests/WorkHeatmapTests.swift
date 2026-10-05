import XCTest

@testable import OpenWorktimeTracker

/// Tests the work heatmap's pure logic: bucketing Net Work Time into heat
/// levels, laying days out in week columns, and the six-month stats.
final class WorkHeatmapTests: XCTestCase {

    private let calendar = Calendar.current
    private let scale = HeatScale(goalHours: 8, redHours: 9)

    /// Thursday, 24 September 2026, at noon.
    private var today: Date {
        date(2026, 9, 24, hour: 12)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date()
    }

    private func log(_ dateString: String, hours: Double) -> HeatmapLog {
        let start = date(2026, 1, 1, hour: 9)
        return HeatmapLog(
            date: dateString, netHours: hours, startTime: start,
            endTime: start.addingTimeInterval(hours * 3600))
    }

    // MARK: - Heat levels

    func testLevelsFollowTheHourBands() {
        let expected: [(Double, HeatLevel)] = [
            (-1, .none), (0, .none), (0.5, .light), (3.99, .light), (4, .medium), (5.99, .medium),
            (6, .deep), (8, .deep), (8.01, .overtime), (9, .overtime), (9.01, .excessive), (14, .excessive)
        ]
        for (hours, level) in expected {
            XCTAssertEqual(scale.level(forHours: hours), level, "\(hours)h")
        }
    }

    func testPastTheGoalIsOvertimeEvenBelowTheDeepBand() {
        let shortGoal = HeatScale(goalHours: 5, redHours: 9)
        XCTAssertEqual(shortGoal.level(forHours: 4.5), .medium)
        XCTAssertEqual(shortGoal.level(forHours: 5.5), .overtime)
    }

    func testScaleIsResolvedFromSettings() throws {
        let suiteName = "heatmap-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            HeatScale.resolved(from: defaults),
            HeatScale(goalHours: AppDefaults.normalNotificationHours, redHours: AppDefaults.redThresholdHours))

        defaults.set(7.5, forKey: AppSettingsKey.normalNotificationHours)
        defaults.set(10.0, forKey: AppSettingsKey.redThresholdHours)
        XCTAssertEqual(HeatScale.resolved(from: defaults), HeatScale(goalHours: 7.5, redHours: 10))
    }

    // MARK: - Layout

    func testGridHasOneSundayFirstColumnPerWeekEndingThisWeek() throws {
        let heatmap = WorkHeatmap(logs: [log("2026-01-05", hours: 1)], scale: scale, today: today)

        XCTAssertEqual(heatmap.weeks.count, WorkHeatmap.defaultWeekCount)
        for week in heatmap.weeks {
            XCTAssertEqual(week.count, 7)
            XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(week.first).date), 1)
        }
        let lastWeek = try XCTUnwrap(heatmap.weeks.last)
        XCTAssertEqual(TimeEntry.dateString(from: lastWeek[0].date), "2026-09-20")
        XCTAssertEqual(TimeEntry.dateString(from: lastWeek[4].date), "2026-09-24")
        XCTAssertTrue(lastWeek[4].isTracked, "Today is tracked")
        XCTAssertFalse(lastWeek[5].isTracked, "Tomorrow is in the future")
        XCTAssertFalse(lastWeek[6].isTracked)
    }

    func testDaysBeforeTheFirstLogAreNotTracked() throws {
        let heatmap = WorkHeatmap(logs: [log("2026-09-22", hours: 7)], scale: scale, today: today)
        let lastWeek = try XCTUnwrap(heatmap.weeks.last)

        XCTAssertFalse(lastWeek[1].isTracked, "2026-09-21 is before the first log")
        XCTAssertTrue(lastWeek[2].isTracked)
        XCTAssertEqual(lastWeek[2].level, .deep)
        XCTAssertTrue(lastWeek[3].isTracked, "A day without work after the first log is tracked")
        XCTAssertEqual(lastWeek[3].level, .none)
        XCTAssertNil(lastWeek[3].log)
    }

    func testMonthLabelsSitOverTheColumnsContainingTheFirst() {
        let heatmap = WorkHeatmap(logs: [], scale: scale, today: today)
        let labels = heatmap.monthLabelColumns(calendar: calendar)

        XCTAssertFalse(labels.isEmpty)
        for label in labels.dropFirst() {
            XCTAssertEqual(calendar.component(.day, from: label.date), 1)
            let week = heatmap.weeks[label.column].map { TimeEntry.dateString(from: $0.date) }
            XCTAssertTrue(week.contains(TimeEntry.dateString(from: label.date)))
        }
        XCTAssertEqual(
            labels.map { calendar.component(.month, from: $0.date) }.suffix(6), [4, 5, 6, 7, 8, 9])
        let columns = labels.map(\.column)
        XCTAssertEqual(columns, columns.sorted())
    }

    // MARK: - Stats

    func testStatsCountWorkedDaysAndAverageThem() {
        let heatmap = WorkHeatmap(
            logs: [
                log("2026-09-01", hours: 5),
                log("2026-09-02", hours: 8.5),
                log("2026-09-03", hours: 10),
                log("2026-09-04", hours: 0),
                log("2026-09-07", hours: 8)
            ],
            scale: scale, today: today)

        XCTAssertEqual(heatmap.stats.workedDays, 4)
        XCTAssertEqual(heatmap.stats.averageHours, (5 + 8.5 + 10 + 8) / 4, accuracy: 0.0001)
    }

    func testStatsIgnoreLogsOutsideTheVisibleRange() {
        let heatmap = WorkHeatmap(
            logs: [log("2025-01-10", hours: 12), log("2026-09-23", hours: 6), log("2026-09-30", hours: 11)],
            scale: scale, today: today)

        XCTAssertEqual(heatmap.stats, HeatmapStats(workedDays: 1, averageHours: 6))
    }

    func testStatsAreZeroWithoutLogs() {
        let heatmap = WorkHeatmap(logs: [], scale: scale, today: today)

        XCTAssertEqual(heatmap.stats, HeatmapStats(workedDays: 0, averageHours: 0))
        XCTAssertTrue(heatmap.weeks.joined().allSatisfy { !$0.isTracked })
    }

    func testTwoLogsOnOneDateAreAddedUp() throws {
        let heatmap = WorkHeatmap(
            logs: [log("2026-09-23", hours: 5), log("2026-09-23", hours: 4.5)], scale: scale, today: today)
        let day = try XCTUnwrap(heatmap.weeks.last?[3])

        XCTAssertEqual(day.netHours, 9.5, accuracy: 0.0001)
        XCTAssertEqual(day.level, .excessive)
        XCTAssertEqual(heatmap.stats.workedDays, 1)
    }

    func testHolidaysAreMarkedWhetherWorkedOrStillAhead() throws {
        let holidays = HolidayCalendar(records: [
            .init(date: "20260619", isHoliday: true, description: "端午節"),
            .init(date: "20260925", isHoliday: true, description: "中秋節")
        ])
        let heatmap = WorkHeatmap(
            logs: [log("2026-04-01", hours: 6), log("2026-06-19", hours: 2)], scale: scale, today: today,
            holidays: holidays)
        let days = heatmap.weeks.joined()

        let dragonBoat = try XCTUnwrap(days.first { TimeEntry.dateString(from: $0.date) == "2026-06-19" })
        XCTAssertEqual(dragonBoat.holiday?.name, "端午節")
        XCTAssertTrue(dragonBoat.isTracked)
        XCTAssertEqual(dragonBoat.level, .light, "Worked on a holiday keeps its heat level")

        let midAutumn = try XCTUnwrap(heatmap.weeks.last?[5])
        XCTAssertEqual(midAutumn.holiday?.name, "中秋節")
        XCTAssertFalse(midAutumn.isTracked, "Still ahead")

        XCTAssertEqual(days.filter { $0.holiday != nil }.count, 2)
    }
}
