import Foundation

struct TimeEntry: Codable, Identifiable {
    let id: UUID
    var date: String  // YYYY-MM-DD
    var startTime: Date
    var endTime: Date?
    var status: Status
    var manualPauseSeconds: TimeInterval
    var pauseStartedAt: Date?
    var idleDecisions: [IdleDecision]
    var notifiedThresholds: Set<NotifiedThreshold>
    var note: String
    var lastActivityTime: Date?

    /// Maps onto `WorkdayState`, which adds `notStarted` for when no Daily Log exists.
    enum Status: String, Codable {
        case running
        case paused
        case ended
    }

    init(
        id: UUID = UUID(),
        date: String? = nil,
        startTime: Date = Date(),
        endTime: Date? = nil,
        status: Status = .running,
        manualPauseSeconds: TimeInterval = 0,
        pauseStartedAt: Date? = nil,
        idleDecisions: [IdleDecision] = [],
        notifiedThresholds: Set<NotifiedThreshold> = [],
        note: String = "",
        lastActivityTime: Date? = nil
    ) {
        self.id = id
        self.date = date ?? Self.dateString(from: startTime)
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.manualPauseSeconds = manualPauseSeconds
        self.pauseStartedAt = pauseStartedAt
        self.idleDecisions = idleDecisions
        self.notifiedThresholds = notifiedThresholds
        self.note = note
        self.lastActivityTime = lastActivityTime
    }

    // MARK: - Computed Properties

    var grossTime: TimeInterval {
        let end = endTime ?? Date()
        return max(0, end.timeIntervalSince(startTime))
    }

    var totalManualPause: TimeInterval {
        var pause = manualPauseSeconds
        if status == .paused, let pauseStart = pauseStartedAt {
            pause += Date().timeIntervalSince(pauseStart)
        }
        return pause
    }

    var totalIdlePause: TimeInterval {
        idlePause(endingAt: endTime ?? Date())
    }

    func idlePause(endingAt instant: Date) -> TimeInterval {
        let end = min(instant, endTime ?? instant)
        let intervals = idleDecisions
            .filter { $0.decision == .pause }
            .map { (start: max(startTime, $0.idleStart), end: min(end, $0.idleEnd)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var coveredUntil = startTime
        var total: TimeInterval = 0
        for interval in intervals {
            total += max(0, interval.end.timeIntervalSince(max(coveredUntil, interval.start)))
            coveredUntil = max(coveredUntil, interval.end)
        }
        return total
    }

    private static let dateStringFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func dateString(from date: Date) -> String {
        dateStringFormatter.string(from: date)
    }
}

/// A Notification Threshold a Workday has already notified, as recorded in its
/// Daily Log.
///
/// String-backed rather than an enum: it encodes as exactly the shipped
/// strings, and a value this version doesn't know (a hand edit, a newer
/// version) is kept instead of making the whole Daily Log unreadable.
struct NotifiedThreshold: RawRepresentable, Hashable, Codable {
    let rawValue: String

    static let normal = NotifiedThreshold(rawValue: "normal")
    static let critical = NotifiedThreshold(rawValue: "critical")
    static let milestone = NotifiedThreshold(rawValue: "milestone")
}

struct IdleDecision: Codable, Identifiable {
    let id: UUID
    let idleStart: Date
    let idleEnd: Date
    var decision: Decision

    enum Decision: String, Codable {
        case work  // Count as work time (meeting, thinking)
        case pause  // Deduct from work time
    }

    var duration: TimeInterval {
        idleEnd.timeIntervalSince(idleStart)
    }

    init(id: UUID = UUID(), idleStart: Date, idleEnd: Date, decision: Decision) {
        self.id = id
        self.idleStart = idleStart
        self.idleEnd = idleEnd
        self.decision = decision
    }
}

extension WorkdayState {
    init(_ status: TimeEntry.Status) {
        switch status {
        case .running: self = .running
        case .paused: self = .paused
        case .ended: self = .ended
        }
    }
}
