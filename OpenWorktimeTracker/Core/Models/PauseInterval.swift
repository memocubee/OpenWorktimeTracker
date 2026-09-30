import Foundation

/// One Pause the user took with the Pause button, or entered by hand, as
/// recorded in the Daily Log. `end` is nil while the Pause is still open.
///
/// Daily Logs written before Pause Intervals existed only carry the aggregate
/// `manualPauseSeconds`. That aggregate is kept as-is and still counts, so the
/// total manual Pause is always:
///
///     manualPauseSeconds (legacy aggregate)
///       + every closed Pause Interval
///       + the open Pause Interval up to now (or the Workday's end)
///
/// Every interval is clipped to the Workday before it is counted.
struct PauseInterval: Codable, Identifiable, Equatable {
    let id: UUID
    var start: Date
    var end: Date?

    init(id: UUID = UUID(), start: Date, end: Date? = nil) {
        self.id = id
        self.start = start
        self.end = end
    }

    var isOpen: Bool { end == nil }

    func duration(endingAt instant: Date) -> TimeInterval {
        max(0, (end ?? instant).timeIntervalSince(start))
    }
}

/// Why an edit to the Pause Intervals was rejected. Overlaps are rejected
/// rather than merged, so an edit never silently changes another Pause.
enum PauseEditError: LocalizedError, Equatable {
    case endNotAfterStart
    case outsideWorkday
    case inFuture
    case overlapping
    case noWorkday
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .endNotAfterStart: return String(localized: "pauses.error.endNotAfterStart")
        case .outsideWorkday: return String(localized: "pauses.error.outsideWorkday")
        case .inFuture: return String(localized: "pauses.error.inFuture")
        case .overlapping: return String(localized: "pauses.error.overlapping")
        case .noWorkday: return String(localized: "pauses.error.noWorkday")
        case .saveFailed: return String(localized: "pauses.error.saveFailed")
        }
    }
}

