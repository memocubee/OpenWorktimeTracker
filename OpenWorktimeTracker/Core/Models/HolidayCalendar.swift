import Foundation

/// A day off on Taiwan's official calendar: a Public Holiday, or the make-up
/// day off (補假) given when one falls on a weekend.
struct Holiday: Equatable {
    let date: String  // YYYY-MM-DD
    /// Short display name, e.g. 國慶日 or 國慶日補假; empty when the calendar gives none.
    let name: String
}

/// Taiwan's working-day calendar (行政機關辦公日曆表): which weekdays are
/// Public Holidays and which weekend days are working days. Years it has no
/// data for fall back to Monday to Friday.
struct HolidayCalendar: Equatable {

    /// One day as published by ruyut/TaiwanCalendar from the DGPA's open data.
    struct Record: Decodable, Equatable {
        let date: String  // YYYYMMDD
        let isHoliday: Bool
        let description: String
    }

    static let empty = HolidayCalendar(records: [])

    /// Every weekday off plus every named day off, by YYYY-MM-DD.
    let holidays: [String: Holiday]
    /// Weekend days made working days (補行上班), by YYYY-MM-DD.
    let makeUpWorkdays: Set<String>
    /// Years the calendar has data for.
    let years: Set<Int>

    static func records(from data: Data) throws -> [Record] {
        try JSONDecoder().decode([Record].self, from: data)
    }

    init(records: [Record]) {
        var named: [String: String] = [:]
        var daysOff: [String] = []
        var makeUpWorkdays: Set<String> = []
        var years: Set<Int> = []
        for record in records {
            guard let day = Self.dayString(record.date) else { continue }
            if let year = DayString.year(day) { years.insert(year) }
            let weekend = DayString.isWeekend(day)
            if record.isHoliday {
                if !record.description.isEmpty { named[day] = record.description }
                if !weekend || !record.description.isEmpty { daysOff.append(day) }
            } else if weekend {
                makeUpWorkdays.insert(day)
            }
        }

        var holidays: [String: Holiday] = [:]
        for day in daysOff {
            let name = named[day].map { $0 == Self.makeUpDayOff ? Self.makeUpName(for: day, named: named) : $0 }
            holidays[day] = Holiday(date: day, name: name.map(Self.shortName) ?? "")
        }
        self.holidays = holidays
        self.makeUpWorkdays = makeUpWorkdays
        self.years = years
    }

    func holiday(on day: String) -> Holiday? {
        holidays[day]
    }

    /// Whether the calendar expects work on `day`: Monday to Friday unless a
    /// day off, plus any weekend day made a working day.
    func isWorkingDay(_ day: String) -> Bool {
        if holidays[day] != nil { return false }
        if makeUpWorkdays.contains(day) { return true }
        return !DayString.isWeekend(day)
    }

    // MARK: - Names

    private static let makeUpDayOff = "補假"

    /// Official names too long for a one-line list.
    private static let shortNames = [
        "孔子誕辰紀念日/教師節": "教師節",
        "孔子誕辰紀念日": "教師節",
        "臺灣光復暨金門古寧頭大捷紀念日": "光復節",
        "兒童節及民族掃墓節": "兒童節及清明節",
        "農曆除夕": "除夕"
    ]

    private static func shortName(_ name: String) -> String {
        if name.hasSuffix(makeUpDayOff), name != makeUpDayOff {
            let holiday = String(name.dropLast(makeUpDayOff.count))
            return (shortNames[holiday] ?? holiday) + makeUpDayOff
        }
        return shortNames[name] ?? name
    }

    /// Names a 補假 after the holiday it makes up for: the nearest named
    /// holiday within five days, preferring one that fell on a weekend.
    private static func makeUpName(for day: String, named: [String: String]) -> String {
        let nearby = (1...5).flatMap { [-$0, $0] }.compactMap { offset -> (day: String, name: String)? in
            guard let other = DayString.adding(offset, to: day),
                let name = named[other], name != makeUpDayOff
            else { return nil }
            return (other, name)
        }
        let source = nearby.first { DayString.isWeekend($0.day) } ?? nearby.first
        return source.map { $0.name + makeUpDayOff } ?? makeUpDayOff
    }

    /// `20261010` → `2026-10-10`.
    private static func dayString(_ compact: String) -> String? {
        guard compact.count == 8, compact.allSatisfy(\.isNumber) else { return nil }
        let year = compact.prefix(4)
        let month = compact.dropFirst(4).prefix(2)
        let day = compact.suffix(2)
        return "\(year)-\(month)-\(day)"
    }
}
