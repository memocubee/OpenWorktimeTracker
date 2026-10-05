import XCTest

@testable import OpenWorktimeTracker

/// Guards the Daily Log file format. CONTEXT.md commits to Daily Logs being
/// readable and exportable by hand, and PersistenceManager decodes with `try?`,
/// so a schema break returns nil and silently loses the day rather than erroring.
///
/// The fixture below is the format as shipped. Changing it is a breaking change
/// to users' files, not a refactor.
final class DailyLogFormatTests: XCTestCase {

    private let fixture = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "date": "2026-03-17",
          "startTime": "2026-03-17T07:30:00Z",
          "endTime": "2026-03-17T16:45:00Z",
          "status": "ended",
          "manualPauseSeconds": 1800,
          "idleDecisions": [
            {
              "id": "6B29FC40-CA47-1067-B31D-00DD010662DA",
              "idleStart": "2026-03-17T12:00:00Z",
              "idleEnd": "2026-03-17T12:30:00Z",
              "decision": "pause"
            }
          ],
          "notifiedThresholds": ["normal"],
          "note": "Sprint review"
        }
        """

    private func decodeFixture() throws -> TimeEntry {
        try decode(fixture)
    }

    private func decode(_ json: String) throws -> TimeEntry {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TimeEntry.self, from: Data(json.utf8))
    }

    func testAShippedDailyLogStillDecodes() throws {
        let entry = try decodeFixture()

        XCTAssertEqual(entry.date, "2026-03-17")
        XCTAssertEqual(entry.status, .ended)
        XCTAssertEqual(entry.manualPauseSeconds, 1800)
        XCTAssertEqual(entry.note, "Sprint review")
        XCTAssertEqual(entry.idleDecisions.count, 1)
        XCTAssertEqual(entry.idleDecisions.first?.decision, .pause)
        XCTAssertTrue(entry.notifiedThresholds.contains(.normal))
        XCTAssertNil(entry.pauseStartedAt)
        XCTAssertNil(entry.lastActivityTime)
    }

    func testAShippedDailyLogDerivesTheExpectedNetWorkTime() throws {
        let workday = Workday(
            payload: try decodeFixture(),
            autoBreakRules: AutoBreakRules(after6hMinutes: 30, after9hMinutes: 45),
            thresholds: ThresholdLadder(elevatedHours: 8.0, criticalHours: 9.5)
        )

        // 07:30 to 16:45 is 9h15m gross. 30min Pause plus a 30min Idle Period
        // decided as a Pause leaves 8h15m, which is past the 6h threshold but
        // already covers the 30min owed, so no Auto Break is added.
        XCTAssertEqual(workday.grossTime, 9 * 3600 + 15 * 60, accuracy: 0.5)
        XCTAssertEqual(workday.autoBreak, 0, accuracy: 0.5)
        XCTAssertEqual(workday.netWorkTime, 8 * 3600 + 15 * 60, accuracy: 0.5)
        XCTAssertEqual(workday.thresholdLevel, .elevated)
    }

    func testAShippedDailyLogLoadsThroughPersistenceManager() throws {
        // Goes through PersistenceManager's own coders, so changing its date
        // strategy fails here rather than in users' files.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = PersistenceManager(logDirectory: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try Data(fixture.utf8).write(
            to: tempDir.appendingPathComponent("2026-03-17.json"),
            options: .atomic
        )

        let loaded = try XCTUnwrap(persistence.load(for: "2026-03-17"))
        XCTAssertEqual(loaded.status, .ended)
        XCTAssertEqual(loaded.manualPauseSeconds, 1800)
        XCTAssertEqual(loaded.idleDecisions.count, 1)

        // Written back out, it still loads.
        persistence.save(loaded)
        persistence.flush()
        XCTAssertNotNil(persistence.load(for: "2026-03-17"))
    }

    func testEncodingKeepsTheShippedKeySet() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(try decodeFixture())
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(
            Set(object.keys),
            [
                "id", "date", "startTime", "endTime", "status", "manualPauseSeconds",
                "idleDecisions", "notifiedThresholds", "note"
            ]
        )
    }

    private func decodeFixture(notifiedThresholds: String) throws -> TimeEntry {
        try decode(fixture.replacingOccurrences(
            of: #""notifiedThresholds": ["normal"]"#,
            with: #""notifiedThresholds": \#(notifiedThresholds)"#))
    }

    private func encodedNotifiedThresholds(of entry: TimeEntry) throws -> [String] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(entry)) as? [String: Any]
        )
        return try XCTUnwrap(object["notifiedThresholds"] as? [String])
    }

    func testNotifiedThresholdsWrittenByThePreviousVersionDecode() throws {
        let entry = try decodeFixture(notifiedThresholds: #"["normal", "critical", "milestone"]"#)

        XCTAssertEqual(entry.notifiedThresholds, [.normal, .critical, .milestone])
    }

    func testNotifiedThresholdsEncodeAsTheShippedStrings() throws {
        var entry = try decodeFixture()
        entry.notifiedThresholds = [.normal, .critical, .milestone]

        XCTAssertEqual(
            Set(try encodedNotifiedThresholds(of: entry)),
            ["normal", "critical", "milestone"]
        )
    }

    func testAnUnknownNotifiedThresholdDoesNotMakeTheDailyLogUnreadable() throws {
        let entry = try decodeFixture(notifiedThresholds: #"["normal", "weekly"]"#)

        XCTAssertTrue(entry.notifiedThresholds.contains(.normal))
        XCTAssertEqual(Set(try encodedNotifiedThresholds(of: entry)), ["normal", "weekly"])
    }

    func testOptionalLastActivityRoundTripsWithoutChangingOtherFields() throws {
        var entry = try decodeFixture()
        entry.lastActivityTime = entry.startTime.addingTimeInterval(3600)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(TimeEntry.self, from: encoder.encode(entry))

        XCTAssertEqual(decoded.lastActivityTime, entry.lastActivityTime)
        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.endTime, entry.endTime)
    }

    // MARK: - Daily Logs written by 0.7.2 (Pause intervals)

    func testA072DailyLogFoldsClosedPauseIntervalsIntoTheTotal() throws {
        let entry = try decode("""
            {
              "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
              "date": "2026-09-30",
              "startTime": "2026-09-30T01:00:00Z",
              "endTime": "2026-09-30T09:00:00Z",
              "status": "ended",
              "manualPauseSeconds": 600,
              "pauses": [
                { "id": "6B29FC40-CA47-1067-B31D-00DD010662DA",
                  "start": "2026-09-30T04:00:00Z", "end": "2026-09-30T04:30:00Z" },
                { "id": "6B29FC40-CA47-1067-B31D-00DD010662DB",
                  "start": "2026-09-30T08:50:00Z", "end": "2026-09-30T09:20:00Z" }
              ],
              "idleDecisions": [],
              "notifiedThresholds": [],
              "note": ""
            }
            """)

        // 600s legacy + 30min + the 10min of the second Pause inside the Workday.
        XCTAssertEqual(entry.manualPauseSeconds, 600 + 1800 + 600)
        XCTAssertNil(entry.pauseStartedAt)
        XCTAssertEqual(entry.status, .ended)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let written = try XCTUnwrap(String(bytes: try encoder.encode(entry), encoding: .utf8))
        XCTAssertFalse(written.contains("pauses"), "pauses must not be written back")
    }

    func testA072DailyLogWithOneClosedPauseAndLegacySeconds() throws {
        let entry = try decode("""
            {
              "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
              "date": "2026-09-30",
              "startTime": "2026-09-30T01:00:00Z",
              "endTime": "2026-09-30T09:00:00Z",
              "status": "ended",
              "manualPauseSeconds": 600,
              "pauses": [
                { "id": "6B29FC40-CA47-1067-B31D-00DD010662DA",
                  "start": "2026-09-30T04:00:00Z", "end": "2026-09-30T04:30:00Z" }
              ],
              "idleDecisions": [],
              "notifiedThresholds": [],
              "note": ""
            }
            """)

        XCTAssertEqual(entry.manualPauseSeconds, 2400)
    }

    func testA072DailyLogWithAnOpenPauseIntervalStaysPaused() throws {
        let entry = try decode("""
            {
              "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
              "date": "2026-09-30",
              "startTime": "2026-09-30T01:00:00Z",
              "status": "paused",
              "manualPauseSeconds": 0,
              "pauses": [
                { "id": "6B29FC40-CA47-1067-B31D-00DD010662DA",
                  "start": "2026-09-30T03:00:00Z", "end": "2026-09-30T03:15:00Z" },
                { "id": "6B29FC40-CA47-1067-B31D-00DD010662DB",
                  "start": "2026-09-30T05:00:00Z" }
              ],
              "idleDecisions": [],
              "notifiedThresholds": [],
              "note": ""
            }
            """)

        XCTAssertEqual(entry.status, .paused)
        XCTAssertEqual(entry.manualPauseSeconds, 900)
        XCTAssertEqual(entry.pauseStartedAt, ISO8601DateFormatter().date(from: "2026-09-30T05:00:00Z"))
    }
}