/// Measures how much of a time span a set of intervals covers, counting any
/// overlap once.
enum TimeCoverage {
    static func covered(_ intervals: [(start: Date, end: Date)], from lower: Date, to upper: Date)
        -> TimeInterval {
        let clipped = intervals
            .map { (start: max(lower, $0.start), end: min(upper, $0.end)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var coveredUntil = lower
        var total: TimeInterval = 0
        for interval in clipped {
            total += max(0, interval.end.timeIntervalSince(max(coveredUntil, interval.start)))
            coveredUntil = max(coveredUntil, interval.end)
        }
        return total
    }
}

// MARK: - Deriving Pause from a Daily Log

extension TimeEntry {

    /// The open Pause Interval, if the user is on a break right now.
    var openPause: PauseInterval? {
        pauses.first { $0.end == nil }
    }

    /// When the current break began: the open interval's start, or for a
    /// Daily Log paused by a version without intervals, `pauseStartedAt`.
    var currentPauseStart: Date? {
        guard status == .paused else { return nil }
        return openPause?.start ?? pauseStartedAt
    }

    /// Pause Intervals as closed spans ending no later than `instant`.
    func pauseSpans(endingAt instant: Date) -> [(start: Date, end: Date)] {
        pauses.map { (start: $0.start, end: $0.end ?? instant) }
    }

    func idlePauseSpans() -> [(start: Date, end: Date)] {
        idleDecisions
            .filter { $0.decision == .pause }
            .map { (start: $0.idleStart, end: $0.idleEnd) }
    }

    /// An open Pause from a Daily Log written before Pause Intervals existed.
    func legacyOpenPause(endingAt instant: Date) -> TimeInterval {
        guard status == .paused, openPause == nil, let openedAt = pauseStartedAt else { return 0 }
        return max(0, instant.timeIntervalSince(max(openedAt, startTime)))
    }

    /// Pause the user took deliberately, including one still open at `instant`.
    func manualPause(endingAt instant: Date) -> TimeInterval {
        let upper = min(instant, endTime ?? instant)
        return manualPauseSeconds + legacyOpenPause(endingAt: instant)
            + TimeCoverage.covered(pauseSpans(endingAt: upper), from: startTime, to: upper)
    }

    /// Every Pause counted against the Workday. A Pause Interval and an Idle
    /// Period decided as a Pause that overlap are only deducted once.
    func totalPause(endingAt instant: Date) -> TimeInterval {
        let upper = min(instant, endTime ?? instant)
        let spans = pauseSpans(endingAt: upper) + idlePauseSpans()
        return manualPauseSeconds + legacyOpenPause(endingAt: instant)
            + TimeCoverage.covered(spans, from: startTime, to: upper)
    }
}

// MARK: - Changing Pause Intervals

extension TimeEntry {

    /// Closes whatever Pause is open at `instant`. A Pause closed at or before
    /// its own start never happened and is dropped, so it can't subtract time.
    mutating func closeOpenPause(at instant: Date) {
        if pauses.contains(where: { $0.end == nil }) {
            pauses = pauses.compactMap { pause in
                guard pause.end == nil else { return pause }
                guard instant > pause.start else { return nil }
                var closed = pause
                closed.end = instant
                return closed
            }
        } else if status == .paused, let openedAt = pauseStartedAt {
            // Opened by a version that only kept the aggregate: record it now.
            let start = max(openedAt, startTime)
            if instant > start {
                pauses.append(PauseInterval(start: start, end: instant))
            }
        }
        pauseStartedAt = nil
        sortPauses()
    }

    mutating func replacePause(_ updated: PauseInterval) {
        guard let index = pauses.firstIndex(where: { $0.id == updated.id }) else { return }
        pauses[index] = updated
        if updated.end == nil, status == .paused {
            pauseStartedAt = updated.start
        }
        sortPauses()
    }

    mutating func addPause(_ pause: PauseInterval) {
        pauses.append(pause)
        sortPauses()
    }

    /// Removing the open Pause means the user never went on that break, so
    /// the Workday is running again.
    mutating func removePause(id: UUID) {
        guard let index = pauses.firstIndex(where: { $0.id == id }) else { return }
        let removed = pauses.remove(at: index)
        if removed.end == nil, status == .paused {
            pauseStartedAt = nil
            status = .running
        }
    }

    /// Applies only what the editor changed, field by field, so a Pause the
    /// timer closed while the editor was open isn't reopened by a stale copy.
    mutating func applyPauseEdits(from original: [PauseInterval], to edited: [PauseInterval], now: Date) {
        guard edited != original else { return }
        defer { snapPausesIntoWorkday(now: now) }
        for before in original where !edited.contains(where: { $0.id == before.id }) {
            removePause(id: before.id)
        }
        for after in edited {
            guard let before = original.first(where: { $0.id == after.id }) else {
                addPause(after)
                continue
            }
            guard before != after, var latest = pauses.first(where: { $0.id == after.id }) else { continue }
            if after.start != before.start { latest.start = after.start }
            if after.end != before.end { latest.end = after.end }
            replacePause(latest)
        }
    }

    /// DatePickers edit hours and minutes but keep the seconds they started
    /// with, so a Pause picked as 09:00 on a Workday started at 09:00:37 lands
    /// a few seconds outside it. Snap anything within a minute back inside.
    mutating func snapPausesIntoWorkday(now: Date, tolerance: TimeInterval = 60) {
        let upper = endTime ?? now
        for index in pauses.indices {
            let start = pauses[index].start
            if start < startTime, startTime.timeIntervalSince(start) < tolerance {
                pauses[index].start = startTime
            }
            if let end = pauses[index].end, end > upper, end.timeIntervalSince(upper) < tolerance {
                pauses[index].end = upper
            }
        }
        if let open = openPause, status == .paused {
            pauseStartedAt = open.start
        }
    }

    private mutating func sortPauses() {
        pauses.sort { $0.start < $1.start }
    }

    /// Checks every Pause Interval against the Workday: each must end after it
    /// starts, lie within the Workday and not in the future, and not overlap
    /// another Pause Interval.
    func pauseValidationError(now: Date) -> PauseEditError? {
        let upper = endTime ?? now
        var previousEnd: Date?
        for pause in pauses.sorted(by: { $0.start < $1.start }) {
            let end = pause.end ?? now
            guard pause.start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite else {
                return .endNotAfterStart
            }
            if let closedEnd = pause.end, closedEnd <= pause.start { return .endNotAfterStart }
            if pause.start > now || end > now { return .inFuture }
            if pause.start < startTime || end > upper { return .outsideWorkday }
            if let previousEnd, pause.start < previousEnd { return .overlapping }
            previousEnd = end
        }
        return nil
    }
}
