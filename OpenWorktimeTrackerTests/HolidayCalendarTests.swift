import XCTest

@testable import OpenWorktimeTracker

/// Tests reading Taiwan's working-day calendar: which days are off, what the
/// week history calls them, and that the bundled years agree with the
/// published 放假 flag on every single day.
final class HolidayCalendarTests: XCTestCase {

    private func calendar(_ json: String) throws -> HolidayCalendar {
        HolidayCalendar(records: try HolidayCalendar.records(from: Data(json.utf8)))
    }

    // MARK: - Parsing

    func testReadsThePublishedFormat() throws {
        let calendar = try calendar("""
            [{"date":"20261009","week":"五","isHoliday":true,"description":"補假"},
             {"date":"20261010","week":"六","isHoliday":true,"description":"國慶日"},
             {"date":"20261011","week":"日","isHoliday":true,"description":""},
             {"date":"20261012","week":"一","isHoliday":false,"description":""},
             {"date":"20250208","week":"六","isHoliday":false,"description":"補行上班"}]
            """)
        XCTAssertEqual(calendar.holiday(on: "2026-10-09"), Holiday(date: "2026-10-09", name: "國慶日補假"))
        XCTAssertEqual(calendar.holiday(on: "2026-10-10")?.name, "國慶日")
        XCTAssertNil(calendar.holiday(on: "2026-10-11"), "An ordinary Sunday is not a holiday")
        XCTAssertNil(calendar.holiday(on: "2026-10-12"))
        XCTAssertEqual(calendar.makeUpWorkdays, ["2025-02-08"])
        XCTAssertEqual(calendar.years, [2025, 2026])
    }

    func testWorkingDaysAreWeekdaysExceptDaysOffPlusMadeUpWeekends() throws {
        let calendar = try calendar("""
            [{"date":"20261009","week":"五","isHoliday":true,"description":"補假"},
             {"date":"20250208","week":"六","isHoliday":false,"description":"補行上班"}]
            """)
        XCTAssertFalse(calendar.isWorkingDay("2026-10-09"))
        XCTAssertTrue(calendar.isWorkingDay("2026-10-08"))
        XCTAssertFalse(calendar.isWorkingDay("2026-10-10"))
        XCTAssertTrue(calendar.isWorkingDay("2025-02-08"))
        XCTAssertFalse(calendar.isWorkingDay("2025-02-09"))
        XCTAssertTrue(HolidayCalendar.empty.isWorkingDay("2030-01-01"), "No data: Monday to Friday")
    }

    // MARK: - Names

    func testAMakeUpDayOffIsNamedAfterTheHolidayItReplaces() throws {
        let calendar = try calendar("""
            [{"date":"20260403","week":"五","isHoliday":true,"description":"補假"},
             {"date":"20260404","week":"六","isHoliday":true,"description":"兒童節"},
             {"date":"20260405","week":"日","isHoliday":true,"description":"清明節"},
             {"date":"20260406","week":"一","isHoliday":true,"description":"補假"},
             {"date":"20250403","week":"四","isHoliday":true,"description":"補假"},
             {"date":"20250404","week":"五","isHoliday":true,"description":"兒童節及民族掃墓節"},
             {"date":"20250928","week":"日","isHoliday":true,"description":"孔子誕辰紀念日"},
             {"date":"20250929","week":"一","isHoliday":true,"description":"補假"},
             {"date":"20270115","week":"五","isHoliday":true,"description":"補假"}]
            """)
        XCTAssertEqual(calendar.holiday(on: "2026-04-03")?.name, "兒童節補假")
        XCTAssertEqual(calendar.holiday(on: "2026-04-06")?.name, "清明節補假")
        XCTAssertEqual(calendar.holiday(on: "2025-04-03")?.name, "兒童節及清明節補假", "Falls back to a weekday holiday")
        XCTAssertEqual(calendar.holiday(on: "2025-09-29")?.name, "教師節補假")
        XCTAssertEqual(calendar.holiday(on: "2027-01-15")?.name, "補假", "Nothing nearby to name it after")
    }

