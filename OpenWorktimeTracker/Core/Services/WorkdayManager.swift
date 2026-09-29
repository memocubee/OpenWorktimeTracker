import AppKit
import Foundation
import Observation
import WidgetKit
import os.log

private let logger = Logger(subsystem: "com.openworktimetracker.app", category: "Workday")

@Observable
final class WorkdayManager {

    // MARK: - State

    private(set) var state: WorkdayState = .notStarted
    private(set) var currentWorkday: Workday?
    private(set) var displayTime: TimeInterval = 0
    private(set) var grossTime: TimeInterval = 0
    private(set) var autoBreak: TimeInterval = 0
    private(set) var pauseTime: TimeInterval = 0
    private(set) var netTime: TimeInterval = 0
    private(set) var logRevision = 0
    private(set) var logMutationError: DailyLogMutationError?

    private(set) var notificationThresholds: NotificationThresholds
    private(set) var newDayStartHour: Int

    /// The Idle Period awaiting a decision, if any. WorkdayManager owns this;
    /// IdleDetector only signals once and keeps no externally-visible state.
    ///
    /// Not `private(set)`: tests set this directly to stage a pending Idle
    /// Period without going through `bootstrap()`, the same way `IdleDetector`'s
    /// own `isIdle`/`idleStartTime` are poked directly by its tests.
    var pendingIdlePeriod: IdlePeriod?

    /// The Daily Log payload behind the current Workday.
    var currentEntry: TimeEntry? { currentWorkday?.payload }

    // MARK: - Services

    let persistence = PersistenceManager()
    let idleDetector: IdleDetector
    private let notifications: WorkdayNotificationSending
    private let defaults: UserDefaults
    private let clock: Clock
    private let store: DailyLogStore
    private let prompts: WorkdayPromptPresenting
    private let widgetStore: SharedDefaults

    init(
        defaults: UserDefaults = .standard,
        clock: Clock = SystemClock(),
        store: DailyLogStore? = nil,
        idleDetector: IdleDetector? = nil,
        prompts: WorkdayPromptPresenting = IdlePromptWindowController.shared,
        notifications: WorkdayNotificationSending = NotificationManager.shared,
        widgetStore: SharedDefaults = .shared
    ) {
        self.defaults = defaults
        self.clock = clock
        self.store = store ?? persistence
        self.idleDetector = idleDetector ?? IdleDetector(clock: clock)
        self.prompts = prompts
        self.notifications = notifications
        self.widgetStore = widgetStore
        self.notificationThresholds = .resolved(from: defaults)
        self.newDayStartHour = Self.resolvedNewDayStartHour(from: defaults)
        self.idleDetector.idleThreshold = .resolved(from: defaults)
    }

    private static func resolvedNewDayStartHour(from defaults: UserDefaults) -> Int {
        defaults.object(forKey: AppSettingsKey.newDayStartHour) as? Int
            ?? AppDefaults.newDayStartHour
    }

    /// Pairs a Daily Log payload with the configured Auto Break Rules and
    /// Threshold Ladder. The one place configuration is resolved.
    func workday(for entry: TimeEntry) -> Workday {
        Workday(payload: entry, defaults: defaults)
    }

    private var timer: Timer?
    private var lastSaveTime: Date?
    private var hasBootstrapped = false
    private var observers: [Any] = []

    deinit {
        timer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    // MARK: - Initialization

    func bootstrap() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        registerForSleepWake()

        idleDetector.onPeriodEnded = { [weak self] detectedPeriod in
            guard let self, self.state == .running, let current = self.currentWorkday else { return }
            let detector = WorkdayDetector(newDayStartHour: self.newDayStartHour)
            let period = IdlePeriod(
                idleStart: detectedPeriod.idleStart,
                idleEnd: detectedPeriod.idleEnd,
                spansMidnight: current.date < detector.effectiveDateString(for: detectedPeriod.idleEnd))
            self.pendingIdlePeriod = period
            self.prompts.show(idlePeriod: period, manager: self)
        }

        // Global keyboard shortcuts
        let shortcuts = GlobalShortcutManager.shared
        shortcuts.onPauseResume = { [weak self] in
            guard let self else { return }
            switch self.state {
            case .running: self.pause()
            case .paused: self.resume()
            case .notStarted: self.startNewDay()
            case .ended: break
            }
        }
        shortcuts.onEndDay = { [weak self] in
            guard let self else { return }
            if self.state == .running || self.state == .paused {
                self.endDay()
            }
        }
        shortcuts.register()

        registerForSettingsChanges()
        store.syncWithCloud()
        evaluateWorkday()
    }

