import XCTest

@testable import OpenWorktimeTracker

/// Pause Intervals: every break is kept with its own start and end, so one
/// the user forgot to close can be fixed afterwards. Daily Logs from before
/// intervals existed keep their aggregate `manualPauseSeconds`, which still counts.
final class PauseIntervalTests: XCTestCase {

    private var clock: ManualClock!
    private var store: InMemoryDailyLogStore!
    private var manager: WorkdayManager!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        clock = ManualClock(now: date(hour: 8))
        store = InMemoryDailyLogStore()
        let suiteName = "pause-interval-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(0, forKey: AppSettingsKey.breakAfter6hMinutes)
        defaults.set(0, forKey: AppSettingsKey.breakAfter9hMinutes)
        self.defaults = defaults
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let widgetSuiteName = "pause-interval-widget-\(UUID())"
        let widgetDefaults = UserDefaults(suiteName: widgetSuiteName)!
        addTeardownBlock { widgetDefaults.removePersistentDomain(forName: widgetSuiteName) }
        manager = WorkdayManager(
            defaults: defaults, clock: clock, store: store,
            idleDetector: IdleDetector(clock: clock, idleTime: { 0 }),
            prompts: RecordingWorkdayPrompts(),
            notifications: RecordingWorkdayNotifications(),
            widgetStore: SharedDefaults(defaults: widgetDefaults))
    }

    override func tearDown() {
        manager = nil
        store = nil
        clock = nil
        defaults = nil
        super.tearDown()
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 9, day: 14, hour: hour, minute: minute))!
    }

    private let noAutoBreak = AutoBreakRules(after6hMinutes: 0, after9hMinutes: 0)
    private let ladder = ThresholdLadder(elevatedHours: 8.0, criticalHours: 9.5)

    /// Starts at 08:00, pauses at 12:00 and leaves the clock at `returnHour`.
    private func startAndPauseAtNoon(clockAt returnHour: Int, minute: Int = 0) {
        manager.startNewDay()
        clock.now = date(hour: 12)
        manager.pause()
        clock.now = date(hour: returnHour, minute: minute)
    }

    // MARK: - Compatibility

    func testAnOldDailyLogWithoutPausesDecodesAndStillCountsItsAggregatePause() throws {
        let json = """
            {
              "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
              "date": "2026-03-17",
              "startTime": "2026-03-17T08:00:00Z",
              "endTime": "2026-03-17T13:00:00Z",
              "status": "ended",
              "manualPauseSeconds": 1800,
              "idleDecisions": [],
              "notifiedThresholds": [],
              "note": ""
            }
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let entry = try decoder.decode(TimeEntry.self, from: Data(json.utf8))
        let workday = Workday(payload: entry, autoBreakRules: noAutoBreak, thresholds: ladder)

        XCTAssertTrue(entry.pauses.isEmpty)
        XCTAssertEqual(workday.manualPause, 1800, accuracy: 0.5)
        XCTAssertEqual(workday.netWorkTime, 4.5 * 3600, accuracy: 0.5)
    }

    func testPauseIntervalsRoundTripThroughTheDailyLog() throws {
        var entry = TimeEntry(startTime: date(hour: 8), endTime: date(hour: 17), status: .ended)
        entry.pauses = [PauseInterval(start: date(hour: 12), end: date(hour: 13))]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(TimeEntry.self, from: encoder.encode(entry))

        XCTAssertEqual(decoded.pauses, entry.pauses)
        XCTAssertEqual(decoded.manualPauseSeconds, 0)
    }

    func testLegacyAggregateAndIntervalsAreCountedTogether() {
        var entry = TimeEntry(
            startTime: date(hour: 8), endTime: date(hour: 13), status: .ended, manualPauseSeconds: 600)
        entry.pauses = [PauseInterval(start: date(hour: 10), end: date(hour: 10, minute: 30))]

        let workday = Workday(payload: entry, autoBreakRules: noAutoBreak, thresholds: ladder)

        XCTAssertEqual(workday.manualPause, 600 + 1800, accuracy: 0.5)
        XCTAssertEqual(workday.netWorkTime, 5 * 3600 - 2400, accuracy: 0.5)
    }

    func testResumingAPauseOpenedByAnOlderVersionRecordsItAsAnInterval() {
        let legacy = TimeEntry(
            startTime: date(hour: 8), status: .paused, pauseStartedAt: date(hour: 12))
        let workday = Workday(payload: legacy, autoBreakRules: noAutoBreak, thresholds: ladder)

        let resumed = workday.resumed(at: date(hour: 13))

        XCTAssertEqual(resumed.payload.pauses, [
            PauseInterval(id: resumed.payload.pauses[0].id, start: date(hour: 12), end: date(hour: 13))
        ])
        XCTAssertEqual(resumed.manualPause(endingAt: date(hour: 14)), 3600, accuracy: 0.5)
    }

    func testAPauseIntervalOverlappingAnIdlePauseIsOnlyDeductedOnce() {
        var entry = TimeEntry(startTime: date(hour: 8), endTime: date(hour: 14), status: .ended)
        entry.pauses = [PauseInterval(start: date(hour: 12), end: date(hour: 13))]
        entry.idleDecisions = [
            IdleDecision(idleStart: date(hour: 12, minute: 30), idleEnd: date(hour: 13, minute: 30), decision: .pause)
        ]

        let workday = Workday(payload: entry, autoBreakRules: noAutoBreak, thresholds: ladder)

        XCTAssertEqual(workday.pause, 90 * 60, accuracy: 0.5)
    }

    // MARK: - Recording

    func testPauseThenResumeRecordsOneInterval() throws {
        startAndPauseAtNoon(clockAt: 13)
        XCTAssertEqual(manager.currentEntry?.openPause?.start, date(hour: 12))
        XCTAssertEqual(manager.currentEntry?.pauseStartedAt, date(hour: 12))

        manager.resume()

        let pause = try XCTUnwrap(manager.currentEntry?.pauses.first)
        XCTAssertEqual(manager.currentEntry?.pauses.count, 1)
        XCTAssertEqual(pause.start, date(hour: 12))
        XCTAssertEqual(pause.end, date(hour: 13))
        XCTAssertNil(manager.currentEntry?.pauseStartedAt)
        XCTAssertEqual(store.load(for: manager.currentEntry!.date)?.pauses.first?.end, date(hour: 13))
        XCTAssertEqual(manager.netTime, 4 * 3600, accuracy: 0.5)
    }

    func testEndingTheDayWhilePausedClosesTheInterval() {
        startAndPauseAtNoon(clockAt: 13)

        manager.endDay()

        XCTAssertEqual(manager.currentEntry?.pauses.first?.end, date(hour: 13))
        XCTAssertEqual(manager.pauseTime, 3600, accuracy: 0.5)
    }

    // MARK: - Resume at a past time

    func testResumeAtAPastTimeCountsTheTimeSinceAsWork() {
        // Came back at 12:45 but only pressed Resume at 15:00.
        startAndPauseAtNoon(clockAt: 15)

        manager.resume(at: date(hour: 12, minute: 45))

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(manager.currentEntry?.pauses.first?.end, date(hour: 12, minute: 45))
        XCTAssertEqual(manager.pauseTime, 45 * 60, accuracy: 0.5)
        XCTAssertEqual(manager.netTime, 7 * 3600 - 45 * 60, accuracy: 0.5)
    }

    func testResumeAtIsClampedBetweenThePauseStartAndNow() {
        startAndPauseAtNoon(clockAt: 13)
        manager.resume(at: date(hour: 18))
        XCTAssertEqual(manager.currentEntry?.pauses.first?.end, date(hour: 13))

        manager.pause()
        clock.now = date(hour: 14)
        manager.resume(at: date(hour: 9))

        // Returning before the break began means it never happened.
        XCTAssertEqual(manager.currentEntry?.pauses.count, 1)
        XCTAssertEqual(manager.state, .running)
    }

    func testMovingTheStartOfTheOpenPauseKeepsPauseStartedAtInStep() throws {
        startAndPauseAtNoon(clockAt: 13)
        var open = try XCTUnwrap(manager.currentEntry?.openPause)
        open.start = date(hour: 11, minute: 30)

        XCTAssertNil(manager.updatePause(open))

        XCTAssertEqual(manager.currentEntry?.pauseStartedAt, date(hour: 11, minute: 30))
        XCTAssertEqual(manager.state, .paused)
        XCTAssertEqual(manager.pauseTime, 90 * 60, accuracy: 0.5)
    }

    // MARK: - Editing after the fact

    func testEditingAnIntervalChangesNetWorkTime() throws {
        startAndPauseAtNoon(clockAt: 14)
        manager.resume()
        clock.now = date(hour: 16)
        XCTAssertEqual(manager.currentWorkday?.netWorkTime(endingAt: clock.now) ?? 0, 6 * 3600, accuracy: 0.5)

        var pause = try XCTUnwrap(manager.currentEntry?.pauses.first)
        pause.end = date(hour: 12, minute: 30)
        XCTAssertNil(manager.updatePause(pause))

        XCTAssertEqual(manager.netTime, 7.5 * 3600, accuracy: 0.5)
        XCTAssertEqual(store.load(for: manager.currentEntry!.date)?.pauses.first?.end, date(hour: 12, minute: 30))
    }

    func testDeletingAClosedIntervalGivesTheTimeBack() throws {
        startAndPauseAtNoon(clockAt: 13)
        manager.resume()
        let id = try XCTUnwrap(manager.currentEntry?.pauses.first?.id)

        XCTAssertNil(manager.deletePause(id: id))

        XCTAssertTrue(manager.currentEntry?.pauses.isEmpty ?? false)
        XCTAssertEqual(manager.pauseTime, 0)
    }

    func testDeletingTheOpenIntervalPutsTheDayBackToRunning() throws {
        startAndPauseAtNoon(clockAt: 13)
        let id = try XCTUnwrap(manager.currentEntry?.openPause?.id)

        XCTAssertNil(manager.deletePause(id: id))

        XCTAssertEqual(manager.state, .running)
        XCTAssertNil(manager.currentEntry?.pauseStartedAt)
        XCTAssertEqual(manager.netTime, 5 * 3600, accuracy: 0.5)
    }

    func testEditingTheLegacyAggregate() {
        manager.startNewDay()
        clock.now = date(hour: 10)

        XCTAssertNil(manager.updateLegacyPauseSeconds(900))
        XCTAssertEqual(manager.pauseTime, 900, accuracy: 0.5)
        XCTAssertEqual(manager.updateLegacyPauseSeconds(-1), .endNotAfterStart)
        XCTAssertEqual(manager.currentEntry?.manualPauseSeconds, 900)
    }

    // MARK: - Validation

    private func dayWithTwoBreaks() throws -> (first: PauseInterval, second: PauseInterval) {
        startAndPauseAtNoon(clockAt: 13)
        manager.resume()
        clock.now = date(hour: 15)
        manager.pause()
        clock.now = date(hour: 15, minute: 30)
        manager.resume()
        clock.now = date(hour: 17)
        let pauses = try XCTUnwrap(manager.currentEntry?.pauses)
        XCTAssertEqual(pauses.count, 2)
        return (pauses[0], pauses[1])
    }

    func testOverlappingIntervalsAreRejected() throws {
        let (first, second) = try dayWithTwoBreaks()
        var moved = first
        moved.end = date(hour: 15, minute: 10)

        XCTAssertEqual(manager.updatePause(moved), .overlapping)

        let saved = store.load(for: manager.currentEntry!.date)
        XCTAssertEqual(saved?.pauses.first?.end, date(hour: 13))
        XCTAssertEqual(saved?.pauses.last, second)
    }

    func testAnIntervalMustEndAfterItStartsAndStayInsideTheWorkday() throws {
        let (first, _) = try dayWithTwoBreaks()

        var backwards = first
        backwards.end = date(hour: 11)
        XCTAssertEqual(manager.updatePause(backwards), .endNotAfterStart)

        var early = first
        early.start = date(hour: 7)
        XCTAssertEqual(manager.updatePause(early), .outsideWorkday)

        var future = first
        future.start = date(hour: 17, minute: 30)
        future.end = date(hour: 18)
        XCTAssertEqual(manager.updatePause(future), .inFuture)

        XCTAssertEqual(manager.currentEntry?.pauses.first, first)
    }

    func testAnIntervalPickedAFewSecondsBeforeTheDayStartedIsSnappedInside() throws {
        // The DatePicker keeps the seconds the value started with.
        clock.now = date(hour: 8).addingTimeInterval(37)
        manager.startNewDay()
        clock.now = date(hour: 12)
        manager.pause()
        clock.now = date(hour: 13)
        manager.resume()
        var pause = try XCTUnwrap(manager.currentEntry?.pauses.first)
        pause.start = date(hour: 8)

        XCTAssertNil(manager.updatePause(pause))

        XCTAssertEqual(manager.currentEntry?.pauses.first?.start, manager.currentEntry?.startTime)
    }

    // MARK: - Log Editor

    func testLogEditorAddsEditsAndDeletesIntervals() throws {
        let (first, second) = try dayWithTwoBreaks()
        let original = try XCTUnwrap(manager.currentEntry)
        var edited = original
        var shortened = first
        shortened.end = date(hour: 12, minute: 30)
        let added = PauseInterval(start: date(hour: 16), end: date(hour: 16, minute: 15))
        edited.pauses = [shortened, added]

        let saved = try XCTUnwrap(manager.saveEdits(edited, original: original))

        XCTAssertEqual(saved.pauses.map(\.id), [first.id, added.id])
        XCTAssertFalse(saved.pauses.contains { $0.id == second.id })
        XCTAssertEqual(manager.pauseTime, 45 * 60, accuracy: 0.5)
    }

    func testLogEditorRejectsOverlappingIntervals() throws {
        let (first, second) = try dayWithTwoBreaks()
        let original = try XCTUnwrap(manager.currentEntry)
        var edited = original
        var overlapping = second
        overlapping.start = date(hour: 12, minute: 30)
        edited.pauses = [first, overlapping]

        XCTAssertFalse(manager.hasValidLogTimes(edited))
        XCTAssertNil(manager.saveEdits(edited, original: original))
        XCTAssertEqual(manager.logMutationError, .invalidTimes)
        XCTAssertEqual(store.load(for: original.date)?.pauses, original.pauses)
    }

    func testLogEditorDoesNotReopenABreakTheTimerClosedMeanwhile() throws {
        startAndPauseAtNoon(clockAt: 12, minute: 30)
        let original = try XCTUnwrap(manager.currentEntry)
        var edited = original
        edited.pauses[0].start = date(hour: 11, minute: 45)
        clock.now = date(hour: 13)
        manager.resume()

        let saved = try XCTUnwrap(manager.saveEdits(edited, original: original))

        XCTAssertEqual(saved.pauses.first?.start, date(hour: 11, minute: 45))
        XCTAssertEqual(saved.pauses.first?.end, date(hour: 13))
        XCTAssertEqual(saved.status, .running)
    }
}
