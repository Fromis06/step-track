import XCTest
@testable import StepTrack

final class ActivityHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }
    private func date(_ key: String) -> Date { HistoryCalendar.date(for: key, calendar: calendar)! }

    func testPastGoalStaysFixedAndSkippedDaysInheritTheirGoal() {
        var history = ActivityHistory()
        history.changeGoal(5000, on: date("2026-10-01"), calendar: calendar)
        history.merge([ActivityDay(date: date("2026-10-01"), steps: 5500)], observedAt: date("2026-10-01"), calendar: calendar)
        history.changeGoal(8000, on: date("2026-10-04"), calendar: calendar)
        let samples = (1...4).map { ActivityDay(date: date("2026-10-0\($0)"), steps: 6000) }
        history.merge(samples, observedAt: date("2026-10-04"), calendar: calendar)
        history.merge(samples, observedAt: date("2026-10-04"), calendar: calendar)
        XCTAssertEqual(history.days["2026-10-01"]?.goal, 5000)
        XCTAssertEqual(history.days["2026-10-03"]?.goal, 5000)
        XCTAssertEqual(history.days["2026-10-04"]?.goal, 8000)
        XCTAssertEqual(history.days["2026-10-01"]?.reachedGoal, true)
        XCTAssertEqual(history.days["2026-10-04"]?.reachedGoal, false)
        XCTAssertEqual(history.records(year: 2026, month: 10).reduce(0) { $0 + $1.steps }, 24000)
        XCTAssertEqual(history.days["2026-10-01"]?.complete, true)
        history.changeGoal(10000, on: date("2026-10-04"), calendar: calendar)
        XCTAssertEqual(history.days["2026-10-04"]?.goal, 10000)
        XCTAssertEqual(history.days["2026-10-03"]?.goal, 5000)
    }

    func testMigrationDoesNotInventPastGoals() {
        let snapshot = ActivitySnapshot(updatedAt: date("2026-10-02"), days: [
            ActivityDay(date: date("2026-10-01"), steps: 5500),
            ActivityDay(date: date("2026-10-02"), steps: 6500)
        ], meters: nil, goal: 8000)
        let history = ActivityHistory.migrating(snapshot, goal: 8000, now: date("2026-10-02"), calendar: calendar)
        XCTAssertNil(history.days["2026-10-01"]?.goal)
        XCTAssertEqual(history.days["2026-10-02"]?.goal, 8000)
    }

    func testDiskRoundTripAndYearHistorySurvivesRecentSync() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        var history = ActivityHistory()
        history.changeGoal(5000, on: date("2025-01-01"), calendar: calendar)
        history.merge([ActivityDay(date: date("2025-01-01"), steps: 6000)], observedAt: date("2025-01-02"), calendar: calendar)
        try HistoryStorage.save(history, to: url)
        var loaded = try XCTUnwrap(HistoryStorage.load(from: url))
        XCTAssertEqual(loaded, history)
        loaded.merge([ActivityDay(date: date("2026-10-01"), steps: 8000)], observedAt: date("2026-10-02"), calendar: calendar)
        XCTAssertEqual(loaded.records(year: 2025).first?.steps, 6000)
        XCTAssertEqual(loaded.records(year: 2026).count, 1)
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try HistoryStorage.load(from: url))
    }

    func testLeapMonthCalendarUsesSixRowsAndMondayFirst() {
        let cells = HistoryCalendar.monthCells(containing: date("2024-02-01"), calendar: calendar)
        XCTAssertEqual(cells.count, 42)
        XCTAssertEqual(cells.compactMap { $0 }.count, 29)
        XCTAssertNil(cells[2])
        XCTAssertEqual(cells[3], date("2024-02-01"))
    }

    func testSetManualStepsClampsRejectsFutureAndPreservesPastGoals() {
        var history = ActivityHistory()
        let day1 = date("2026-10-01")
        let day2 = date("2026-10-02")
        let futureDay = date("2026-10-05")

        history.changeGoal(6_000, on: day1, calendar: calendar)
        history.setManualSteps(7_500, on: day1, observedAt: day1, calendar: calendar)
        history.changeGoal(10_000, on: day2, calendar: calendar)
        history.setManualSteps(250_000, on: day2, observedAt: day2, calendar: calendar)
        history.setManualSteps(-120, on: day1, observedAt: day2, calendar: calendar)
        history.setManualSteps(5_000, on: futureDay, observedAt: day2, calendar: calendar)

        XCTAssertEqual(history.days["2026-10-01"]?.steps, 0)
        XCTAssertEqual(history.days["2026-10-01"]?.goal, 6_000)
        XCTAssertEqual(history.days["2026-10-01"]?.isManual, true)
        XCTAssertEqual(history.days["2026-10-01"]?.complete, true)
        XCTAssertEqual(history.days["2026-10-02"]?.steps, 200_000)
        XCTAssertEqual(history.days["2026-10-02"]?.goal, 10_000)
        XCTAssertEqual(history.days["2026-10-02"]?.isManual, true)
        XCTAssertEqual(history.days["2026-10-02"]?.complete, false)
        XCTAssertNil(history.days["2026-10-05"])
    }

    func testMergeProtectsManualDaysAndSkipsFutureSamples() {
        var history = ActivityHistory()
        let day1 = date("2026-10-01")
        let day2 = date("2026-10-02")
        let futureDay = date("2026-10-04")

        history.changeGoal(8_000, on: day1, calendar: calendar)
        history.setManualSteps(6_400, on: day1, observedAt: day2, calendar: calendar)

        // Zero or negative sensor sample must NOT overwrite a manually logged day.
        history.merge(
            [
                ActivityDay(date: day1, steps: 0),
                ActivityDay(date: day2, steps: -50),
                ActivityDay(date: futureDay, steps: 9_000)
            ],
            observedAt: day2,
            calendar: calendar
        )
        XCTAssertEqual(history.days["2026-10-01"]?.steps, 6_400)
        XCTAssertEqual(history.days["2026-10-01"]?.isManual, true)
        XCTAssertEqual(history.days["2026-10-02"]?.steps, 0)
        XCTAssertEqual(history.days["2026-10-02"]?.isManual, false)
        XCTAssertNil(history.days["2026-10-04"])

        // Positive sensor sample replaces manual day with live reading.
        history.merge([ActivityDay(date: day1, steps: 8_200)], observedAt: day2, calendar: calendar)
        XCTAssertEqual(history.days["2026-10-01"]?.steps, 8_200)
        XCTAssertEqual(history.days["2026-10-01"]?.isManual, false)
    }

    func testRecentDaysAndEstimatedCalories() {
        var history = ActivityHistory()
        let day1 = date("2026-10-01")
        let day3 = date("2026-10-03")
        history.setManualSteps(4_000, on: day1, observedAt: day3, calendar: calendar)
        history.setManualSteps(9_000, on: day3, observedAt: day3, calendar: calendar)

        XCTAssertTrue(history.recentDays(count: 0, endingAt: day3, calendar: calendar).isEmpty)
        XCTAssertTrue(history.recentDays(count: -3, endingAt: day3, calendar: calendar).isEmpty)

        let recent = history.recentDays(count: 3, endingAt: day3, calendar: calendar)
        XCTAssertEqual(recent.map(\.steps), [4_000, 0, 9_000])

        XCTAssertEqual(ActivityHistory.estimatedCalories(forSteps: 0, bodyWeightKg: 70), 0)
        XCTAssertEqual(ActivityHistory.estimatedCalories(forSteps: -500, bodyWeightKg: 70), 0)
        XCTAssertEqual(ActivityHistory.estimatedCalories(forSteps: 10_000, bodyWeightKg: 70), 400)
        // Weight below 30 kg clamps to 30 kg.
        XCTAssertEqual(
            ActivityHistory.estimatedCalories(forSteps: 7_000, bodyWeightKg: 10),
            ActivityHistory.estimatedCalories(forSteps: 7_000, bodyWeightKg: 30)
        )
    }

    func testHistoricalDayDecodingDefaultsIsManualAndInvalidCalendarFormats() throws {
        let legacyJSON = """
        {
          "id": "2025-02-15",
          "steps": 5120,
          "complete": true,
          "updatedAt": 0
        }
        """
        let decoded = try JSONDecoder().decode(HistoricalDay.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.id, "2025-02-15")
        XCTAssertEqual(decoded.steps, 5120)
        XCTAssertNil(decoded.goal)
        XCTAssertFalse(decoded.isManual)
        XCTAssertFalse(decoded.reachedGoal)

        XCTAssertNil(HistoryCalendar.date(for: "", calendar: calendar))
        XCTAssertNil(HistoryCalendar.date(for: "2026-10", calendar: calendar))
        XCTAssertNil(HistoryCalendar.date(for: "bad-key-here", calendar: calendar))

        // Non-leap February 2025: Feb 1, 2025 is Saturday -> 5 leading nils, 28 days, 42 total cells.
        let feb2025 = HistoryCalendar.monthCells(containing: date("2025-02-01"), calendar: calendar)
        XCTAssertEqual(feb2025.count, 42)
        XCTAssertEqual(feb2025.compactMap { $0 }.count, 28)
        XCTAssertEqual(feb2025.firstIndex(where: { $0 != nil }), 5)
        XCTAssertEqual(feb2025[5], date("2025-02-01"))
    }
}