    /// The held Workday carries resolved configuration, so a settings change has
    /// to be pushed into it rather than picked up on the next derivation.
    ///
    /// Scoped to `.standard`: widget publication writes to the app group
    /// suite on every tick, and an unscoped observer would retrigger itself.
    private func registerForSettingsChanges() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: defaults,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.notificationThresholds = .resolved(from: self.defaults)
                self.newDayStartHour = Self.resolvedNewDayStartHour(from: self.defaults)
                self.idleDetector.idleThreshold = .resolved(from: self.defaults)
                guard let workday = self.currentWorkday else { return }
                self.currentWorkday = workday.reconfigured(defaults: self.defaults)
                self.updateComputedValues()
            }
        )
    }

    // MARK: - Workday Detection

    func evaluateWorkday() {
        guard pendingIdlePeriod == nil, !idleDetector.isIdle else { return }
        let detector = WorkdayDetector(newDayStartHour: newDayStartHour)
        let todayEntry = store.load(for: detector.effectiveDateString(for: clock.now))
        let mostRecent = store.loadMostRecentEntry()

        let action = detector.evaluate(todayEntry: todayEntry, mostRecentEntry: mostRecent, now: clock.now)

        switch action {
        case .continueExisting(let entry):
            activate(workday(for: entry))

        case .startFreshDay:
            if isManualPunchMode {
                resetToNotStarted()
            } else {
                startNewDay()
            }

        case .endPreviousAndStartNew(let previous, let suggestedEnd):
            // Auto-end the previous day and start new. `ended(at:)` closes any
            // Pause that was still open so the Net Work Time stays correct.
            store.save(workday(for: previous).ended(at: suggestedEnd).payload)
            if isManualPunchMode {
                resetToNotStarted()
            } else {
                startNewDay()
            }

        case .dayAlreadyEnded(let entry):
            activate(workday(for: entry))
        }
    }

    /// Fork: in manual punch mode the day waits for the user's Start click.
    private var isManualPunchMode: Bool {
        defaults.object(forKey: AppSettingsKey.manualPunchMode) as? Bool
            ?? AppDefaults.manualPunchMode
    }

    private func resetToNotStarted() {
        guard state != .notStarted || currentWorkday != nil else { return }
        currentWorkday = nil
        state = .notStarted
        stopTimer()
        idleDetector.stopMonitoring()
        updateComputedValues()
        logRevision += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Actions

    func startNewDay() {
        startDay(at: clock.now)
    }

    private func startDay(at instant: Date) {
        let detector = WorkdayDetector(newDayStartHour: newDayStartHour)
        let date = detector.effectiveDateString(for: clock.now)
        if let current = currentWorkday, current.date == date {
            return
        }
        if let existing = store.load(for: date) {
            activate(workday(for: existing))
            return
        }
        let started = workday(for: TimeEntry(date: date, startTime: instant, lastActivityTime: instant))
        store.save(started.payload)
        activate(started)
        if notificationThresholds.enabled {
            notifications.sendNewDayNotification()
        }
    }

    func pause() {
        guard state == .running, let current = currentWorkday else { return }
        let paused = current.paused(at: clock.now)
        store.save(paused.payload)
        activate(paused)
    }

    func resume() {
        guard state == .paused, let current = currentWorkday else { return }
        let detector = WorkdayDetector(newDayStartHour: newDayStartHour)
        if detector.effectiveDateString(for: clock.now) > current.date {
            finish(at: detector.startOfEffectiveDay(for: clock.now))
            startNewDay()
            return
        }
        let resumed = current.resumed(at: clock.now)
        store.save(resumed.payload)
        activate(resumed)
    }

    func endDay() {
        finish(at: clock.now)
    }

    func restartDay() {
        guard let current = currentWorkday, state == .ended else { return }
        let detector = WorkdayDetector(newDayStartHour: newDayStartHour)
        guard current.date == detector.effectiveDateString(for: clock.now) else {
            startNewDay()
            return
        }
        let restarted = current.reopened(at: clock.now)
        store.save(restarted.payload)
        activate(restarted)
    }

    private func activate(_ workday: Workday) {
        currentWorkday = workday
        state = WorkdayState(workday.status)
        startTimer()
        if state == .running {
            idleDetector.startMonitoring()
        } else {
            idleDetector.stopMonitoring()
        }
        updateComputedValues()
        logRevision += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    func updateNote(_ note: String) {
        guard let current = currentWorkday else { return }
        let updated = current.withNote(note)
        currentWorkday = updated
        store.save(updated.payload)
    }

    /// Apply only edited fields to the latest payload. The timer may have
    /// paused, ended, or recorded another idle decision while the editor was open.
    func saveEdits(_ edited: TimeEntry, original: TimeEntry) -> TimeEntry? {
        logMutationError = nil
        guard var latest = store.load(for: original.date), latest.id == original.id else {
            logger.error("Cannot edit a deleted or replaced workday: \(original.date)")
            logMutationError = .missingEntry
            return nil
        }
        if edited.startTime != original.startTime { latest.startTime = edited.startTime }
        if edited.endTime != original.endTime, latest.status == .ended {
            latest.endTime = edited.endTime
        }
        if edited.manualPauseSeconds != original.manualPauseSeconds {
            latest.manualPauseSeconds = edited.manualPauseSeconds
        }
        if edited.note != original.note { latest.note = edited.note }
        for decision in edited.idleDecisions {
            if let before = original.idleDecisions.first(where: { $0.id == decision.id }),
                before.decision != decision.decision,
                let index = latest.idleDecisions.firstIndex(where: { $0.id == decision.id }) {
                latest.idleDecisions[index].decision = decision.decision
            }
        }
        guard hasValidLogTimes(latest) else {
            logger.error("Cannot save invalid workday times: \(original.date)")
            logMutationError = .invalidTimes
            return nil
        }
        guard store.saveAndWait(latest) else {
            logger.error("Failed to commit edited Daily Log: \(original.date)")
            logMutationError = .saveFailed
            return nil
        }
        if latest.id == currentEntry?.id {
            activate(workday(for: latest))
        } else {
            logRevision += 1
        }
        return latest
    }

    func hasValidLogTimes(_ entry: TimeEntry) -> Bool {
        let end = entry.endTime ?? clock.now
        return entry.startTime.timeIntervalSince1970.isFinite
            && end.timeIntervalSince1970.isFinite
            && entry.startTime <= end
            && entry.manualPauseSeconds.isFinite && entry.manualPauseSeconds >= 0
            && (entry.status != .ended || entry.endTime != nil)
    }

    func loadDailyLogs() -> [TimeEntry] {
        store.loadAll()
    }

    @discardableResult
    func deleteLog(_ entry: TimeEntry) -> Bool {
        logMutationError = nil
        guard let latest = store.load(for: entry.date), latest.id == entry.id else {
            logger.error("Cannot delete a missing or replaced Daily Log: \(entry.date)")
            logMutationError = .missingEntry
            return false
        }
        guard store.delete(for: entry.date) else {
            logger.error("Failed to delete Daily Log: \(entry.date)")
            logMutationError = .deleteFailed
            return false
        }
        logRevision += 1
        if currentWorkday?.date == entry.date {
            dismissIdlePeriod()
            currentWorkday = nil
            state = .notStarted
            stopTimer()
            idleDetector.stopMonitoring()
            updateComputedValues()
            WidgetCenter.shared.reloadAllTimelines()
        }
        return true
    }

    func clearLogMutationError() {
        logMutationError = nil
    }

    func updateStartTime(_ newStart: Date) {
        guard let current = currentWorkday else { return }
        if let end = current.endTime {
            if newStart > end { return }
        } else if newStart > clock.now {
            // Running/paused day: the start must not be in the future
            return
        }
        let updated = current.withStartTime(newStart)
        currentWorkday = updated
        store.save(updated.payload)
        updateComputedValues()
        logRevision += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    func updateEndTime(_ newEnd: Date) {
        guard let current = currentWorkday, state == .ended else { return }
        if newEnd < current.startTime { return }
        let updated = current.withEndTime(newEnd)
        currentWorkday = updated
        store.save(updated.payload)
        updateComputedValues()
        logRevision += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Estimated end time to reach a target of net work hours.
    /// Accounts for auto-break that will be added at 6h/9h thresholds.
    var estimatedEndTime: Date? {
        guard let current = currentWorkday, state == .running || state == .paused else { return nil }
        let targetSeconds = notificationThresholds.normalHours * 3600

        // Calculate how much gross time is needed to reach targetSeconds net
        // Net = Gross - ManualPause - IdlePause - AutoBreak
        // AutoBreak depends on (Gross - ManualPause - IdlePause)
        let alreadyPaused = current.pause(endingAt: clock.now)

        // Estimate: target net + pauses already taken + auto-break for the total
        let estimatedWorkTime = targetSeconds
        let estimatedAutoBreak = current.autoBreakRules.autoBreak(
            forWorkTime: estimatedWorkTime,
            alreadyPaused: alreadyPaused
        )
        let neededGross = targetSeconds + alreadyPaused + estimatedAutoBreak
        let currentGross = current.grossTime(endingAt: clock.now)
        let remaining = neededGross - currentGross

        guard remaining > 0 else { return nil }
        return clock.now.addingTimeInterval(remaining)
    }

}

// MARK: - Timer

extension WorkdayManager {

    private func startTimer() {
        stopTimer()
        let newTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func tick() {
        checkDateChange()
        guard state == .running || state == .paused else { return }
        if let current = currentWorkday, state == .running {
            currentWorkday = current.recordingActivity(at: idleDetector.lastActivityTime)
        }
        updateComputedValues()
        checkThresholds()
        autoSave()
    }

    private func updateComputedValues() {
        let instant = currentWorkday?.endTime ?? clock.now
        if let current = currentWorkday {
            grossTime = current.grossTime(endingAt: instant)
            pauseTime = current.pause(endingAt: instant)
            autoBreak = current.autoBreak(endingAt: instant)
            netTime = current.netWorkTime(endingAt: instant)
            displayTime = netTime
        } else {
            grossTime = 0
            pauseTime = 0
            autoBreak = 0
            netTime = 0
            displayTime = 0
        }
        let thresholds = currentWorkday?.thresholds ?? .resolved(from: defaults)
        let snapshot = WidgetSnapshot(
            measuredAt: instant,
            state: state,
            netTime: netTime,
            grossTime: grossTime,
            startTime: currentWorkday?.startTime,
            workDate: currentWorkday?.date ?? "",
            targetHours: notificationThresholds.normalHours,
            thresholdLadder: thresholds
        )
        do {
            try widgetStore.publish(snapshot)
        } catch {
            logger.error("Failed to publish widget snapshot: \(error.localizedDescription)")
        }
    }

    // MARK: - Threshold Notifications

    private func checkThresholds() {
        guard let current = currentWorkday, state == .running,
            pendingIdlePeriod == nil, !idleDetector.isIdle, idleDetector.hasRecentActivity else { return }

        let hours = netTime.inHours
        let notified = current.payload.notifiedThresholds
        let thresholds = notificationThresholds

        // Only the highest crossed Threshold is reported. Lower ones crossed in
        // the same jump are recorded as notified so they never follow later.
        func markingCrossedBelow(_ workday: Workday, _ threshold: NotifiedThreshold) -> Workday {
            var marked = workday.markingNotified(threshold)
            if threshold == .milestone && hours >= thresholds.criticalHours {
                marked = marked.markingNotified(.critical)
            }
            if hours >= thresholds.normalHours {
                marked = marked.markingNotified(.normal)
            }
            return marked
        }

        // The 10h milestone popup is a legal safeguard (ArbZG) and must appear
        // regardless of whether notifications are enabled.
        if hours >= thresholds.milestoneHours && !notified.contains(.milestone) {
            let updated = markingCrossedBelow(current, .milestone)
            currentWorkday = updated
            store.save(updated.payload)
            if thresholds.enabled {
                notifications.sendThresholdNotification(.milestone, hours: hours)
            }
            // Show popup asking to end the day
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state == .running, self.pendingIdlePeriod == nil,
                    self.currentEntry?.id == current.id else { return }
                self.prompts.showMaxHoursPrompt(hours: hours, manager: self)
            }
            return
        }

        // Normal and critical notifications are only sent when enabled.
        guard thresholds.enabled else { return }

        if hours >= thresholds.criticalHours && !notified.contains(.critical) {
            notifications.sendThresholdNotification(.critical, hours: hours)
            let updated = markingCrossedBelow(current, .critical)
            currentWorkday = updated
            store.save(updated.payload)
        } else if hours >= thresholds.normalHours && !notified.contains(.normal) {
            notifications.sendThresholdNotification(.normal, hours: hours)
            let updated = current.markingNotified(.normal)
            currentWorkday = updated
            store.save(updated.payload)
        }
    }

    // MARK: - Date Change Detection

    private func checkDateChange() {
        guard let current = currentWorkday, pendingIdlePeriod == nil,
            !idleDetector.isIdle, idleDetector.hasRecentActivity else { return }
        let detector = WorkdayDetector(newDayStartHour: newDayStartHour)
        let effectiveDate = detector.effectiveDateString(for: clock.now)
        guard effectiveDate > current.date else { return }

        if state == .ended {
            evaluateWorkday()
            return
        }

        let wasPaused = (state == .paused)

        // Split active work at the configured boundary, not midnight.
        let boundary = detector.startOfEffectiveDay(for: clock.now)
        finish(at: boundary)

        if wasPaused {
            // The user was paused across midnight (not actively working) —
            // don't auto-start a running day, which would wrongly count the
            // night as work. Reset to a clean, idle slate instead.
            currentWorkday = nil
            state = .notStarted
            stopTimer()
            updateComputedValues()
        } else {
            if let existing = store.load(for: effectiveDate) {
                activate(workday(for: existing))
                return
            }
            let carriedDecisions = current.payload.idleDecisions.filter { $0.idleEnd > boundary }
            let started = workday(for: TimeEntry(
                date: effectiveDate, startTime: boundary, idleDecisions: carriedDecisions))
            store.save(started.payload)
            activate(started)
        }
    }

    // MARK: - Auto-Save

    private func autoSave() {
        guard state == .running || state == .paused else { return }
        let now = clock.now
        if let last = lastSaveTime, now.timeIntervalSince(last) < 30 { return }
        if let current = currentWorkday {
            store.save(current.payload)
            lastSaveTime = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Sleep/Wake

    private func registerForSleepWake() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.handleSleep()
            }
        )
        let wsnc = NSWorkspace.shared.notificationCenter
        observers.append(
            wsnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.handleActivityEvent(.sleep)
            }
        )
        observers.append(
            wsnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.handleActivityEvent(.wake)
            }
        )

        // Screen lock/unlock (covers lid close without sleep, fast user switching)
        let dnc = DistributedNotificationCenter.default()
        observers.append(
            dnc.addObserver(
                forName: NSNotification.Name("com.apple.screenIsLocked"),
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.handleActivityEvent(.lock)
            }
        )
        observers.append(
            dnc.addObserver(
                forName: NSNotification.Name("com.apple.screenIsUnlocked"),
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.handleActivityEvent(.unlock)
            }
        )
    }

    private func handleSleep() {
        // Save current state before sleep
        if let current = currentWorkday {
            let updated = current.recordingActivity(at: idleDetector.lastActivityTime)
            currentWorkday = updated
            store.save(updated.payload)
            store.flush()
        }
    }

    func handleActivityEvent(_ event: IdleDetector.ActivityEvent) {
        // Finish detection and publish any Idle Period before considering a new Workday.
        idleDetector.handle(event)
        switch event {
        case .sleep, .lock:
            handleSleep()
        case .wake, .unlock:
            guard !idleDetector.isSuspended else { return }
            evaluateWorkday()
        }
    }

    // MARK: - Menu Bar Display

    var menuBarTitle: String {
        switch state {
        case .notStarted:
            return "--:--"
        case .running:
            return displayTime.hoursMinutesFormatted
        case .paused:
            return "|| \(displayTime.hoursMinutesFormatted)"
        case .ended:
            return "\(displayTime.hoursMinutesFormatted)"
        }
    }

    var thresholdLevel: ThresholdLevel {
        (currentWorkday?.thresholds ?? .resolved()).level(for: netTime)
    }

    /// Exports every Daily Log, deriving Net Work Time with the configured rules.
    func exportCSV() -> URL? {
        store.exportCSV(workdayFor: workday(for:))
    }

    // MARK: - Ending a Workday

    /// Ends the held Workday at `instant` and runs every effect that requires:
    /// persisting, stopping Idle monitoring, dismissing any prompt, and
    /// publishing the final values. The timer stays alive to detect activity
    /// on the next effective day, without accumulating more work today.
    ///
    /// Unconditional — every caller gets the full effect list, even one that
    /// immediately starts a new Workday and redoes half of it. That's cheap;
    /// five near-identical, subtly-diverging copies of this list were not.
    private func finish(at instant: Date) {
        guard let current = currentWorkday else { return }
        let ended = current.ended(at: instant)
        store.save(ended.payload)
        dismissIdlePeriod()
        activate(ended)
    }

    /// Clears the pending Idle Period, tells the detector it's been resolved,
    /// and closes its presentation. The single call every dismissal path uses
    /// — no caller has to remember the pairing that used to be here.
    func dismissIdlePeriod() {
        pendingIdlePeriod = nil
        idleDetector.periodResolved()
        prompts.dismiss()
    }
}

