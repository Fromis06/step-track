import XCTest
@testable import StepTrack

final class BackupAndStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var savedDailyGoal: Any?
    private var savedSnapshot: Any?
    private var savedTrackingEnabled: Any?
    private var savedManualFallback: Any?
    private var savedHistoryData: Data?

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupAndStoreTests-\(UUID().uuidString)")
        savedDailyGoal = ActivityStorage.defaults.object(forKey: "dailyGoal")
        savedSnapshot = ActivityStorage.defaults.object(forKey: "activitySnapshot")
        savedTrackingEnabled = UserDefaults.standard.object(forKey: "trackingEnabled")
        savedManualFallback = UserDefaults.standard.object(forKey: "manualStepFallback")
        savedHistoryData = try? Data(contentsOf: HistoryStorage.fileURL)

        try? HistoryStorage.clear()
        ActivityStorage.clear()
        ActivityStorage.defaults.removeObject(forKey: "dailyGoal")
        UserDefaults.standard.removeObject(forKey: "trackingEnabled")
        UserDefaults.standard.removeObject(forKey: "manualStepFallback")
    }

    override func tearDown() {
        if let savedHistoryData {
            try? FileManager.default.createDirectory(
                at: HistoryStorage.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? savedHistoryData.write(to: HistoryStorage.fileURL, options: .atomic)
        } else {
            try? HistoryStorage.clear()
        }
        savedHistoryData = nil
        restoreDefault(savedDailyGoal, key: "dailyGoal", in: ActivityStorage.defaults)
        restoreDefault(savedSnapshot, key: "activitySnapshot", in: ActivityStorage.defaults)
        restoreDefault(savedTrackingEnabled, key: "trackingEnabled", in: UserDefaults.standard)
        restoreDefault(savedManualFallback, key: "manualStepFallback", in: UserDefaults.standard)
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func restoreDefault(_ value: Any?, key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func testLocalStoreAtomicSavesAndLoadsAllDomains() throws {
        let store = LocalStore(directory: tempDirectory)
        let now = Date(timeIntervalSince1970: 1_760_000_000)

        var split = WeeklySplit.defaultSplit
        split.assign(.monday, split: .upper, title: "Heavy Upper", muscleGroups: [.chest, .back], exerciseIDs: ["0025", "0027"])
        try store.saveWeeklySplit(split)
        XCTAssertEqual(store.loadWeeklySplit(), split)

        let session = WorkoutSession(
            date: now,
            split: .upper,
            title: "Heavy Upper",
            startedAt: now,
            finishedAt: now.addingTimeInterval(2_400),
            exercises: [
                ExerciseSessionEntry(
                    exerciseID: "0025",
                    exerciseName: "Barbell Bench Press",
                    sets: [ExerciseSetLog(setNumber: 1, weightKg: 82.5, reps: 5, rpe: 8.5, isCompleted: true, isPersonalRecord: true, completedAt: now)]
                )
            ],
            notes: "Strong lockout"
        )
        try store.saveWorkoutSessions([session])
        XCTAssertEqual(store.loadWorkoutSessions(), [session])

        let template = WorkoutTemplate(name: "Upper A", split: .upper, exerciseIDs: ["0025"], defaultSetsPerExercise: 4, createdAt: now)
        try store.saveWorkoutTemplates([template])
        XCTAssertEqual(store.loadWorkoutTemplates(), [template])

        let sleep = SleepEntry(date: now, bedTime: now.addingTimeInterval(-27_000), wakeTime: now, quality: 4, note: "Rested")
        try store.saveSleepEntries([sleep])
        XCTAssertEqual(store.loadSleepEntries(), [sleep])

        let meal = MealEntry(
            date: now,
            name: "Salmon Rice Bowl",
            category: .dinner,
            calories: 680,
            macros: MacroBreakdown(proteinG: 44, carbsG: 72, fatG: 20),
            isFavorite: true
        )
        try store.saveMealEntries([meal])
        XCTAssertEqual(store.loadMealEntries(), [meal])

        let hydration = HydrationEntry(date: now, ml: 500)
        try store.saveHydrationEntries([hydration])
        XCTAssertEqual(store.loadHydrationEntries(), [hydration])

        let weight = BodyWeightEntry(date: now, weightKg: 74.2)
        try store.saveBodyWeightEntries([weight])
        XCTAssertEqual(store.loadBodyWeightEntries(), [weight])

        let profile = UserBodyProfile(heightCm: 178, weightKg: 74.2, age: 31, sex: .male, activityLevel: .veryActive)
        try store.saveProfile(profile)
        XCTAssertEqual(store.loadProfile(), profile)

        let goals = PersonalGoals(
            dailySteps: 11_000,
            dailySleepHours: 7.5,
            dailyCalorieTarget: 2_400,
            weeklyWorkoutsTarget: 5,
            targetWeightKg: 72.0,
            dailyHydrationMl: 3_000,
            dailyProteinG: 165,
            dailyCarbsG: 250,
            dailyFatG: 75
        )
        try store.saveGoals(goals)
        XCTAssertEqual(store.loadGoals(), goals)

        var checklist = GoalChecklistStore()
        checklist.addGoal(title: "Hit 100 kg squat", targetDate: now, isComplete: false)
        try store.saveGoalChecklist(checklist)
        XCTAssertEqual(store.loadGoalChecklist(), checklist)

        // Verify no leftover .tmp files exist in store directory.
        let contents = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertFalse(contents.contains { $0.hasSuffix(".tmp") })
    }

    func testExportAndImportBackupRoundTripAndClearAll() throws {
        let sourceStore = LocalStore(directory: tempDirectory.appendingPathComponent("source"))
        let now = Date(timeIntervalSince1970: 1_760_100_000)

        var history = ActivityHistory()
        history.changeGoal(9_500, on: now)
        history.setManualSteps(10_400, on: now, observedAt: now)

        var split = WeeklySplit.defaultSplit
        split.assign(.wednesday, split: .legs, title: "Quad Focus", muscleGroups: [.upperLegs], exerciseIDs: ["0043"])
        try sourceStore.saveWeeklySplit(split)
        try sourceStore.saveMealEntries([MealEntry(date: now, name: "Oats", category: .breakfast, calories: 420, macros: MacroBreakdown(proteinG: 20, carbsG: 65, fatG: 9))])
        try sourceStore.saveSleepEntries([SleepEntry(date: now, bedTime: now.addingTimeInterval(-28_800), wakeTime: now, quality: 5)])
        try sourceStore.saveHydrationEntries([HydrationEntry(date: now, ml: 750)])
        try sourceStore.saveBodyWeightEntries([BodyWeightEntry(date: now, weightKg: 71.5)])

        let exportedData = try sourceStore.exportBackupData(activityHistory: history, dailyStepGoal: 9_500, appVersion: "1.2.3")

        let destinationDir = tempDirectory.appendingPathComponent("dest")
        let destStore = LocalStore(directory: destinationDir)
        let imported = try destStore.importBackupData(exportedData)

        XCTAssertEqual(imported.schemaVersion, AppBackupPayload.currentSchemaVersion)
        XCTAssertEqual(imported.appVersion, "1.2.3")
        XCTAssertEqual(imported.dailyStepGoal, 9_500)
        XCTAssertEqual(imported.activityHistory, history)
        XCTAssertEqual(destStore.loadWeeklySplit(), split)
        XCTAssertEqual(destStore.loadMealEntries().count, 1)
        XCTAssertEqual(destStore.loadSleepEntries().count, 1)
        XCTAssertEqual(destStore.loadHydrationEntries().first?.ml, 750)
        XCTAssertEqual(destStore.loadBodyWeightEntries().first?.weightKg, 71.5)
        XCTAssertEqual(try HistoryStorage.load(from: destStore.historyFileURL), history)

        try destStore.clearAll()
        XCTAssertEqual(destStore.loadWeeklySplit(), .defaultSplit)
        XCTAssertTrue(destStore.loadMealEntries().isEmpty)
        XCTAssertTrue(destStore.loadSleepEntries().isEmpty)
        XCTAssertNil(try HistoryStorage.load(from: destStore.historyFileURL))
    }

    func testImportRejectsCorruptAndUnsupportedBackupVersions() throws {
        let store = LocalStore(directory: tempDirectory)

        XCTAssertThrowsError(try store.importBackupData(Data("not valid json".utf8))) { error in
            XCTAssertEqual(error as? LocalStoreError, .corruptBackupData)
        }

        let badSchemaPayload = AppBackupPayload(
            schemaVersion: 99,
            exportedAt: Date(timeIntervalSince1970: 1_760_000_000),
            appVersion: "1.0.0",
            activityHistory: ActivityHistory(),
            dailyStepGoal: 8_000,
            weeklySplit: .defaultSplit,
            workoutSessions: [],
            workoutTemplates: [],
            sleepEntries: [],
            mealEntries: [],
            hydrationEntries: [],
            bodyWeightEntries: [],
            profile: UserBodyProfile(),
            goals: PersonalGoals(),
            goalChecklist: GoalChecklistStore()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let badSchemaData = try encoder.encode(badSchemaPayload)
        XCTAssertThrowsError(try store.importBackupData(badSchemaData)) { error in
            XCTAssertEqual(error as? LocalStoreError, .unsupportedBackupVersion(99))
        }

        var badHistory = ActivityHistory()
        badHistory.version = 2
        let badHistoryPayload = AppBackupPayload(
            schemaVersion: AppBackupPayload.currentSchemaVersion,
            exportedAt: Date(timeIntervalSince1970: 1_760_000_000),
            appVersion: "1.0.0",
            activityHistory: badHistory,
            dailyStepGoal: 8_000,
            weeklySplit: .defaultSplit,
            workoutSessions: [],
            workoutTemplates: [],
            sleepEntries: [],
            mealEntries: [],
            hydrationEntries: [],
            bodyWeightEntries: [],
            profile: UserBodyProfile(),
            goals: PersonalGoals(),
            goalChecklist: GoalChecklistStore()
        )
        let badHistoryData = try encoder.encode(badHistoryPayload)
        XCTAssertThrowsError(try store.importBackupData(badHistoryData)) { error in
            XCTAssertEqual(error as? LocalStoreError, .unsupportedBackupVersion(2))
        }
    }

    func testImportRollsBackBothExistingAndAbsentFilesOnPartialWriteFailure() throws {
        let seedStore = LocalStore(directory: tempDirectory)
        var initialSplit = WeeklySplit.defaultSplit
        initialSplit.assign(.monday, split: .upper, title: "Original Split", muscleGroups: [.chest, .back], exerciseIDs: ["0025"])
        try seedStore.saveWeeklySplit(initialSplit)

        let initialGoals = PersonalGoals(dailySteps: 9_000, dailyCalorieTarget: 2_100)
        try seedStore.saveGoals(initialGoals)

        // Leave workout-sessions.json and sleep-entries.json absent before the failing import.
        let sessionsURL = tempDirectory.appendingPathComponent("workout-sessions.json")
        let sleepURL = tempDirectory.appendingPathComponent("sleep-entries.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sleepURL.path))

        let backupCreator = LocalStore(directory: tempDirectory.appendingPathComponent("source"))
        let now = Date(timeIntervalSince1970: 1_760_200_000)
        var backupSplit = WeeklySplit.defaultSplit
        backupSplit.assign(.monday, split: .legs, title: "Overwritten Split", muscleGroups: [.upperLegs], exerciseIDs: ["0043"])
        try backupCreator.saveWeeklySplit(backupSplit)
        try backupCreator.saveWorkoutSessions([
            WorkoutSession(date: now, split: .legs, title: "Leg Session", startedAt: now, finishedAt: now.addingTimeInterval(1_200))
        ])
        try backupCreator.saveGoals(PersonalGoals(dailySteps: 14_000, dailyCalorieTarget: 2_800))
        try backupCreator.saveSleepEntries([SleepEntry(date: now, bedTime: now.addingTimeInterval(-25_200), wakeTime: now, quality: 4)])
        let backupData = try backupCreator.exportBackupData(activityHistory: ActivityHistory(), dailyStepGoal: 14_000)

        var attemptedFiles: [String] = []
        let failingStore = LocalStore(directory: tempDirectory) { url, data in
            attemptedFiles.append(url.lastPathComponent)
            if url.lastPathComponent == "personal-goals.json" {
                throw NSError(domain: "BackupTest", code: 500, userInfo: [NSLocalizedDescriptionKey: "Disk full"])
            }
            try data.write(to: url, options: .atomic)
        }

        XCTAssertThrowsError(try failingStore.importBackupData(backupData))
        XCTAssertTrue(attemptedFiles.contains("weekly-split.json"))
        XCTAssertTrue(attemptedFiles.contains("workout-sessions.json"))
        XCTAssertTrue(attemptedFiles.contains("personal-goals.json"))

        // Existing weekly-split.json (overwritten earlier in the sequence) must roll back to original value.
        XCTAssertEqual(seedStore.loadWeeklySplit(), initialSplit)
        // Existing personal-goals.json (where write threw) must remain at original value.
        XCTAssertEqual(seedStore.loadGoals(), initialGoals)
        // Previously absent files written before failure must be rolled back (deleted).
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sleepURL.path))
    }

    func testEmptyBackupRoundTripSucceeds() throws {
        let store = LocalStore(directory: tempDirectory)
        let emptyData = try store.exportBackupData(activityHistory: ActivityHistory(), dailyStepGoal: 8_000)

        let freshStore = LocalStore(directory: tempDirectory.appendingPathComponent("fresh"))
        let restored = try freshStore.importBackupData(emptyData)

        XCTAssertTrue(restored.workoutSessions.isEmpty)
        XCTAssertTrue(restored.mealEntries.isEmpty)
        XCTAssertEqual(restored.profile, UserBodyProfile())
        XCTAssertEqual(restored.dailyStepGoal, 8_000)
    }

    func testCorruptDomainFileFallsBackWithoutCrashingAndRepeatedSavesKeepLatest() throws {
        let store = LocalStore(directory: tempDirectory)
        let splitURL = tempDirectory.appendingPathComponent("weekly-split.json")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Data("{corrupt".utf8).write(to: splitURL)
        XCTAssertEqual(store.loadWeeklySplit(), .defaultSplit)

        for goalValue in stride(from: 6_000, through: 12_000, by: 1_000) {
            try store.saveGoals(PersonalGoals(dailySteps: goalValue))
        }
        XCTAssertEqual(store.loadGoals().dailySteps, 12_000)
    }

    @MainActor
    func testFitnessStoreBackupExportImportAndResetAllData() throws {
        try? HistoryStorage.clear()
        ActivityStorage.clear()
        ActivityStorage.defaults.removeObject(forKey: "dailyGoal")
        UserDefaults.standard.removeObject(forKey: "trackingEnabled")
        UserDefaults.standard.removeObject(forKey: "manualStepFallback")

        let localStore = LocalStore(directory: tempDirectory)
        let activityStore = ActivityStore()
        let fitnessStore = FitnessStore(localStore: localStore, notificationCenter: nil, isFixture: false)
        defer {
            try? fitnessStore.resetAllData(activityStore: activityStore)
        }

        activityStore.setGoal(11_500)
        activityStore.addManualSteps(8_400)
        let stepObservedAt = activityStore.snapshot.updatedAt
        let stepKey = HistoryCalendar.key(for: stepObservedAt)
        fitnessStore.assignDay(.friday, split: .fullBody, title: "Friday Full", muscleGroups: [.chest, .back], exerciseIDs: ["0025"])
        fitnessStore.logSet(exerciseID: "0025", exerciseName: "Bench Press", weightKg: 80, reps: 8, rpe: 8)
        fitnessStore.finishActiveSession()
        fitnessStore.logHydration(ml: 600)
        fitnessStore.logBodyWeight(kg: 73.5)

        let backupData = try fitnessStore.exportBackupData(activityStore: activityStore)

        try fitnessStore.resetAllData(activityStore: activityStore)
        XCTAssertTrue(fitnessStore.sessions.isEmpty)
        XCTAssertTrue(fitnessStore.hydrationEntries.isEmpty)
        XCTAssertTrue(fitnessStore.bodyWeightEntries.isEmpty)
        XCTAssertEqual(activityStore.stepsToday, 0)

        try fitnessStore.importBackupData(backupData, activityStore: activityStore)
        XCTAssertEqual(fitnessStore.sessions.count, 1)
        XCTAssertEqual(fitnessStore.hydrationEntries.first?.ml, 600)
        XCTAssertEqual(fitnessStore.profile.weightKg, 73.5)
        XCTAssertEqual(activityStore.dailyGoal, 11_500)
        XCTAssertEqual(activityStore.history.days[stepKey]?.steps, 8_400)
        XCTAssertEqual(activityStore.snapshot.steps(on: stepObservedAt), 8_400)
        XCTAssertEqual(fitnessStore.weeklySplit.schedule(for: .friday).title, "Friday Full")
    }

    func test365DayBackupRoundTripPerformance() throws {
        let store = LocalStore(directory: tempDirectory)
        let calendar = HistoryCalendar.calendar
        let anchor = HistoryCalendar.date(for: "2026-10-01", calendar: calendar)!

        var history = ActivityHistory()
        var sessions: [WorkoutSession] = []
        var sleepEntries: [SleepEntry] = []
        var mealEntries: [MealEntry] = []

        for offset in 0..<365 {
            let day = calendar.date(byAdding: .day, value: -offset, to: anchor)!
            history.setManualSteps(6_000 + (offset % 5_000), on: day, observedAt: anchor, calendar: calendar)
            sleepEntries.append(SleepEntry(date: day, bedTime: day.addingTimeInterval(-27_000), wakeTime: day, quality: 4))
            mealEntries.append(MealEntry(date: day, name: "Meal \(offset)", category: .lunch, calories: 650, macros: MacroBreakdown(proteinG: 40, carbsG: 70, fatG: 20)))
            if offset % 2 == 0 {
                sessions.append(WorkoutSession(
                    date: day,
                    split: .push,
                    title: "Push \(offset)",
                    startedAt: day,
                    finishedAt: day.addingTimeInterval(1_800),
                    exercises: [
                        ExerciseSessionEntry(
                            exerciseID: "0025",
                            exerciseName: "Bench Press",
                            sets: [ExerciseSetLog(setNumber: 1, weightKg: 70, reps: 8)]
                        )
                    ]
                ))
            }
        }

        try store.saveWorkoutSessions(sessions)
        try store.saveSleepEntries(sleepEntries)
        try store.saveMealEntries(mealEntries)

        let started = Date()
        let exported = try store.exportBackupData(activityHistory: history, dailyStepGoal: 8_000)
        let restoreStore = LocalStore(directory: tempDirectory.appendingPathComponent("perf-restore"))
        let restored = try restoreStore.importBackupData(exported)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(restored.activityHistory.days.count, 365)
        XCTAssertEqual(restored.workoutSessions.count, 183)
        XCTAssertEqual(restored.sleepEntries.count, 365)
        XCTAssertEqual(restored.mealEntries.count, 365)
        XCTAssertLessThan(elapsed, 2.0)
    }
}
