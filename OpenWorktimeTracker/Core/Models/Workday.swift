import Foundation

/// One person's tracked time for a single calendar date, paired with the
/// configuration needed to make sense of it.
///
/// The pairing is the point: a Workday cannot be constructed without Auto Break
/// Rules and a Threshold Ladder, so no caller can derive Net Work Time with the
/// wrong ones.
struct Workday {

    /// The Daily Log payload. Persisted verbatim; the on-disk JSON format is
    /// `TimeEntry`'s and must not follow this type around.
    private(set) var payload: TimeEntry

    private(set) var autoBreakRules: AutoBreakRules
    private(set) var thresholds: ThresholdLadder

    init(payload: TimeEntry, autoBreakRules: AutoBreakRules, thresholds: ThresholdLadder) {
        self.payload = payload
        self.autoBreakRules = autoBreakRules
        self.thresholds = thresholds
    }

    /// Resolves configuration from user settings.
    init(payload: TimeEntry, defaults: UserDefaults = .standard) {
        self.init(
            payload: payload,
            autoBreakRules: .resolved(from: defaults),
            thresholds: .resolved(from: defaults)
        )
    }

    // MARK: - Payload passthrough

    var id: UUID { payload.id }
    var date: String { payload.date }
    var startTime: Date { payload.startTime }
    var endTime: Date? { payload.endTime }
    var status: TimeEntry.Status { payload.status }
    var note: String { payload.note }

    // MARK: - Derivation

    /// The instant this Workday is measured to: its end, or now while it runs.
    private var measuredTo: Date { payload.endTime ?? Date() }

    var grossTime: TimeInterval { grossTime(endingAt: measuredTo) }
    var manualPause: TimeInterval { manualPause(endingAt: measuredTo) }
    var pause: TimeInterval { pause(endingAt: measuredTo) }
    var autoBreak: TimeInterval { autoBreak(endingAt: measuredTo) }
    var netWorkTime: TimeInterval { netWorkTime(endingAt: measuredTo) }
    var thresholdLevel: ThresholdLevel { thresholds.level(for: netWorkTime) }

    func grossTime(endingAt instant: Date) -> TimeInterval {
        max(0, min(instant, payload.endTime ?? instant).timeIntervalSince(payload.startTime))
    }

    /// Pause the user took deliberately, including one still open at `instant`.
    func manualPause(endingAt instant: Date) -> TimeInterval {
        var total = payload.manualPauseSeconds
        if payload.status == .paused, let openedAt = payload.pauseStartedAt {
            total += max(0, instant.timeIntervalSince(max(openedAt, startTime)))
        }
        return total
    }

    /// Idle Periods the user decided were a Pause.
    var idlePause: TimeInterval { payload.idlePause(endingAt: measuredTo) }

    /// Every Pause counted against the Workday.
    func pause(endingAt instant: Date) -> TimeInterval {
        manualPause(endingAt: instant) + payload.idlePause(endingAt: instant)
    }

    func autoBreak(endingAt instant: Date) -> TimeInterval {
        let taken = pause(endingAt: instant)
        return autoBreakRules.autoBreak(
            forWorkTime: workBeforeAutoBreak(endingAt: instant, pause: taken),
            alreadyPaused: taken
        )
    }

    func netWorkTime(endingAt instant: Date) -> TimeInterval {
        let taken = pause(endingAt: instant)
        let worked = workBeforeAutoBreak(endingAt: instant, pause: taken)
        let owed = autoBreakRules.autoBreak(forWorkTime: worked, alreadyPaused: taken)
        return max(0, worked - owed)
    }

    func thresholdLevel(endingAt instant: Date) -> ThresholdLevel {
        thresholds.level(for: netWorkTime(endingAt: instant))
    }

    /// Gross Time left after every Pause, before any Auto Break is owed.
    private func workBeforeAutoBreak(endingAt instant: Date, pause: TimeInterval) -> TimeInterval {
        max(0, grossTime(endingAt: instant) - pause)
    }

    // MARK: - Transitions

    // Pure and value-returning. Persisting the result, stopping timers and
    // dismissing prompts stay with WorkdayManager.

    func paused(at instant: Date) -> Workday {
        guard payload.status == .running else { return self }
        return mutating {
            $0.pauseStartedAt = instant
            $0.status = .paused
        }
    }

    func resumed(at instant: Date) -> Workday {
        guard payload.status == .paused else { return self }
        return mutating {
            $0.manualPauseSeconds += closingOpenPause(at: instant)
            $0.pauseStartedAt = nil
            $0.status = .running
        }
    }

    /// Closes any open Pause and ends the Workday. Ending an already-ended
    /// Workday is a no-op, so a second call cannot overwrite the recorded end.
    func ended(at instant: Date) -> Workday {
        guard payload.status != .ended else { return self }
        let end = max(startTime, instant)
        return mutating {
            $0.manualPauseSeconds += closingOpenPause(at: end)
            $0.pauseStartedAt = nil
            $0.status = .ended
            $0.endTime = end
        }
    }

    func reopened(at instant: Date) -> Workday {
        guard payload.status == .ended, let end = endTime else { return self }
        return mutating {
            if instant > end {
                $0.idleDecisions.append(
                    IdleDecision(idleStart: end, idleEnd: instant, decision: .pause))
            }
            $0.endTime = nil
            $0.status = .running
        }
    }

    func withNote(_ note: String) -> Workday {
        mutating { $0.note = note }
    }

    func withStartTime(_ instant: Date) -> Workday {
        mutating { $0.startTime = instant }
    }

    func withEndTime(_ instant: Date) -> Workday {
        mutating { $0.endTime = instant }
    }

    func recording(_ decision: IdleDecision) -> Workday {
        mutating { $0.idleDecisions.append(decision) }
    }

    func markingNotified(_ threshold: NotifiedThreshold) -> Workday {
        mutating { $0.notifiedThresholds.insert(threshold) }
    }

    func recordingActivity(at instant: Date) -> Workday {
        guard status == .running else { return self }
        return mutating { $0.lastActivityTime = max(startTime, instant) }
    }

    /// Re-resolves configuration so a settings change reaches a Workday that is
    /// already being held.
    func reconfigured(defaults: UserDefaults = .standard) -> Workday {
        Workday(payload: payload, defaults: defaults)
    }

    /// The Pause seconds accrued since an open Pause was opened. Clamped, so an
    /// instant before the Pause opened never subtracts time.
    private func closingOpenPause(at instant: Date) -> TimeInterval {
        guard let openedAt = payload.pauseStartedAt else { return 0 }
        return max(0, instant.timeIntervalSince(max(openedAt, startTime)))
    }

    private func mutating(_ change: (inout TimeEntry) -> Void) -> Workday {
        var updated = payload
        change(&updated)
        return Workday(payload: updated, autoBreakRules: autoBreakRules, thresholds: thresholds)
    }
}
