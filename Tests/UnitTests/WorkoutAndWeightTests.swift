import XCTest
@preconcurrency import UserNotifications
@testable import StepTrack

private final class RestTimerMockNotificationCenter: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var addedRequests: [UNNotificationRequest] = []
    private var removedIdentifiers: [[String]] = []

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
            addedRequests.append(request)
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        withLock {
            addedRequests
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        withLock {
            removedIdentifiers.append(identifiers)
        }
    }

    func removeAllPendingNotificationRequests() {}

    func recordedAdds() -> [UNNotificationRequest] {
        withLock {
            addedRequests
        }
    }

    func recordedRemovals() -> [[String]] {
        withLock {
            removedIdentifiers
        }
    }
}

final class WorkoutAndWeightTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutAndWeightTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testWeeklySplitNormalizeDefaultAssignAndTodayAssignment() {
        let partial = WeeklySplit(days: [
            DaySchedule(weekday: .monday, split: .push, title: "Push A"),
            DaySchedule(weekday: .monday, split: .pull, title: "Push B"),
            DaySchedule(weekday: .friday, split: .legs, title: "  ")
        ])

        XCTAssertEqual(partial.days.count, 7)
        XCTAssertEqual(partial.days.map(\.weekday), Weekday.allCases)
        // Duplicate Monday keeps the first one assigned, empty Friday falls back to split.titleKey.
        XCTAssertEqual(partial.schedule(for: .monday).split, .push)
        XCTAssertEqual(partial.schedule(for: .monday).title, "Push A")
        XCTAssertEqual(partial.schedule(for: .friday).title, "Legs")
        XCTAssertEqual(partial.schedule(for: .wednesday).split, .rest)

        var split = WeeklySplit.defaultSplit
        XCTAssertEqual(split.schedule(for: .monday).split, .push)
        XCTAssertEqual(split.schedule(for: .thursday).split, .rest)
        XCTAssertEqual(split.schedule(for: .sunday).split, .rest)

        split.assign(.wednesday, split: .custom, title: "Arm Day", muscleGroups: [.upperArms], exerciseIDs: ["0010", "0011"])
        let wed = split.schedule(for: .wednesday)
        XCTAssertEqual(wed.split, .custom)
        XCTAssertEqual(wed.title, "Arm Day")
        XCTAssertEqual(wed.muscleGroups, [.upperArms])
        XCTAssertEqual(wed.exerciseIDs, ["0010", "0011"])