    func testLongOfficialNamesAreShortened() throws {
        let calendar = try calendar("""
            [{"date":"20260928","week":"一","isHoliday":true,"description":"孔子誕辰紀念日/教師節"},
             {"date":"20261025","week":"日","isHoliday":true,"description":"臺灣光復暨金門古寧頭大捷紀念日"},
             {"date":"20261026","week":"一","isHoliday":true,"description":"補假"},
             {"date":"20260216","week":"一","isHoliday":true,"description":"農曆除夕"},
             {"date":"20261225","week":"五","isHoliday":true,"description":"行憲紀念日"}]
            """)
        XCTAssertEqual(calendar.holiday(on: "2026-09-28")?.name, "教師節")
        XCTAssertEqual(calendar.holiday(on: "2026-10-25")?.name, "光復節")
        XCTAssertEqual(calendar.holiday(on: "2026-10-26")?.name, "光復節補假")
        XCTAssertEqual(calendar.holiday(on: "2026-02-16")?.name, "除夕")
        XCTAssertEqual(calendar.holiday(on: "2026-12-25")?.name, "行憲紀念日")
    }

    // MARK: - Bundled years

    private func bundledStore() -> HolidayStore {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("holidays-\(UUID())")
        return HolidayStore(bundle: Bundle(for: WorkdayManager.self), cacheDirectory: empty)
    }

    func testBundledYearsAgreeWithThePublishedFlagOnEveryDay() throws {
        let store = bundledStore()
        XCTAssertTrue(store.calendar.years.isSuperset(of: [2025, 2026, 2027]))
        for year in [2025, 2026, 2027] {
            let url = try XCTUnwrap(
                Bundle(for: WorkdayManager.self).url(
                    forResource: "taiwan-calendar-\(year)", withExtension: "json"))
            let records = try HolidayCalendar.records(from: Data(contentsOf: url))
            XCTAssertTrue(HolidayStore.isComplete(records, year: year), "\(year)")
            for record in records {
                let day = "\(record.date.prefix(4))-\(record.date.dropFirst(4).prefix(2))-\(record.date.suffix(2))"
                XCTAssertEqual(store.calendar.isWorkingDay(day), !record.isHoliday, day)
            }
        }
    }

    func testBundled2026CalendarNamesTheAutumnDaysOff() {
        let calendar = bundledStore().calendar
        XCTAssertEqual(calendar.holiday(on: "2026-09-25")?.name, "中秋節")
        XCTAssertEqual(calendar.holiday(on: "2026-09-28")?.name, "教師節")
        XCTAssertEqual(calendar.holiday(on: "2026-10-09")?.name, "國慶日補假")
        XCTAssertEqual(calendar.holiday(on: "2026-10-10")?.name, "國慶日")
        XCTAssertEqual(calendar.holiday(on: "2026-10-26")?.name, "光復節補假")
        XCTAssertEqual(calendar.holiday(on: "2026-12-25")?.name, "行憲紀念日")
    }

    func testADownloadedYearJoinsTheBundledOnes() throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("holidays-\(UUID())")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        try Data(#"[{"date":"20280101","week":"六","isHoliday":true,"description":"開國紀念日"}]"#.utf8)
            .write(to: cache.appendingPathComponent(HolidayStore.fileName(for: 2028)))

        let store = HolidayStore(bundle: Bundle(for: WorkdayManager.self), cacheDirectory: cache)
        XCTAssertTrue(store.calendar.years.isSuperset(of: [2026, 2028]))
        XCTAssertEqual(store.calendar.holiday(on: "2028-01-01")?.name, "開國紀念日")
    }

    func testOnlyAWholeYearCountsAsComplete() {
        let days = (0..<365).map { HolidayCalendar.Record(date: "2028\($0)", isHoliday: false, description: "") }
        XCTAssertTrue(HolidayStore.isComplete(days, year: 2028))
        XCTAssertFalse(HolidayStore.isComplete(Array(days.prefix(200)), year: 2028), "Truncated")
        XCTAssertFalse(HolidayStore.isComplete(days, year: 2029), "Another year")
        XCTAssertEqual(HolidayStore.remoteURL(for: 2028)?.lastPathComponent, "2028.json")
    }
}
