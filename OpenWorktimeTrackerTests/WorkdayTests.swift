import XCTest

@testable import OpenWorktimeTracker

/// Tests the Workday interface: deriving Net Work Time, Auto Break and the
/// Threshold Level from a Daily Log payload plus resolved configuration.
///
/// The ArbZG ladder itself is tested in BreakCalculatorTests. What is tested
/// here is *assembly* — that the configured Auto Break Rules and every Pause
/// term actually reach the rule.
final class WorkdayTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 0)

    private func payload(
        hoursWorked: Double,
        manualPauseSeconds: TimeInterval = 0,
        status: TimeEntry.Status = .ended
    ) -> TimeEntry {
        TimeEntry(
            startTime: epoch,
            endTime: status == .ended ? epoch.addingTimeInterval(hoursWorked * 3600) : nil,
            status: status,
            manualPauseSeconds: manualPauseSeconds
        )
    }

    private let standardLadder = ThresholdLadder(elevatedHours: 8.0, criticalHours: 9.5)

    // MARK: - Configured Auto Break Rules reach the rule

    func testNetWorkTimeUsesConfiguredAutoBreakMinutes() {
        let workday = Workday(
            payload: payload(hoursWorked: 7),
            autoBreakRules: AutoBreakRules(after6hMinutes: 20, after9hMinutes: 40),
            thresholds: standardLadder
        )

        // 7h worked, past the 6h threshold, 20 configured minutes owed.
        XCTAssertEqual(workday.netWorkTime, 6 * 3600 + 40 * 60, accuracy: 0.5)
    }

    func testNetWorkTimeWithDefaultRulesDeductsThirtyMinutesPastSixHours() {
        let workday = Workday(
            payload: payload(hoursWorked: 7),
            autoBreakRules: AutoBreakRules(after6hMinutes: 30, after9hMinutes: 45),
            thresholds: standardLadder
        )

        XCTAssertEqual(workday.netWorkTime, 6 * 3600 + 30 * 60, accuracy: 0.5)
    }

    func testAutoBreakIsReducedByPauseAlreadyTaken() {
        let workday = Workday(
            payload: payload(hoursWorked: 7, manualPauseSeconds: 10 * 60),
            autoBreakRules: AutoBreakRules(after6hMinutes: 30, after9hMinutes: 45),
            thresholds: standardLadder
        )

        // 30min owed, 10min already taken as a Pause, so 20min is added.
        XCTAssertEqual(workday.autoBreak, 20 * 60, accuracy: 0.5)
        // 7h gross - 10min Pause - 20min Auto Break
        XCTAssertEqual(workday.netWorkTime, 6 * 3600 + 30 * 60, accuracy: 0.5)
    }

    // MARK: - Net Work Time at a hypothetical end

    func testNetWorkTimeEndingAtEarlierInstant() {
        let workday = Workday(
            payload: payload(hoursWorked: 9, status: .running),
            autoBreakRules: AutoBreakRules(after6hMinutes: 30, after9hMinutes: 45),
            thresholds: standardLadder
        )

        // As if the Workday had ended 4h in: below the 6h threshold, nothing owed.
        XCTAssertEqual(
            workday.netWorkTime(endingAt: epoch.addingTimeInterval(4 * 3600)),
            4 * 3600,
            accuracy: 0.5
        )
    }

    func testNetWorkTimeEndingAtIncludesAnOpenPause() {
        var open = payload(hoursWorked: 7, status: .paused)
        // Pause opened 5h in and never closed.
        open.pauseStartedAt = epoch.addingTimeInterval(5 * 3600)

        let workday = Workday(
            payload: open,
            autoBreakRules: AutoBreakRules(after6hMinutes: 30, after9hMinutes: 45),
            thresholds: standardLadder
        )

        // Ending at 6h: 1h of that was an open Pause, so 5h worked, nothing owed.
        XCTAssertEqual(
            workday.netWorkTime(endingAt: epoch.addingTimeInterval(6 * 3600)),
            5 * 3600,
            accuracy: 0.5
        )
    }

    func testNetWorkTimeEndingBeforeAnOpenPauseStartedIsNotNegative() {
        var open = payload(hoursWorked: 7, status: .paused)
        open.pauseStartedAt = epoch.addingTimeInterval(5 * 3600)

        let workday = Workday(
            payload: open,
            autoBreakRules: AutoBreakRules(after6hMinutes: 30, after9hMinutes: 45),
            thresholds: standardLadder
        )

        // Ending at 3h, before the Pause opened: the Pause must not count backwards.
        XCTAssertEqual(
            workday.netWorkTime(endingAt: epoch.addingTimeInterval(3 * 3600)),
            3 * 3600,
            accuracy: 0.5
        )
    }

    // MARK: - Idle Decisions

    func testIdlePeriodDecidedAsPauseIsDeducted() {
        var withIdle = payload(hoursWorked: 5)
        withIdle.idleDecisions = [
            IdleDecision(
                idleStart: epoch.addingTimeInterval(2 * 3600),
                idleEnd: epoch.addingTimeInterval(3 * 3600),
                decision: .pause
            )
        ]

        let workday = Workday(
            payload: withIdle,
            autoBreakRules: AutoBreakRules(after6hMinutes: 30, after9hMinutes: 45),
            thresholds: standardLadder
        )

        XCTAssertEqual(workday.netWorkTime, 4 * 3600, accuracy: 0.5)
    }

    func testIdlePeriodDecidedAsWorkIsNotDeducted() {
        var withIdle = payload(hoursWorked: 5)
        withIdle.idleDecisions = [
            IdleDecision(
                idleStart: epoch.addingTimeInterval(2 * 3600),
                idleEnd: epoch.addingTimeInterval(3 * 3600),
                decision: .work
            )
        ]

        let workday = Workday(
            payload: withIdle,
            autoBreakRules: AutoBreakRules(after6hMinutes: 30, after9hMinutes: 45),
            thresholds: standardLadder
        )

        XCTAssertEqual(workday.netWorkTime, 5 * 3600, accuracy: 0.5)
    }

    // MARK: - Threshold Level

    func testPauseCombinesManualAndIdle() {
        var entry = payload(hoursWorked: 8, manualPauseSeconds: 600)
        entry.idleDecisions = [
            IdleDecision(
                idleStart: epoch.addingTimeInterval(3600),
                idleEnd: epoch.addingTimeInterval(4200),
                decision: .pause
            )
        ]

        let workday = Workday(
            payload: entry,
            autoBreakRules: AutoBreakRules(after6hMinutes: 30, after9hMinutes: 45),
            thresholds: standardLadder
        )

        XCTAssertEqual(workday.manualPause, 600, accuracy: 0.5)
        XCTAssertEqual(workday.idlePause, 600, accuracy: 0.5)
        XCTAssertEqual(workday.pause, 1200, accuracy: 0.5)
    }

    func testPauseCountsTowardsTheAutoBreakOwed() {
        // 8h gross, 15min Pause: 7h45m worked, 30min owed past 6h, 15min of it
        // already taken, so 15min more is deducted.
        let workday = Workday(
            payload: payload(hoursWorked: 8, manualPauseSeconds: 900),
            autoBreakRules: AutoBreakRules(after6hMinutes: 30, after9hMinutes: 45),
            thresholds: standardLadder
        )

        XCTAssertEqual(workday.autoBreak, 900, accuracy: 0.5)
        XCTAssertEqual(workday.netWorkTime, 7 * 3600 + 30 * 60, accuracy: 0.5)
    }

    func testNetWorkTimeIsNeverNegativeWhenPauseExceedsGross() {
        let workday = Workday(
            payload: payload(hoursWorked: 1, manualPauseSeconds: 7200),
            autoBreakRules: AutoBreakRules(after6hMinutes: 30, after9hMinutes: 45),
            thresholds: standardLadder
        )

        XCTAssertEqual(workday.netWorkTime, 0, accuracy: 0.5)
    }

    private func workday(hoursWorked: Double) -> Workday {
        Workday(
            payload: payload(hoursWorked: hoursWorked),
            autoBreakRules: AutoBreakRules(after6hMinutes: 0, after9hMinutes: 0),
            thresholds: standardLadder
        )
    }

    func testThresholdLevelIsNormalBelowTheElevatedThreshold() {
        XCTAssertEqual(workday(hoursWorked: 7).thresholdLevel, .normal)
    }

    func testThresholdLevelIsElevatedAtTheElevatedThreshold() {
        XCTAssertEqual(workday(hoursWorked: 8).thresholdLevel, .elevated)
    }

    func testThresholdLevelIsCriticalAtTheCriticalThreshold() {
        XCTAssertEqual(workday(hoursWorked: 9.5).thresholdLevel, .critical)
    }

    func testThresholdLevelUsesConfiguredLadder() {
        let workday = Workday(
            payload: payload(hoursWorked: 7),
            autoBreakRules: AutoBreakRules(after6hMinutes: 0, after9hMinutes: 0),
            thresholds: ThresholdLadder(elevatedHours: 6.0, criticalHours: 6.5)
        )

        XCTAssertEqual(workday.thresholdLevel, .critical)
    }

    func testThresholdLevelIsDerivedFromNetNotGrossTime() {
        // 7h gross with a full hour of Pause is 6h net, below an 8h Threshold.
        let workday = Workday(
            payload: payload(hoursWorked: 7, manualPauseSeconds: 3600),
            autoBreakRules: AutoBreakRules(after6hMinutes: 0, after9hMinutes: 0),
            thresholds: standardLadder
        )

        XCTAssertEqual(workday.thresholdLevel, .normal)
    }

    // MARK: - Transitions

    private func runningWorkday() -> Workday {
        Workday(
            payload: payload(hoursWorked: 0, status: .running),
            autoBreakRules: AutoBreakRules(after6hMinutes: 30, after9hMinutes: 45),
            thresholds: standardLadder
        )
    }

    func testEndingClosesAnOpenPause() {
        let paused = runningWorkday().paused(at: epoch.addingTimeInterval(2 * 3600))
        let ended = paused.ended(at: epoch.addingTimeInterval(3 * 3600))

        XCTAssertEqual(ended.status, .ended)
        XCTAssertNil(ended.payload.pauseStartedAt)
        XCTAssertEqual(ended.payload.manualPauseSeconds, 3600, accuracy: 0.5)
    }

    func testEndingBeforeAnOpenPauseStartedDoesNotSubtractPause() {
        let paused = runningWorkday().paused(at: epoch.addingTimeInterval(4 * 3600))
        let ended = paused.ended(at: epoch.addingTimeInterval(1 * 3600))

        XCTAssertEqual(ended.payload.manualPauseSeconds, 0, accuracy: 0.5)
    }

    func testEndingAnEndedWorkdayDoesNotOverwriteItsEnd() {
        let first = epoch.addingTimeInterval(8 * 3600)
        let ended = runningWorkday().ended(at: first)

        let again = ended.ended(at: epoch.addingTimeInterval(12 * 3600))

        XCTAssertEqual(again.endTime, first)
    }

    func testOverlappingIdlePausesAreOnlyCountedOnceAndClippedToWorkday() {
        let workday = runningWorkday()
            .recording(IdleDecision(
                idleStart: epoch.addingTimeInterval(-3600),
                idleEnd: epoch.addingTimeInterval(3600), decision: .pause))
            .recording(IdleDecision(
                idleStart: epoch,
                idleEnd: epoch.addingTimeInterval(7200), decision: .pause))
            .ended(at: epoch.addingTimeInterval(5400))

        XCTAssertEqual(workday.idlePause, 5400)
        XCTAssertEqual(workday.netWorkTime, 0)
        XCTAssertEqual(workday.grossTime(endingAt: epoch.addingTimeInterval(10_000)), 5400)
    }

    func testEndingBeforeStartClampsEndToStart() {
        let ended = runningWorkday().ended(at: epoch.addingTimeInterval(-3600))

        XCTAssertEqual(ended.endTime, epoch)
        XCTAssertEqual(ended.netWorkTime, 0)
    }

    func testResumingAccumulatesPause() {
        let resumed = runningWorkday()
            .paused(at: epoch.addingTimeInterval(1 * 3600))
            .resumed(at: epoch.addingTimeInterval(2 * 3600))

        XCTAssertEqual(resumed.status, .running)
        XCTAssertNil(resumed.payload.pauseStartedAt)
        XCTAssertEqual(resumed.payload.manualPauseSeconds, 3600, accuracy: 0.5)
    }

    func testTransitionsKeepConfiguration() {
        let rules = AutoBreakRules(after6hMinutes: 20, after9hMinutes: 40)
        let workday = Workday(
            payload: payload(hoursWorked: 0, status: .running),
            autoBreakRules: rules,
            thresholds: standardLadder
        )

        let ended = workday.ended(at: epoch.addingTimeInterval(7 * 3600))

        XCTAssertEqual(ended.autoBreakRules.after6hMinutes, 20)
        XCTAssertEqual(ended.netWorkTime, 6 * 3600 + 40 * 60, accuracy: 0.5)
    }
}
