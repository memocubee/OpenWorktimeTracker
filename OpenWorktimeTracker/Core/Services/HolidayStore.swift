import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.openworktimetracker.app", category: "Holidays")

/// Taiwan's working-day calendar for the week history: the years bundled with
/// the app, plus any later year downloaded once it is published, so the
/// calendar keeps working after the bundled years run out.
@Observable
final class HolidayStore {
    static let shared = HolidayStore()

    private(set) var calendar: HolidayCalendar

    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private let cacheDirectory: URL
    @ObservationIgnored private var lastAttempt: [Int: Date] = [:]

    private static let filePrefix = "taiwan-calendar-"
    private static let retryInterval: TimeInterval = 6 * 3600

    init(bundle: Bundle = .main, cacheDirectory: URL = HolidayStore.defaultCacheDirectory) {
        self.bundle = bundle
        self.cacheDirectory = cacheDirectory
        self.calendar = Self.load(bundle: bundle, cacheDirectory: cacheDirectory)
    }

    static var defaultCacheDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("OpenWorktimeTracker/holidays", isDirectory: true)
    }

    /// Where the DGPA calendar for `year` is published as JSON.
    static func remoteURL(for year: Int) -> URL? {
        URL(string: "https://cdn.jsdelivr.net/gh/ruyut/TaiwanCalendar/data/\(year).json")
    }

    static func fileName(for year: Int) -> String {
        "\(filePrefix)\(year).json"
    }

    /// Downloads this year and next when neither the bundle nor the cache has
    /// them, retrying a failed year at most every six hours. Next year's
    /// calendar is usually published in June.
    func refreshIfNeeded(now: Date = Date()) {
        let thisYear = Calendar(identifier: .gregorian).component(.year, from: now)
        for year in [thisYear, thisYear + 1] where !calendar.years.contains(year) {
            if let last = lastAttempt[year], now.timeIntervalSince(last) < Self.retryInterval { continue }
            lastAttempt[year] = now
            download(year)
        }
    }

    private func download(_ year: Int) {
        guard let url = Self.remoteURL(for: year) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                let records = try? HolidayCalendar.records(from: data),
                Self.isComplete(records, year: year)
            else {
                logger.info("No calendar for \(year): \(error?.localizedDescription ?? "not published")")
                return
            }
            do {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                try data.write(to: cacheDirectory.appendingPathComponent(Self.fileName(for: year)), options: .atomic)
            } catch {
                logger.error("Could not cache the \(year) calendar: \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.async {
                self.calendar = Self.load(bundle: self.bundle, cacheDirectory: self.cacheDirectory)
            }
        }.resume()
    }

    /// A whole year of days, so a truncated download is never cached.
    static func isComplete(_ records: [HolidayCalendar.Record], year: Int) -> Bool {
        records.count >= 365 && records.allSatisfy { $0.date.hasPrefix(String(year)) }
    }

    /// One file per year; a downloaded year replaces the bundled one.
    private static func load(bundle: Bundle, cacheDirectory: URL) -> HolidayCalendar {
        let bundled = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let cached =
            (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        var files: [Int: URL] = [:]
        for url in bundled + cached {
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix(filePrefix), let year = Int(name.dropFirst(filePrefix.count)) else { continue }
            files[year] = url
        }
        let records = files.values.flatMap { url -> [HolidayCalendar.Record] in
            guard let data = try? Data(contentsOf: url) else { return [] }
            return (try? HolidayCalendar.records(from: data)) ?? []
        }
        return HolidayCalendar(records: records)
    }
}
