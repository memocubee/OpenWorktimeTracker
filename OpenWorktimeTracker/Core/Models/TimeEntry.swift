import Foundation

struct TimeEntry: Codable, Identifiable {
    let id: UUID
    var date: String  // YYYY-MM-DD
    var startTime: Date
    var endTime: Date?
    var status: Status
    var manualPauseSeconds: TimeInterval
    var pauseStartedAt: Date?
    /// Each Pause the user took. Absent from Daily Logs written before Pause
    /// Intervals existed; see `PauseInterval` for how both are counted.
    var pauses: [PauseInterval]
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
        pauses: [PauseInterval] = [],
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
        self.pauses = pauses
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
        manualPause(endingAt: endTime ?? Date())
    }

    var totalIdlePause: TimeInterval {
        idlePause(endingAt: endTime ?? Date())
    }

    func idlePause(endingAt instant: Date) -> TimeInterval {
        let end = min(instant, endTime ?? instant)
        return TimeCoverage.covered(idlePauseSpans(), from: startTime, to: end)
    }

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey {
        case id, date, startTime, endTime, status, manualPauseSeconds, pauseStartedAt
        case pauses, idleDecisions, notifiedThresholds, note, lastActivityTime
    }

    /// Daily Logs written before Pause Intervals existed have no `pauses` key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(String.self, forKey: .date)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        status = try container.decode(Status.self, forKey: .status)
        manualPauseSeconds = try container.decode(TimeInterval.self, forKey: .manualPauseSeconds)
        pauseStartedAt = try container.decodeIfPresent(Date.self, forKey: .pauseStartedAt)
        pauses = try container.decodeIfPresent([PauseInterval].self, forKey: .pauses) ?? []
        idleDecisions = try container.decode([IdleDecision].self, forKey: .idleDecisions)
        notifiedThresholds = try container.decode(Set<NotifiedThreshold>.self, forKey: .notifiedThresholds)
        note = try container.decode(String.self, forKey: .note)
        lastActivityTime = try container.decodeIfPresent(Date.self, forKey: .lastActivityTime)
    }

    /// Writes the shipped keys unchanged; `pauses` only once there is one, so a
    /// day without breaks keeps the shipped file format.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encode(status, forKey: .status)
        try container.encode(manualPauseSeconds, forKey: .manualPauseSeconds)
        try container.encodeIfPresent(pauseStartedAt, forKey: .pauseStartedAt)
        if !pauses.isEmpty {
            try container.encode(pauses, forKey: .pauses)
        }
        try container.encode(idleDecisions, forKey: .idleDecisions)
        try container.encode(notifiedThresholds, forKey: .notifiedThresholds)
        try container.encode(note, forKey: .note)
        try container.encodeIfPresent(lastActivityTime, forKey: .lastActivityTime)
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
