import XCTest
@testable import StepTrack

final class StepsTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testStepCheckpointsReached() {
        let day = Date()
        let snapshot = ActivitySnapshot(
            updatedAt: day,
            days: [ActivityDay(date: day, steps: 6_789)],
            meters: 4_800,
            goal: 10_000
        )

        XCTAssertEqual(snapshot.steps(on: day, calendar: calendar), 6_789)
        XCTAssertTrue(snapshot.reached25PercentGoal(on: day, calendar: calendar))
        XCTAssertTrue(snapshot.reached50PercentGoal(on: day, calendar: calendar))
        XCTAssertFalse(snapshot.reached75PercentGoal(on: day, calendar: calendar))
        XCTAssertFalse(snapshot.reached100PercentGoal(on: day, calendar: calendar))

        let zeroGoalSnapshot = ActivitySnapshot(
            updatedAt: day,
            days: [ActivityDay(date: day, steps: 6_789)],
            meters: nil,
            goal: 0
        )
        XCTAssertFalse(zeroGoalSnapshot.reached25PercentGoal(on: day, calendar: calendar))
        XCTAssertFalse(zeroGoalSnapshot.reached100PercentGoal(on: day, calendar: calendar))

        let exactBoundary = ActivitySnapshot(
            updatedAt: day,
            days: [ActivityDay(date: day, steps: 10_000)],
            meters: nil,
            goal: 10_000
        )
        XCTAssertTrue(exactBoundary.reached75PercentGoal(on: day, calendar: calendar))
        XCTAssertTrue(exactBoundary.reached100PercentGoal(on: day, calendar: calendar))
    }

    func testGoalValidationClampsToSupportedRange() {
        let now = Date()
        var history = ActivityHistory()
        history.changeGoal(100, on: now, calendar: calendar)
        XCTAssertEqual(history.goal(on: HistoryCalendar.key(for: now, calendar: calendar)), 500)

        history.changeGoal(90_000, on: now, calendar: calendar)
        XCTAssertEqual(history.goal(on: HistoryCalendar.key(for: now, calendar: calendar)), 50_000)

        history.changeGoal(12_500, on: now, calendar: calendar)
        XCTAssertEqual(history.goal(on: HistoryCalendar.key(for: now, calendar: calendar)), 12_500)
    }

    func testStrideUnitCalculation() {
        let day = Date()
        let zero = ActivitySnapshot(updatedAt: day, days: [ActivityDay(date: day, steps: 0)], meters: nil, goal: 8_000)
        XCTAssertEqual(zero.estimatedStrideUnits(on: day, calendar: calendar), 0)

        let one = ActivitySnapshot(updatedAt: day, days: [ActivityDay(date: day, steps: 145)], meters: nil, goal: 8_000)
        XCTAssertEqual(one.estimatedStrideUnits(on: day, calendar: calendar), 1)

        let two = ActivitySnapshot(updatedAt: day, days: [ActivityDay(date: day, steps: 289)], meters: nil, goal: 8_000)
        XCTAssertEqual(two.estimatedStrideUnits(on: day, calendar: calendar), 2)
        XCTAssertEqual(two.estimatedStrideUnits(on: day, calendar: calendar, stepsPerUnit: 0), 0)
    }
}
