import XCTest
@testable import StepTrack

final class ActivitySnapshotTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }
    private func date(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    func testYesterdayDoesNotLeakIntoTodayOrWidgetMidnightEntry() {
        let value = ActivitySnapshot(updatedAt: date(5, hour: 23), days: [.init(date: date(5), steps: 9000)], meters: 6000, goal: 8000)
        XCTAssertEqual(value.steps(on: date(5, hour: 23), calendar: calendar), 9000)
        XCTAssertEqual(value.steps(on: date(6), calendar: calendar), 0)
        XCTAssertEqual(value.progress(on: date(6), calendar: calendar), 0)
    }
    func testProgressClampsAndHandlesZeroGoal() {
        var value = ActivitySnapshot(updatedAt: date(5), days: [.init(date: date(5), steps: 12000)], meters: nil, goal: 8000)
        XCTAssertEqual(value.progress(on: date(5), calendar: calendar), 1)
        value.goal = 0
        XCTAssertTrue(value.progress(on: date(5), calendar: calendar).isFinite)
        value.goal = 24000
        XCTAssertEqual(value.progress(on: date(5), calendar: calendar), 0.5)
    }
    func testSnapshotRoundTripKeepsUnknownDistance() throws {
        let value = ActivitySnapshot(updatedAt: date(5), days: [.init(date: date(5), steps: 300)], meters: nil, goal: 8000)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(ActivitySnapshot.self, from: data), value)
    }
    func testLocalDayBoundaryAcrossDaylightSaving() {
        var zone = Calendar(identifier: .gregorian)
        zone.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let before = zone.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!
        let after = zone.date(byAdding: .day, value: 1, to: before)!
        let value = ActivitySnapshot(updatedAt: before, days: [.init(date: before, steps: 150)], meters: nil, goal: 8000)
        XCTAssertEqual(after.timeIntervalSince(before), 25 * 3600)
        XCTAssertEqual(value.steps(on: after, calendar: zone), 0)
    }
}
