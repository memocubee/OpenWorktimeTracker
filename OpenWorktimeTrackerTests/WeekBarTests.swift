import XCTest

@testable import OpenWorktimeTracker

/// Tests the week chart: its bars borrow the heatmap's colour levels and
/// report only the time past the daily goal as overtime; a week always runs
/// Monday to Sunday and owes the daily goal on every working day the holiday
/// calendar leaves.
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

    /// 教師節 on Monday 28 September, 國慶日 on Saturday 10 October with its
    /// make-up day off on the Friday before.
    private let taiwan = HolidayCalendar(records: [
        .init(date: "20260928", isHoliday: true, description: "孔子誕辰紀念日/教師節"),
        .init(date: "20261009", isHoliday: true, description: "補假"),
        .init(date: "20261010", isHoliday: true, description: "國慶日"),
        .init(date: "20261011", isHoliday: true, description: "")
    ])

    private func week(
        offset: Int = 0, now: Date, newDayStartHour: Int = 4, holidays: HolidayCalendar? = nil,
        logs: [String: TimeInterval] = [:]
    ) -> WorkWeek {
        WorkWeek.week(
            offset: offset,
            today: WorkdayDetector(newDayStartHour: newDayStartHour).effectiveDateString(for: now),
            scale: scale, holidays: holidays ?? taiwan
        ) { date in
            logs[date].map { WeekBar.Log(netWorkTime: $0, startTime: self.start, endTime: nil) }
        }
    }

    // MARK: - Weeks

    func testWeekRunsMondayToSundayAroundToday() {
        let current = week(now: localDate(2026, 10, 7, hour: 10))
        XCTAssertEqual(
            current.bars.map(\.date),
            ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10", "2026-10-11"])
        XCTAssertEqual(current.bars.filter(\.isToday).map(\.date), ["2026-10-07"])
        XCTAssertEqual(current.bars.filter(\.isFuture).map(\.date).first, "2026-10-08")
        XCTAssertFalse(current.bars.contains(where: \.hasLog))
        XCTAssertEqual(current.offset, 0)
    }

    func testSundayStillBelongsToTheWeekThatStartedOnMonday() {
        XCTAssertEqual(week(now: localDate(2026, 10, 11, hour: 20)).firstDate, "2026-10-05")
        XCTAssertEqual(week(now: localDate(2026, 10, 12, hour: 9)).firstDate, "2026-10-12")
    }

    func testBeforeTheNewDayStartHourStillCountsAsYesterday() {
        let lateSunday = week(now: localDate(2026, 10, 12, hour: 2), newDayStartHour: 4)
        XCTAssertEqual(lateSunday.firstDate, "2026-10-05")
        XCTAssertEqual(lateSunday.bars.last?.isToday, true)
    }

    func testOffsetPagesBackWholeWeeksAcrossMonthsAndYears() {
        let now = localDate(2026, 10, 7, hour: 10)
        XCTAssertEqual(week(offset: -1, now: now).firstDate, "2026-09-28")
        XCTAssertEqual(week(offset: -1, now: now).lastDate, "2026-10-04")
        XCTAssertEqual(week(offset: -2, now: now).firstDate, "2026-09-21")
        XCTAssertFalse(week(offset: -1, now: now).bars.contains(where: \.isToday))

        let newYear = week(now: localDate(2027, 1, 1, hour: 10))
        XCTAssertEqual(newYear.firstDate, "2026-12-28")
        XCTAssertEqual(newYear.lastDate, "2027-01-03")
    }

    func testExpectedHoursLeaveOutPublicHolidays() {
        let national = week(now: localDate(2026, 10, 7, hour: 10))
        XCTAssertEqual(national.workingDays, 4)
        XCTAssertEqual(national.expected, hours(32))
        XCTAssertEqual(national.holidays.map(\.name), ["國慶日補假", "國慶日"])
        XCTAssertFalse(national.bars[4].isWorkingDay, "The make-up day off is off")
        XCTAssertEqual(national.bars[4].holiday?.name, "國慶日補假")
        XCTAssertNil(national.bars[6].holiday, "An ordinary Sunday is not listed")

        let teachers = week(offset: -1, now: localDate(2026, 10, 7, hour: 10))
        XCTAssertEqual(teachers.expected, hours(32))
        XCTAssertEqual(teachers.holidays.map(\.name), ["教師節"])
    }

    func testWithoutHolidayDataAWeekIsMondayToFriday() {
        let plain = week(now: localDate(2026, 10, 7, hour: 10), holidays: .empty)
        XCTAssertEqual(plain.workingDays, 5)
        XCTAssertEqual(plain.expected, hours(40))
        XCTAssertTrue(plain.holidays.isEmpty)
    }

    func testAWeekendMadeAWorkingDayOwesHoursToo() {
        let makeUp = HolidayCalendar(records: [.init(date: "20250208", isHoliday: false, description: "補行上班")])
        let makeUpWeek = week(now: localDate(2025, 2, 5, hour: 10), holidays: makeUp)
        XCTAssertEqual(makeUpWeek.workingDays, 6)
        XCTAssertTrue(makeUpWeek.bars[5].isWorkingDay)
        XCTAssertEqual(makeUpWeek.expected, hours(48))
    }

    func testBalanceWeighsEveryDayWorkedAgainstTheExpectedHours() {
        let busy = week(
            now: localDate(2026, 10, 11, hour: 20),
            logs: [
                "2026-10-05": hours(9), "2026-10-06": hours(9), "2026-10-07": hours(9),
                "2026-10-08": hours(9), "2026-10-10": hours(2), "2026-09-30": hours(8)
            ])
        XCTAssertEqual(busy.worked, hours(38), "Work on a holiday counts, other weeks do not")
        XCTAssertEqual(busy.balance, hours(6))
        XCTAssertEqual(busy.bars.filter(\.hasLog).map(\.date), ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-10"])

        let short = week(now: localDate(2026, 10, 11, hour: 20), logs: ["2026-10-05": hours(8)])
        XCTAssertEqual(short.balance, -hours(24))
    }

    func testExpectedHoursOverARangeCountOnlyWorkingDays() {
        XCTAssertEqual(
            WorkWeek.expectedHours(from: "2026-10-01", through: "2026-10-11", goalHours: 8, holidays: taiwan),
            hours(48), "1, 2, 5, 6, 7 and 8 October")
        XCTAssertEqual(
            WorkWeek.expectedHours(from: "2026-10-05", through: "2026-10-04", goalHours: 8, holidays: taiwan), 0)
        XCTAssertEqual(
            WorkWeek.expectedHours(from: "2026-10-05", through: "2026-10-05", goalHours: 7.5, holidays: taiwan),
            hours(7.5))
    }

    func testDayStringsStayGregorianAroundMonthAndLeapYearEnds() {
        XCTAssertEqual(DayString.adding(1, to: "2026-12-31"), "2027-01-01")
        XCTAssertEqual(DayString.adding(-1, to: "2028-03-01"), "2028-02-29")
        XCTAssertEqual(DayString.monday(of: "2026-10-11"), "2026-10-05")
        XCTAssertEqual(DayString.monday(of: "2026-10-05"), "2026-10-05")
        XCTAssertTrue(DayString.isWeekend("2026-10-10"))
        XCTAssertFalse(DayString.isWeekend("2026-10-09"))
        XCTAssertNil(DayString.adding(1, to: "not a day"))
    }

    func testFullHeightCoversTheLongestDayAndTheRedLine() {
        XCTAssertEqual(WeekBar.chartMaxHours(for: [], scale: scale), 10)
        let allEmpty = week(now: localDate(2026, 10, 1, hour: 10)).bars
        XCTAssertEqual(WeekBar.chartMaxHours(for: allEmpty, scale: scale), 10, "An empty week still has a scale")
        XCTAssertEqual(WeekBar.chartMaxHours(for: [bar(seconds: hours(7))], scale: scale), 10)
        XCTAssertEqual(WeekBar.chartMaxHours(for: [bar(seconds: hours(12))], scale: scale), 12, accuracy: 0.001)
        let lateRedLine = HeatScale(goalHours: 9, redHours: 11)
        XCTAssertEqual(WeekBar.chartMaxHours(for: [], scale: lateRedLine), 11)
    }
}
