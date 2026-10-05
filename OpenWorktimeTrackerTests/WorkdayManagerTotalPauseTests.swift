import XCTest

@testable import OpenWorktimeTracker

/// Setting today's Pause total directly from the menu bar popover.
final class WorkdayManagerTotalPauseTests: XCTestCase {

    private var clock: ManualClock!
    private var store: InMemoryDailyLogStore!
    private var manager: WorkdayManager!

    override func setUp() {
        super.setUp()
        clock = ManualClock(now: Calendar.current.date(
            from: DateComponents(year: 2026, month: 9, day: 14, hour: 8))!)
        store = InMemoryDailyLogStore()
        let suiteName = "total-pause-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let widgetSuiteName = "total-pause-widget-\(UUID())"
        let widgetDefaults = UserDefaults(suiteName: widgetSuiteName)!
        addTeardownBlock { widgetDefaults.removePersistentDomain(forName: widgetSuiteName) }
        manager = WorkdayManager(
            defaults: defaults, clock: clock, store: store,
            idleDetector: IdleDetector(clock: clock, idleTime: { 0 }), prompts: RecordingWorkdayPrompts(),
            widgetStore: SharedDefaults(defaults: widgetDefaults))
        manager.startNewDay()
        clock.now = clock.now.addingTimeInterval(4 * 3600)  // 4h gross, below any Auto Break
    }

    override func tearDown() {
        manager = nil
        store = nil
        clock = nil
        super.tearDown()
    }

    func testSettingTheTotalChangesNetTimeAndIsSaved() throws {
        XCTAssertNil(manager.setTotalPause(45 * 60))

        XCTAssertEqual(manager.pauseTime, 45 * 60, accuracy: 0.5)
        XCTAssertEqual(manager.netTime, 4 * 3600 - 45 * 60, accuracy: 0.5)
        let saved = try XCTUnwrap(store.load(for: manager.currentEntry!.date))
        XCTAssertEqual(saved.manualPauseSeconds, 45 * 60)

        XCTAssertNil(manager.setTotalPause(10 * 60))
        XCTAssertEqual(manager.netTime, 4 * 3600 - 10 * 60, accuracy: 0.5)
    }

    func testATotalAboveGrossTimeIsRejectedAndNothingChanges() {
        manager.setTotalPause(20 * 60)

        XCTAssertEqual(manager.setTotalPause(4 * 3600 + 60), .exceedsGrossTime(4 * 3600))
        XCTAssertEqual(manager.currentEntry?.manualPauseSeconds, 20 * 60)
        XCTAssertEqual(manager.netTime, 4 * 3600 - 20 * 60, accuracy: 0.5)
        XCTAssertNil(manager.totalPauseError(for: 4 * 3600))
    }

    func testIdlePauseCountsTowardsTheTotalAndIsItsFloor() {
        let idleStart = clock.now.addingTimeInterval(-3600)
        manager.pendingIdlePeriod = IdlePeriod(
            idleStart: idleStart, idleEnd: idleStart.addingTimeInterval(30 * 60 + 30), spansMidnight: false)
        manager.handleIdleDecision(.pause)

        // 30:30 away shows as 00:30, so 00:30 is still accepted.
        XCTAssertNil(manager.totalPauseError(for: 30 * 60))
        XCTAssertEqual(manager.setTotalPause(29 * 60), .belowIdlePause(30 * 60 + 30))

        XCTAssertNil(manager.setTotalPause(50 * 60))
        XCTAssertEqual(manager.currentEntry?.manualPauseSeconds ?? -1, 19 * 60 + 30, accuracy: 0.5)
        XCTAssertEqual(manager.pauseTime, 50 * 60, accuracy: 0.5)
    }

    func testEditingIsBlockedWhilePaused() {
        manager.pause()

        XCTAssertEqual(manager.setTotalPause(10 * 60), .paused)
        XCTAssertEqual(manager.currentEntry?.manualPauseSeconds, 0)
    }

    func testAnEndedDayCanBeEdited() {
        manager.endDay()
        clock.now = clock.now.addingTimeInterval(3600)

        XCTAssertNil(manager.setTotalPause(60 * 60))
        XCTAssertEqual(manager.netTime, 3 * 3600, accuracy: 0.5)
        XCTAssertEqual(manager.setTotalPause(4 * 3600 + 60), .exceedsGrossTime(4 * 3600))
    }

    func testSaveFailureLeavesTheWorkdayUntouched() {
        store.saveSucceeds = false

        XCTAssertEqual(manager.setTotalPause(10 * 60), .saveFailed)
        XCTAssertEqual(manager.currentEntry?.manualPauseSeconds, 0)
    }
}
