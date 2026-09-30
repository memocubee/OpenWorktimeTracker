import Foundation

// MARK: - Editing Pause Intervals

/// Edits to the held Workday's Pause Intervals from the menu bar popover. The
/// Log Editor goes through `saveEdits(_:original:)` instead.
extension WorkdayManager {

    /// Moves or shortens one Pause. An open Pause keeps running; only its
    /// start changes.
    @discardableResult
    func updatePause(_ pause: PauseInterval) -> PauseEditError? {
        commitPauseEdit { $0.replacePause(pause) }
    }

    /// Deleting the open Pause puts the Workday back to running, as if the
    /// user had never pressed Pause.
    @discardableResult
    func deletePause(id: UUID) -> PauseEditError? {
        commitPauseEdit { $0.removePause(id: id) }
    }

    /// Changes the aggregate Pause kept by Daily Logs from before Pause
    /// Intervals existed.
    @discardableResult
    func updateLegacyPauseSeconds(_ seconds: TimeInterval) -> PauseEditError? {
        guard seconds.isFinite, seconds >= 0 else { return .endNotAfterStart }
        return commitPauseEdit { $0.manualPauseSeconds = seconds }
    }

    /// Validates, persists and republishes the held Workday after `change`,
    /// or leaves everything untouched and says why.
    private func commitPauseEdit(_ change: (inout TimeEntry) -> Void) -> PauseEditError? {
        guard let current = currentWorkday else { return .noWorkday }
        var entry = current.payload
        change(&entry)
        entry.snapPausesIntoWorkday(now: clock.now)
        if let error = entry.pauseValidationError(now: clock.now) {
            return error
        }
        guard store.saveAndWait(entry) else { return .saveFailed }
        activate(workday(for: entry))
        return nil
    }
}
