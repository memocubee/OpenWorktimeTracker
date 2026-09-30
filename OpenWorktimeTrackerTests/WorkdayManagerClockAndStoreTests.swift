import AppKit
import XCTest

@testable import OpenWorktimeTracker

/// Tests that exercise WorkdayManager's Clock/DailyLogStore seams:
/// time-dependent behaviour asserted against an exact instant instead of a
/// tolerance, and no filesystem I/O for the Daily Log.
final class WorkdayManagerClockAndStoreTests: XCTestCase {

    private var clock: ManualClock!
    private var store: InMemoryDailyLogStore!
    private var manager: WorkdayManager!
    private var prompts: RecordingWorkdayPrompts!
    private var widgetStore: SharedDefaults!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        clock = ManualClock(now: date(day: 14, hour: 8))
        store = InMemoryDailyLogStore()
        prompts = RecordingWorkdayPrompts()
        let suiteName = "clock-store-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        self.defaults = defaults
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let widgetSuiteName = "widget-manager-tests-\(UUID())"
        let widgetDefaults = UserDefaults(suiteName: widgetSuiteName)!
        addTeardownBlock { widgetDefaults.removePersistentDomain(forName: widgetSuiteName) }
        widgetStore = SharedDefaults(defaults: widgetDefaults)
        manager = WorkdayManager(
            defaults: defaults, clock: clock, store: store,
            idleDetector: IdleDetector(clock: clock, idleTime: { 0 }), prompts: prompts,
            widgetStore: widgetStore)
    }

    override func tearDown() {
        manager = nil
        store = nil
        clock = nil
        prompts = nil
        widgetStore = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Exact timestamps

    func testWidgetPublicationTracksStartPauseResumeAndEndMeasurements() throws {
        manager.startNewDay()
        let start = clock.now
        var snapshot = try XCTUnwrap(widgetStore.readSnapshot())
        XCTAssertEqual(snapshot.state, .running)
        XCTAssertEqual(snapshot.measuredAt, start)
        XCTAssertEqual(snapshot.startTime, start)
        XCTAssertEqual(snapshot.workDate, manager.currentEntry?.date)
        XCTAssertEqual(snapshot.netTime, 0)

        clock.now = start.addingTimeInterval(3600)
        manager.pause()
        snapshot = try XCTUnwrap(widgetStore.readSnapshot())
        XCTAssertEqual(snapshot.state, .paused)
        XCTAssertEqual(snapshot.measuredAt, clock.now)
        XCTAssertEqual(snapshot.netTime, 3600)
        XCTAssertEqual(snapshot.netTime(at: clock.now.addingTimeInterval(600)), 3600)

        clock.now = clock.now.addingTimeInterval(600)
        manager.resume()
        snapshot = try XCTUnwrap(widgetStore.readSnapshot())
        XCTAssertEqual(snapshot.state, .running)
        XCTAssertEqual(snapshot.measuredAt, clock.now)
        XCTAssertEqual(snapshot.netTime, 3600)
        XCTAssertEqual(snapshot.grossTime, 4200)
        XCTAssertEqual(snapshot.netTime(at: clock.now.addingTimeInterval(300)), 3900)

        clock.now = clock.now.addingTimeInterval(300)
        manager.endDay()
        snapshot = try XCTUnwrap(widgetStore.readSnapshot())
        XCTAssertEqual(snapshot.state, .ended)
        XCTAssertEqual(snapshot.measuredAt, clock.now)
        XCTAssertEqual(snapshot.netTime, 3900)
        clock.now = clock.now.addingTimeInterval(900)
        manager.tick()
        XCTAssertEqual(try widgetStore.readSnapshot(), snapshot)
    }

    func testWidgetPublicationUsesResolvedSettingsFromManager() throws {
        defaults.set(7.0, forKey: AppSettingsKey.normalNotificationHours)
        defaults.set(7.5, forKey: AppSettingsKey.orangeThresholdHours)
        defaults.set(8.5, forKey: AppSettingsKey.redThresholdHours)
        manager.bootstrap()
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)

        let snapshot = try XCTUnwrap(widgetStore.readSnapshot())
        XCTAssertEqual(snapshot.targetHours, 7)
        XCTAssertEqual(snapshot.thresholdLadder, ThresholdLadder(elevatedHours: 7.5, criticalHours: 8.5))
    }

    func testDeletingCurrentLogPublishesEmptySnapshotWithoutStaleStartTime() throws {
        manager.startNewDay()
        XCTAssertTrue(manager.deleteLog(manager.currentEntry!))

        let snapshot = try XCTUnwrap(widgetStore.readSnapshot())
        XCTAssertEqual(snapshot.state, .notStarted)
        XCTAssertEqual(snapshot.measuredAt, clock.now)
        XCTAssertNil(snapshot.startTime)
        XCTAssertEqual(snapshot.workDate, "")
        XCTAssertEqual(snapshot.netTime, 0)
        XCTAssertEqual(snapshot.grossTime, 0)
    }

    func testEndingAtIdleStartPublishesMeasurementAtActualEnd() throws {
        manager.startNewDay()
        let end = clock.now.addingTimeInterval(3600)
        clock.now = end.addingTimeInterval(600)
        manager.pendingIdlePeriod = IdlePeriod(
            idleStart: end, idleEnd: clock.now, spansMidnight: false)
        manager.handleIdleDecisionAndEndDay()

        let snapshot = try XCTUnwrap(widgetStore.readSnapshot())
        XCTAssertEqual(snapshot.state, .ended)
        XCTAssertEqual(snapshot.measuredAt, end)
        XCTAssertEqual(snapshot.netTime, 3600)
        XCTAssertEqual(snapshot.netTime(at: clock.now), 3600)
    }

    private func date(day: Int, hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    func testRestartPreservesWorkAndCountsGapAsPause() {
        manager.startNewDay()
        manager.updateNote("Keep this note")
        let original = manager.currentEntry!
        clock.now = clock.now.addingTimeInterval(3600)
        manager.endDay()
        clock.now = clock.now.addingTimeInterval(1800)

        manager.restartDay()

        XCTAssertEqual(manager.currentEntry?.id, original.id)
        XCTAssertEqual(manager.currentEntry?.startTime, original.startTime)
        XCTAssertEqual(manager.currentEntry?.note, original.note)
        XCTAssertEqual(manager.pauseTime, 1800)
        XCTAssertNil(manager.currentEntry?.endTime)
        XCTAssertEqual(manager.netTime, 3600)
    }

    func testStartBeforeDayBoundaryUsesPreviousEffectiveDate() {
        clock.now = date(day: 15, hour: 2)
        manager.startNewDay()

        XCTAssertEqual(manager.currentEntry?.date, "2026-09-14")
        let id = manager.currentEntry?.id
        manager.tick()
        manager.tick()
        XCTAssertEqual(manager.currentEntry?.id, id)
        XCTAssertEqual(manager.currentEntry?.startTime, clock.now)
    }

    func testEvaluationBeforeBoundaryResumesPreviousCalendarDay() {
        clock.now = date(day: 14, hour: 22)
        manager.startNewDay()
        let original = manager.currentEntry!
        clock.now = date(day: 15, hour: 2)

        manager.evaluateWorkday()

        XCTAssertEqual(manager.currentEntry?.id, original.id)
        XCTAssertEqual(manager.currentEntry?.startTime, original.startTime)
        XCTAssertEqual(store.load(for: original.date)?.status, .running)
    }

    func testEvaluationKeepsEndedEffectiveDayEnded() {
        manager.startNewDay()
        clock.now = date(day: 14, hour: 17)
        manager.endDay()
        let id = manager.currentEntry?.id
        clock.now = date(day: 15, hour: 2)

        manager.evaluateWorkday()

        XCTAssertEqual(manager.state, .ended)
        XCTAssertEqual(manager.currentEntry?.id, id)
    }

    func testRolloverPreservesWorkBetweenMidnightAndBoundary() {
        clock.now = date(day: 15, hour: 2)
        store.save(TimeEntry(date: "2026-09-14", startTime: clock.now))
        manager.evaluateWorkday()
        clock.now = date(day: 15, hour: 4)

        manager.tick()

        let previous = store.load(for: "2026-09-14")!
        XCTAssertEqual(previous.endTime, clock.now)
        XCTAssertEqual(manager.workday(for: previous).netWorkTime, 7200)
        XCTAssertEqual(manager.currentEntry?.date, "2026-09-15")
    }

    func testPendingOvernightIdleIsNotDiscardedByTick() {
        manager.startNewDay()
        let original = manager.currentEntry!
        let idleStart = date(day: 14, hour: 17)
        clock.now = date(day: 15, hour: 8)
        manager.pendingIdlePeriod = IdlePeriod(
            idleStart: idleStart, idleEnd: clock.now, spansMidnight: true)

        manager.tick()

        XCTAssertEqual(manager.currentEntry?.id, original.id)
        XCTAssertNotNil(manager.pendingIdlePeriod)
        XCTAssertEqual(store.load(for: original.date)?.status, .running)
    }

    func testEndingAtIdleStartDoesNotDeductIdleAfterEnd() {
        manager.startNewDay()
        let idleStart = clock.now.addingTimeInterval(3600)
        clock.now = clock.now.addingTimeInterval(7200)
        manager.pendingIdlePeriod = IdlePeriod(
            idleStart: idleStart, idleEnd: clock.now, spansMidnight: false)

        manager.handleIdleDecisionAndEndDay()

        XCTAssertEqual(manager.currentEntry?.endTime, idleStart)
        XCTAssertEqual(manager.currentWorkday?.netWorkTime, 3600)
        XCTAssertEqual(manager.netTime, 3600)
    }

    func testIdleRestartPreservesWorkWithoutDeductingGapTwice() {
        manager.startNewDay()
        let original = manager.currentEntry!
        let idleStart = clock.now.addingTimeInterval(3600)
        clock.now = clock.now.addingTimeInterval(7200)
        manager.pendingIdlePeriod = IdlePeriod(
            idleStart: idleStart, idleEnd: clock.now, spansMidnight: false)

        manager.handleIdleDecisionAndRestart()

        XCTAssertEqual(manager.currentEntry?.id, original.id)
        XCTAssertEqual(manager.netTime, 3600)
        XCTAssertEqual(manager.pauseTime, 3600)
    }

    func testDeletingCurrentEntryStopsTrackingAndDoesNotRecreateIt() {
        manager.startNewDay()
        let date = manager.currentEntry!.date
        XCTAssertTrue(manager.deleteLog(manager.currentEntry!))
        manager.tick()

        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertNil(manager.currentEntry)
        XCTAssertNil(store.load(for: date))
        XCTAssertEqual(manager.netTime, 0)
    }

    func testSavingEditsUsesHeldWorkdayDateBeforeBoundary() {
        manager.startNewDay()
        let original = manager.currentEntry!
        var edited = original
        edited.note = "Edited overnight"
        clock.now = date(day: 15, hour: 2)

        XCTAssertNotNil(manager.saveEdits(edited, original: original))

        XCTAssertEqual(manager.currentEntry?.note, edited.note)
    }

    func testEndedDayStartsNextDayOnActivityWithoutWakeNotification() {
        manager.startNewDay()
        manager.endDay()
        let previous = manager.currentEntry!
        clock.now = date(day: 15, hour: 8)

        manager.tick()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(manager.currentEntry?.date, "2026-09-15")
        XCTAssertEqual(manager.currentEntry?.startTime, clock.now)
        XCTAssertEqual(store.load(for: previous.date)?.endTime, previous.endTime)
    }

    func testManualPauseDoesNotAlsoGenerateAnIdlePause() {
        manager.bootstrap()
        clock.now = clock.now.addingTimeInterval(3600)
        manager.pause()
        let pauseStart = clock.now
        clock.now = clock.now.addingTimeInterval(1800)
        manager.idleDetector.onPeriodEnded?(
            IdlePeriod(idleStart: pauseStart, idleEnd: clock.now, spansMidnight: false))

        XCTAssertNil(manager.pendingIdlePeriod)
        manager.resume()
        XCTAssertEqual(manager.pauseTime, 1800)
        XCTAssertEqual(manager.netTime, 3600)
    }

    func testSavingStaleEditorDoesNotReopenEndedDayOrLosePauses() {
        manager.startNewDay()
        let original = manager.currentEntry!
        clock.now = clock.now.addingTimeInterval(3600)
        manager.pause()
        clock.now = clock.now.addingTimeInterval(900)
        manager.endDay()
        let end = manager.currentEntry?.endTime
        var edited = original
        edited.note = "Edited while timer changed"

        let saved = manager.saveEdits(edited, original: original)

        XCTAssertEqual(saved?.note, edited.note)
        XCTAssertEqual(saved?.status, .ended)
        XCTAssertEqual(saved?.endTime, end)
        XCTAssertEqual(saved?.manualPauseSeconds, 900)
        XCTAssertEqual(manager.state, .ended)
        XCTAssertEqual(manager.netTime, 3600)
    }

    func testSavingStaleEditorDoesNotRecreateDeletedDay() {
        manager.startNewDay()
        let original = manager.currentEntry!
        store.delete(for: original.date)

        XCTAssertNil(manager.saveEdits(original, original: original))
        XCTAssertNil(store.load(for: original.date))
    }

    func testOvernightPauseDecisionCarriesPauseIntoNewDay() {
        manager.startNewDay()
        clock.now = date(day: 15, hour: 8)
        manager.pendingIdlePeriod = IdlePeriod(
            idleStart: date(day: 14, hour: 17), idleEnd: clock.now, spansMidnight: true)

        manager.handleIdleDecision(.pause)
        manager.tick()

        XCTAssertEqual(manager.currentEntry?.date, "2026-09-15")
        XCTAssertEqual(manager.netTime, 0)
        XCTAssertEqual(manager.pauseTime, 4 * 3600)
    }

    func testResumeAfterOvernightPauseStartsAtResumeNotBoundary() {
        manager.startNewDay()
        clock.now = date(day: 14, hour: 17)
        manager.pause()
        clock.now = date(day: 15, hour: 8)

        manager.resume()
        manager.tick()

        XCTAssertEqual(manager.currentEntry?.date, "2026-09-15")
        XCTAssertEqual(manager.currentEntry?.startTime, clock.now)
        XCTAssertEqual(manager.netTime, 0)
    }

    func testIdleRestartDoesNotSubtractTimeSpentAnsweringPrompt() {
        manager.startNewDay()
        let idleStart = clock.now.addingTimeInterval(3600)
        let idleEnd = idleStart.addingTimeInterval(1800)
        clock.now = idleEnd.addingTimeInterval(600)
        manager.pendingIdlePeriod = IdlePeriod(
            idleStart: idleStart, idleEnd: idleEnd, spansMidnight: false)

        manager.handleIdleDecisionAndRestart()

        XCTAssertEqual(manager.netTime, 4200)
        XCTAssertEqual(manager.pauseTime, 1800)
    }

    func testNewDayFromIdleStartsAtReturnEvenWhenDecisionIsDelayed() {
        manager.startNewDay()
        let idleStart = date(day: 14, hour: 17)
        let idleEnd = date(day: 15, hour: 8)
        clock.now = idleEnd.addingTimeInterval(600)
        manager.pendingIdlePeriod = IdlePeriod(
            idleStart: idleStart, idleEnd: idleEnd, spansMidnight: true)

        manager.handleNewDayFromIdle(endYesterdayAt: idleStart)

        XCTAssertEqual(manager.currentEntry?.startTime, idleEnd)
        XCTAssertEqual(manager.netTime, 600)
    }

    func testRestartNextMorningEndsPreviousDayAtLastRecordedActivity() {
        manager.startNewDay()
        clock.now = date(day: 14, hour: 16)
        manager.tick()
        let previousDate = manager.currentEntry!.date
        clock.now = date(day: 15, hour: 8)

        manager.evaluateWorkday()

        XCTAssertEqual(store.load(for: previousDate)?.endTime, date(day: 14, hour: 16))
        XCTAssertEqual(manager.currentEntry?.date, "2026-09-15")
    }

    func testEndedDayDoesNotStartNewDayUntilActivityReturns() {
        var idleSeconds: TimeInterval = 3600
        manager = WorkdayManager(
            clock: clock, store: store,
            idleDetector: IdleDetector(clock: clock, idleTime: { idleSeconds }))
        manager.startNewDay()
        manager.endDay()
        clock.now = date(day: 15, hour: 8)
        manager.tick()
        XCTAssertEqual(manager.state, .ended)

        idleSeconds = 0
        manager.tick()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(manager.currentEntry?.date, "2026-09-15")
        XCTAssertEqual(manager.currentEntry?.startTime, clock.now)
    }

    func testHistoricalLogDeletionDoesNotDismissCurrentIdleDecision() {
        manager.startNewDay()
        manager.pendingIdlePeriod = IdlePeriod(
            idleStart: clock.now, idleEnd: clock.now.addingTimeInterval(600), spansMidnight: false)
        let periodID = manager.pendingIdlePeriod?.id
        let historical = TimeEntry(date: "2026-09-13", startTime: date(day: 13, hour: 8))
        store.save(historical)
        let revision = manager.logRevision
        let dismissCount = prompts.dismissCount

        XCTAssertTrue(manager.deleteLog(historical))

        XCTAssertEqual(manager.pendingIdlePeriod?.id, periodID)
        XCTAssertNil(store.load(for: historical.date))
        XCTAssertEqual(manager.logRevision, revision + 1)
        XCTAssertEqual(prompts.dismissCount, dismissCount)
    }

    func testStartNewDayUsesTheInjectedClockExactly() {
        manager.startNewDay()
        XCTAssertEqual(manager.currentEntry?.startTime, clock.now)
    }

    func testPauseUsesTheInjectedClockExactly() {
        manager.startNewDay()
        clock.now = clock.now.addingTimeInterval(3600)

        manager.pause()

        XCTAssertEqual(manager.currentEntry?.pauseStartedAt, clock.now)
    }

    func testResumeAccumulatesExactlyTheInjectedClockDelta() {
        manager.startNewDay()
        manager.pause()
        clock.now = clock.now.addingTimeInterval(900)

        manager.resume()

        XCTAssertEqual(manager.currentEntry?.manualPauseSeconds ?? 0, 900)
    }

    func testEndDayUsesTheInjectedClockExactly() {
        manager.startNewDay()
        clock.now = clock.now.addingTimeInterval(7200)

        manager.endDay()

        XCTAssertEqual(manager.currentEntry?.endTime, clock.now)
    }

    func testEndDayImmediatelyPublishesFinalTime() {
        manager.startNewDay()
        clock.now = clock.now.addingTimeInterval(3600)

        manager.endDay()

        XCTAssertEqual(manager.grossTime, 3600)
        XCTAssertEqual(manager.netTime, 3600)
        XCTAssertEqual(manager.displayTime, 3600)
    }

    func testEndedDayDoesNotAccumulateTimeWhenRecomputed() {
        manager.startNewDay()
        clock.now = clock.now.addingTimeInterval(3600)
        manager.endDay()
        clock.now = clock.now.addingTimeInterval(7200)

        manager.updateStartTime(manager.currentEntry!.startTime)

        XCTAssertEqual(manager.grossTime, 3600)
        XCTAssertEqual(manager.netTime, 3600)
    }

    func testRepeatedStartPreservesTrackedWork() {
        manager.startNewDay()
        let original = manager.currentEntry!
        clock.now = clock.now.addingTimeInterval(3600)

        manager.startNewDay()

        XCTAssertEqual(manager.currentEntry?.id, original.id)
        XCTAssertEqual(manager.currentEntry?.startTime, original.startTime)
        XCTAssertEqual(store.load(for: original.date)?.id, original.id)
    }

    func testUpdateStartTimeRejectsAnInstantAfterTheInjectedNow() {
        manager.startNewDay()
        let future = clock.now.addingTimeInterval(60)

        manager.updateStartTime(future)

        XCTAssertNotEqual(manager.currentEntry?.startTime, future)
    }

    // MARK: - Deterministic published values

    func testNetTimeIsComputedAgainstTheInjectedClock() {
        manager.startNewDay()
        // 7h elapsed, past the 6h Auto Break threshold with default rules
        // (30min owed): 6h30m net.
        clock.now = clock.now.addingTimeInterval(7 * 3600)
        manager.updateStartTime(manager.currentEntry!.startTime)  // triggers a recompute

        XCTAssertEqual(manager.netTime, 6 * 3600 + 30 * 60, accuracy: 0.5)
        XCTAssertEqual(manager.grossTime, 7 * 3600, accuracy: 0.5)
    }

    // MARK: - No filesystem I/O

    func testStartNewDaySavesToTheInjectedStoreNotRealDisk() {
        manager.startNewDay()

        XCTAssertNotNil(store.load(for: manager.currentEntry!.date))
    }

    func testBootstrapSyncsThroughTheInjectedStore() {
        manager.bootstrap()

        XCTAssertEqual(store.syncWithCloudCallCount, 1)
    }

}
