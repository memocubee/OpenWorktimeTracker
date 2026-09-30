import Foundation

/// Why setting today's total Pause was rejected.
enum TotalPauseEditError: LocalizedError, Equatable {
    case noWorkday
    case paused
    case belowIdlePause(TimeInterval)
    case exceedsGrossTime(TimeInterval)
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .noWorkday:
            return String(localized: "pauseTotal.error.noWorkday")
        case .paused:
            return String(localized: "pauseTotal.pausedHint")
        case .belowIdlePause(let minimum):
            return String(format: String(localized: "pauseTotal.error.belowIdle"), minimum.hoursMinutesFormatted)
        case .exceedsGrossTime(let maximum):
            return String(format: String(localized: "pauseTotal.error.exceedsGross"), maximum.hoursMinutesFormatted)
        case .saveFailed:
            return String(localized: "pauseTotal.error.saveFailed")
        }
    }
}

// MARK: - Editing today's total Pause

/// The menu bar popover edits the Pause total directly, without Pause
/// intervals. The Log Editor goes through `saveEdits(_:original:)` instead.
extension WorkdayManager {

    /// The part of the Pause total the user cannot lower here: Idle Periods
    /// decided as a Pause. Changing those goes through the Log Editor.
    var idlePauseTime: TimeInterval {
        guard let current = currentWorkday else { return 0 }
        return current.payload.idlePause(endingAt: current.endTime ?? clock.now)
    }

    /// Why `total` cannot be set as today's Pause total right now, or nil.
    func totalPauseError(for total: TimeInterval) -> TotalPauseEditError? {
        guard let current = currentWorkday else { return .noWorkday }
        // An open Pause keeps growing; editing the total then would be
        // stale a second later, so ask the user to resume first.
        guard current.status != .paused else { return .paused }
        guard total.isFinite, total >= 0 else { return .belowIdlePause(0) }
        let instant = current.endTime ?? clock.now
        let idle = current.payload.idlePause(endingAt: instant)
        let gross = current.grossTime(endingAt: instant)
        // Whole minutes: the editor shows minutes, so an Idle Period of
        // 30:30 must still accept the 30:00 it was shown.
        if (total / 60).rounded(.down) < (idle / 60).rounded(.down) { return .belowIdlePause(idle) }
        if total > gross { return .exceedsGrossTime(gross) }
        return nil
    }

    /// Sets the held Workday's Pause total (the value shown under Pauses) to
    /// `total` by adjusting the manual Pause; Idle Periods decided as a Pause
    /// stay as they are.
    @discardableResult
    func setTotalPause(_ total: TimeInterval) -> TotalPauseEditError? {
        if let error = totalPauseError(for: total) { return error }
        guard let current = currentWorkday else { return .noWorkday }
        var entry = current.payload
        let idle = entry.idlePause(endingAt: current.endTime ?? clock.now)
        entry.manualPauseSeconds = max(0, total - idle)
        guard store.saveAndWait(entry) else { return .saveFailed }
        activate(workday(for: entry))
        return nil
    }
}