// MARK: - Idle Handling

extension WorkdayManager {

    func handleIdleDecision(_ decision: IdleDecision.Decision) {
        guard let current = currentWorkday,
            let period = pendingIdlePeriod
        else { return }

        let updated = current.recording(
            IdleDecision(idleStart: period.idleStart, idleEnd: period.idleEnd, decision: decision)
        )
        currentWorkday = updated
        store.save(updated.payload)
        dismissIdlePeriod()
        updateComputedValues()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func handleIdleDecisionAndEndDay() {
        guard let current = currentWorkday,
            let period = pendingIdlePeriod
        else { return }

        // Record idle time as pause, then end the day at idle start.
        currentWorkday = current.recording(
            IdleDecision(idleStart: period.idleStart, idleEnd: period.idleEnd, decision: .pause)
        )
        finish(at: period.idleStart)
    }

    func handleIdleDecisionAndRestart() {
        guard let current = currentWorkday,
            let period = pendingIdlePeriod
        else { return }

        let detector = WorkdayDetector(newDayStartHour: newDayStartHour)
        if current.date == detector.effectiveDateString(for: clock.now) {
            handleIdleDecision(.pause)
        } else {
            handleNewDayFromIdle(endYesterdayAt: period.idleStart)
        }
    }

    func handleNewDayFromIdle(endYesterdayAt: Date) {
        guard let current = currentWorkday,
            let period = pendingIdlePeriod
        else { return }

        let detector = WorkdayDetector(newDayStartHour: newDayStartHour)
        if current.date == detector.effectiveDateString(for: clock.now) {
            handleIdleDecision(.pause)
            return
        }
        finish(at: endYesterdayAt)
        startDay(at: max(detector.startOfEffectiveDay(for: clock.now), period.idleEnd))
    }
}