        split.assign(.sunday, split: .rest, title: "", muscleGroups: [], exerciseIDs: [])
        XCTAssertTrue(split.schedule(for: .sunday).split.isRest)
        XCTAssertEqual(split.schedule(for: .sunday).title, "Rest")
        XCTAssertTrue(split.schedule(for: .sunday).exerciseIDs.isEmpty)
    }

    func testExerciseSetLogClampingDecimalsE1RMAndPersonalRecordDetector() {
        let decimalSet = ExerciseSetLog(setNumber: 1, weightKg: 62.5, reps: 8, rpe: 8.5)
        XCTAssertEqual(decimalSet.weightKg, 62.5, accuracy: 0.0001)
        XCTAssertEqual(decimalSet.volumeKg, 500.0, accuracy: 0.0001)

        let microSet = ExerciseSetLog(setNumber: 2, weightKg: 102.25, reps: 5, rpe: 9.0)
        XCTAssertEqual(microSet.weightKg, 102.25, accuracy: 0.0001)

        let plateSet = ExerciseSetLog(setNumber: 3, weightKg: 2.5, reps: 12)
        XCTAssertEqual(plateSet.weightKg, 2.5, accuracy: 0.0001)

        let clampedSet = ExerciseSetLog(setNumber: 0, weightKg: -20, reps: -5, rpe: 15.0, isCompleted: false)
        XCTAssertEqual(clampedSet.setNumber, 1)
        XCTAssertEqual(clampedSet.weightKg, 0)
        XCTAssertEqual(clampedSet.reps, 0)
        XCTAssertEqual(clampedSet.rpe, 10.0)
        XCTAssertNil(clampedSet.completedAt)
        XCTAssertEqual(clampedSet.volumeKg, 0)

        let lowRpeSet = ExerciseSetLog(setNumber: 1, weightKg: 500, reps: 1, rpe: 0.2)
        XCTAssertEqual(lowRpeSet.weightKg, 500)
        XCTAssertEqual(lowRpeSet.rpe, 1.0)

        // Epley e1RM formula checks.
        XCTAssertEqual(ExerciseSetLog.estimated1RM(weightKg: 100, reps: 0), 0)
        XCTAssertEqual(ExerciseSetLog.estimated1RM(weightKg: 0, reps: 8), 0)
        XCTAssertEqual(ExerciseSetLog.estimated1RM(weightKg: 120, reps: 1), 120.0, accuracy: 0.0001)
        XCTAssertEqual(ExerciseSetLog.estimated1RM(weightKg: 100, reps: 6), 120.0, accuracy: 0.0001)

        // PersonalRecordDetector threshold checks.
        XCTAssertFalse(PersonalRecordDetector.isPersonalRecord(weightKg: 0, reps: 10, priorBestE1RM: nil))
        XCTAssertTrue(PersonalRecordDetector.isPersonalRecord(weightKg: 60, reps: 5, priorBestE1RM: nil))
        XCTAssertTrue(PersonalRecordDetector.isPersonalRecord(weightKg: 60, reps: 5, priorBestE1RM: 0))
        XCTAssertFalse(PersonalRecordDetector.isPersonalRecord(weightKg: 100, reps: 6, priorBestE1RM: 120.0))
        XCTAssertTrue(PersonalRecordDetector.isPersonalRecord(weightKg: 102.5, reps: 6, priorBestE1RM: 120.0))
    }

    func testWorkoutTemplateClamping() {
        let low = WorkoutTemplate(name: "  ", split: .upper, exerciseIDs: ["0025"], defaultSetsPerExercise: 0)
        XCTAssertEqual(low.name, "Upper")
        XCTAssertEqual(low.defaultSetsPerExercise, 1)

        let high = WorkoutTemplate(name: "Volume", split: .fullBody, exerciseIDs: ["0025"], defaultSetsPerExercise: 99)
        XCTAssertEqual(high.name, "Volume")
        XCTAssertEqual(high.defaultSetsPerExercise, 12)
    }

    @MainActor
    func testFitnessStoreSessionLoggingPreviousSetsPRsAndEmptyFiltering() {
        let store = FitnessStore(localStore: LocalStore(directory: tempDirectory), notificationCenter: nil, isFixture: false)

        let todayWeekday = Weekday.from(date: Date())
        store.assignDay(todayWeekday, split: .push, title: "Push Power", muscleGroups: [.chest, .shoulders], exerciseIDs: ["0025", "0043"])
        XCTAssertEqual(store.todayAssignment.title, "Push Power")

        // Empty session with 0 completed sets must not persist to sessions.
        store.startSession(from: store.todayAssignment)
        XCTAssertEqual(store.activeSession?.exercises.count, 2)
        store.finishActiveSession()
        XCTAssertNil(store.activeSession)
        XCTAssertTrue(store.sessions.isEmpty)

        // Log sets on one exercise and leave the second exercise with 0 completed sets.
        store.startSession(from: store.todayAssignment)
        store.logSet(exerciseID: "0025", exerciseName: "Barbell Bench Press", weightKg: 80, reps: 8, rpe: 8)
        store.logSet(exerciseID: "0025", exerciseName: "Barbell Bench Press", weightKg: 85, reps: 5, rpe: 9)
        store.finishActiveSession()

        XCTAssertEqual(store.sessions.count, 1)
        // Exercise "0043" had 0 completed sets so it was filtered out.
        XCTAssertEqual(store.sessions.first?.exercises.count, 1)
        XCTAssertEqual(store.previousSets(for: "0025").count, 2)
        XCTAssertEqual(store.previousSets(for: "0025").first?.weightKg, 80)

        let expectedFirstBest = ExerciseSetLog.estimated1RM(weightKg: 80, reps: 8)
        XCTAssertEqual(store.bestE1RM(for: "0025") ?? 0, expectedFirstBest, accuracy: 0.001)
        XCTAssertNil(store.bestE1RM(for: "unknown-exercise"))

        // Second session beats previous e1RM and sets PR flag.
        store.startSession()
        store.logSet(exerciseID: "0025", exerciseName: "Barbell Bench Press", weightKg: 90, reps: 8, rpe: 9.5)
        let loggedSet = store.activeSession?.exercises.first?.sets.first
        XCTAssertEqual(loggedSet?.isPersonalRecord, true)

        // Toggle completion off, then delete set.
        if let entryID = store.activeSession?.exercises.first?.id, let setID = loggedSet?.id {
            store.toggleSetCompletion(exerciseEntryID: entryID, setID: setID)
            XCTAssertEqual(store.activeSession?.exercises.first?.sets.first?.isCompleted, false)
            store.toggleSetCompletion(exerciseEntryID: entryID, setID: setID)
            XCTAssertEqual(store.activeSession?.exercises.first?.sets.first?.isCompleted, true)
            store.deleteSet(exerciseEntryID: entryID, setID: setID)
            XCTAssertTrue(store.activeSession?.exercises.first?.sets.isEmpty ?? false)
        } else {
            XCTFail("Expected active set to exist")
        }
        store.finishActiveSession()
        // All sets deleted, so second session should not be saved.
        XCTAssertEqual(store.sessions.count, 1)
    }

    @MainActor
    func testRestTimerClampingAdjustmentsAndNotificationCancellation() async throws {
        let mockCenter = RestTimerMockNotificationCenter()
        let store = FitnessStore(localStore: LocalStore(directory: tempDirectory), notificationCenter: mockCenter, isFixture: false)
        defer { store.stopRestTimer() }

        store.startRestTimer(seconds: 1)
        XCTAssertEqual(store.restRemainingSeconds, 5)
        XCTAssertEqual(store.restTotalSeconds, 5)
        XCTAssertTrue(store.isRestTimerRunning)

        store.startRestTimer(seconds: 9_999)
        XCTAssertEqual(store.restRemainingSeconds, 3_600)
        XCTAssertEqual(store.restTotalSeconds, 3_600)

        store.stopRestTimer()
        XCTAssertFalse(store.isRestTimerRunning)
        XCTAssertEqual(store.restRemainingSeconds, 0)

        let removals = mockCenter.recordedRemovals()
        XCTAssertTrue(removals.contains { $0 == [FitnessStore.restTimerNotificationID] })

        store.startRestTimer(seconds: 20)
        store.adjustRestTimer(delta: 15)
        XCTAssertEqual(store.restRemainingSeconds, 35)
        XCTAssertEqual(store.restTotalSeconds, 35)

        store.adjustRestTimer(delta: -50)
        XCTAssertEqual(store.restRemainingSeconds, 0)
        XCTAssertFalse(store.isRestTimerRunning)
    }
}
