import Foundation

extension Date {
    private static let hoursMinutesFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var hoursMinutesString: String {
        Date.hoursMinutesFormatter.string(from: self)
    }

    var dateString: String {
        TimeEntry.dateString(from: self)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }
}

/// Day arithmetic on `YYYY-MM-DD` strings, the key Daily Logs are stored by.
/// Always Gregorian and anchored at noon, so neither a Minguo calendar setting
/// nor a DST change shifts a day.
enum DayString {
    private static let calendar = Calendar(identifier: .gregorian)

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        return formatter
    }()

    /// Noon on `day`, or `nil` when it isn't a `YYYY-MM-DD` date.
    static func date(_ day: String) -> Date? {
        parser.date(from: day).flatMap { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0) }
    }

    static func adding(_ days: Int, to day: String) -> String? {
        date(day).flatMap { calendar.date(byAdding: .day, value: days, to: $0) }.map(parser.string(from:))
    }

    static func year(_ day: String) -> Int? {
        date(day).map { calendar.component(.year, from: $0) }
    }

    /// Saturday or Sunday.
    static func isWeekend(_ day: String) -> Bool {
        guard let date = date(day) else { return false }
        return [1, 7].contains(calendar.component(.weekday, from: date))
    }

    /// The Monday of the Monday-to-Sunday week `day` falls in.
    static func monday(of day: String) -> String? {
        guard let date = date(day) else { return nil }
        // weekday: 1 = Sunday … 7 = Saturday
        let daysSinceMonday = (calendar.component(.weekday, from: date) + 5) % 7
        return adding(-daysSinceMonday, to: day)
    }
}

extension TimeInterval {
    var hoursComponent: Int {
        Int(self) / 3600
    }

    var minutesComponent: Int {
        (Int(self) % 3600) / 60
    }

    var secondsComponent: Int {
        Int(self) % 60
    }

    var inHours: Double {
        self / 3600.0
    }
}
