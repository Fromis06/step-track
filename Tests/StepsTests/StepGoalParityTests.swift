import XCTest
@preconcurrency import UserNotifications
@testable import StepTrack

private final class ParityMockNotificationCenter: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [UNNotificationRequest] = []
    private var removeAllCount = 0

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func add(_ request: UNNotificationRequest) async throws {
        withLock {
            requests.append(request)
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        withLock {
            requests
        }
    }

    func removeAllPendingNotificationRequests() {
        withLock {
            removeAllCount += 1
            requests.removeAll()
        }
    }

    func recordedRemoveAllCount() -> Int {
        withLock {
            removeAllCount
        }
    }
}

final class StepGoalParityTests: XCTestCase {
    private var savedDailyGoal: Any?

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }

    override func setUp() {
        super.setUp()
        savedDailyGoal = ActivityStorage.defaults.object(forKey: "dailyGoal")
        ActivityStorage.defaults.removeObject(forKey: "dailyGoal")
    }

    override func tearDown() {
        if let savedDailyGoal {
            ActivityStorage.defaults.set(savedDailyGoal, forKey: "dailyGoal")
        } else {
            ActivityStorage.defaults.removeObject(forKey: "dailyGoal")
        }
        super.tearDown()
    }

    func testGoalChecklistMissingFileAndCorruptJSONBehavior() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let missingURL = directory.appendingPathComponent("missing-goals.json")
        let emptyStore = try GoalChecklistStore.load(from: missingURL)
        XCTAssertTrue(emptyStore.items.isEmpty)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corruptURL = directory.appendingPathComponent("corrupt-goals.json")
        try Data("{not-valid-json".utf8).write(to: corruptURL)
        XCTAssertThrowsError(try GoalChecklistStore.load(from: corruptURL))
    }

    func testGoalChecklistDeleteIncompleteAndUnknownUUIDToggleNoOp() {
        var store = GoalChecklistStore()
        store.addGoal(title: "\n \t ")
        XCTAssertTrue(store.items.isEmpty)

        store.addGoal(title: "Walk 8,000 steps", isComplete: false)
        store.addGoal(title: "Log sleep", isComplete: true)
        store.addGoal(title: "Hydrate 2,500 ml", isComplete: false)

        let unknownID = UUID()
        let before = store
        store.toggleCompletion(id: unknownID)
        XCTAssertEqual(store, before)

        // Delete second incomplete item ("Hydrate 2,500 ml") by filtered offset.
        store.deleteGoals(at: IndexSet(integer: 1), isComplete: false)
        XCTAssertEqual(store.incompleteGoals.map(\.title), ["Walk 8,000 steps"])
        XCTAssertEqual(store.completeGoals.map(\.title), ["Log sleep"])
    }

    func testDailyReminderCustomScheduleAndDefaultRemoveForwarding() async throws {
        let scheduler = DailyReminderScheduler()
        let center = ParityMockNotificationCenter()

        try await scheduler.scheduleDailyReminder(hour: 21, minute: 30, using: center)
        try await Task.sleep(for: .milliseconds(50))

        let pending = await center.pendingNotificationRequests()
        XCTAssertEqual(pending.count, 1)
        let trigger = try XCTUnwrap(pending.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 21)
        XCTAssertEqual(trigger.dateComponents.minute, 30)
        XCTAssertTrue(trigger.repeats)

        let removeCallsBefore = await center.recordedRemoveAllCount()
        // Default protocol extension forwards removePendingNotificationRequests(withIdentifiers:)
        // to removeAllPendingNotificationRequests().
        center.removePendingNotificationRequests(withIdentifiers: [DailyReminderScheduler.reminderIdentifier])
        try await Task.sleep(for: .milliseconds(50))

        let removeCallsAfter = await center.recordedRemoveAllCount()
        XCTAssertEqual(removeCallsAfter, removeCallsBefore + 1)
        let remaining = await center.pendingNotificationRequests()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testStepGoalRevisionParityWithoutCoreData() {
        let d1 = HistoryCalendar.date(for: "2026-10-01", calendar: calendar)!
        let d2 = HistoryCalendar.date(for: "2026-10-02", calendar: calendar)!
        let d3 = HistoryCalendar.date(for: "2026-10-03", calendar: calendar)!

        var history = ActivityHistory()
        history.changeGoal(8_000, on: d1, calendar: calendar)
        history.setManualSteps(8_500, on: d1, observedAt: d1, calendar: calendar)
        history.setManualSteps(8_100, on: d2, observedAt: d2, calendar: calendar)

        // Revise goal upward on day 3; past days retain 8,000 target and remain achieved.
        history.changeGoal(12_000, on: d3, calendar: calendar)
        history.setManualSteps(9_000, on: d3, observedAt: d3, calendar: calendar)

        XCTAssertEqual(history.days["2026-10-01"]?.goal, 8_000)
        XCTAssertEqual(history.days["2026-10-01"]?.reachedGoal, true)
        XCTAssertEqual(history.days["2026-10-02"]?.goal, 8_000)
        XCTAssertEqual(history.days["2026-10-02"]?.reachedGoal, true)
        XCTAssertEqual(history.days["2026-10-03"]?.goal, 12_000)
        XCTAssertEqual(history.days["2026-10-03"]?.reachedGoal, false)

        // ActivityStorage goal clamping parity.
        XCTAssertEqual(ActivityStorage.goal, 8_000)
        ActivityStorage.goal = 100
        XCTAssertEqual(ActivityStorage.goal, 500)
        ActivityStorage.goal = 100_000
        XCTAssertEqual(ActivityStorage.goal, 50_000)
        ActivityStorage.goal = 12_000
        XCTAssertEqual(ActivityStorage.goal, 12_000)
    }
}
