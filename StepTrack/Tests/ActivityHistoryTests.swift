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
}
