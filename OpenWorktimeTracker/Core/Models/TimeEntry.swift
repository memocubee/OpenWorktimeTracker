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

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey {
        case id, date, startTime, endTime, status, manualPauseSeconds, pauseStartedAt
        case idleDecisions, notifiedThresholds, note, lastActivityTime
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

// MARK: - Reading Daily Logs written by 0.7.2

/// Version 0.7.2 recorded each Pause as an interval under a `pauses` key. Only
/// the total is kept now: closed intervals are folded into
/// `manualPauseSeconds` and an open one becomes `pauseStartedAt`. `pauses` is
/// never written back, so the next save restores the shipped format.
extension TimeEntry {
    private enum V072Keys: String, CodingKey {
        case pauses
    }

    private struct V072Pause: Decodable {
        let start: Date
        let end: Date?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            date: try container.decode(String.self, forKey: .date),
            startTime: try container.decode(Date.self, forKey: .startTime),
            endTime: try container.decodeIfPresent(Date.self, forKey: .endTime),
            status: try container.decode(Status.self, forKey: .status),
            manualPauseSeconds: try container.decode(TimeInterval.self, forKey: .manualPauseSeconds),
            pauseStartedAt: try container.decodeIfPresent(Date.self, forKey: .pauseStartedAt),
            idleDecisions: try container.decode([IdleDecision].self, forKey: .idleDecisions),
            notifiedThresholds: try container.decode(Set<NotifiedThreshold>.self, forKey: .notifiedThresholds),
            note: try container.decode(String.self, forKey: .note),
            lastActivityTime: try container.decodeIfPresent(Date.self, forKey: .lastActivityTime)
        )
        let v072 = try decoder.container(keyedBy: V072Keys.self)
        let pauses = try v072.decodeIfPresent([V072Pause].self, forKey: .pauses) ?? []
        for pause in pauses {
            if let end = pause.end {
                let start = max(pause.start, startTime)
                let clampedEnd = endTime.map { min(end, $0) } ?? end
                manualPauseSeconds += max(0, clampedEnd.timeIntervalSince(start))
            } else {
                pauseStartedAt = pause.start
            }
        }
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
