import XCTest
@preconcurrency import UserNotifications
@testable import StepTrack

private actor PairwiseNotificationRecorder {
    private(set) var removedIdentifiers: [[String]] = []
    func recordRemove(_ ids: [String]) {
        removedIdentifiers.append(ids)
    }
}

private final class PairwiseMockNotificationCenter: NotificationScheduling, @unchecked Sendable {
    private let recorder = PairwiseNotificationRecorder()

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func add(_ request: UNNotificationRequest) async throws {}
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        Task { await recorder.recordRemove(identifiers) }
    }
    func removeAllPendingNotificationRequests() {}

    func removals() async -> [[String]] {
        await recorder.removedIdentifiers
    }
}

final class PairwiseAndWorkflowTests: XCTestCase {
    private var tempDirectory: URL!
    private var savedLanguage: Any?
    private var savedDailyGoal: Any?
    private var savedSnapshot: Any?
    private var savedTrackingEnabled: Any?
    private var savedManualFallback: Any?
    private let calendar = HistoryCalendar.calendar

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PairwiseAndWorkflowTests-\(UUID().uuidString)")
        savedLanguage = ActivityStorage.defaults.object(forKey: Copy.storageKey)
        savedDailyGoal = ActivityStorage.defaults.object(forKey: "dailyGoal")
        savedSnapshot = ActivityStorage.defaults.object(forKey: "activitySnapshot")
        savedTrackingEnabled = UserDefaults.standard.object(forKey: "trackingEnabled")
        savedManualFallback = UserDefaults.standard.object(forKey: "manualStepFallback")

        try? HistoryStorage.clear()
        ActivityStorage.clear()
        ActivityStorage.defaults.removeObject(forKey: "dailyGoal")
        UserDefaults.standard.removeObject(forKey: "trackingEnabled")
        UserDefaults.standard.removeObject(forKey: "manualStepFallback")
    }

    override func tearDown() {
        try? HistoryStorage.clear()
        restoreDefault(savedLanguage, key: Copy.storageKey, in: ActivityStorage.defaults)
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

    // MARK: - Tier 3 Pairwise Combinations (Logic Level)

    @MainActor
    func testP01ToP03_SplitWorkoutLibraryAndProgression() throws {
        let loader = try ExerciseLibraryLoader(bundle: .main)
        let store = FitnessStore(localStore: LocalStore(directory: tempDirectory), notificationCenter: nil, isFixture: false)

        // P02 (F15 x F13): Find chest exercise and biceps exercise from offline library, assign to split.
        let chestExercise = try XCTUnwrap(loader.exercises(for: BodyRegionID.chest).first)
        let bicepsExercise = try XCTUnwrap(loader.exercises(for: BodyRegionID.biceps).first)

        store.assignDay(.monday, split: .push, title: "Push Day", muscleGroups: [.chest], exerciseIDs: [chestExercise.id])
        XCTAssertEqual(store.weeklySplit.schedule(for: .monday).exerciseIDs, [chestExercise.id])

        // P01 (F13 x F14): Start Monday session -> log 80 kg x 8 -> finish -> start next session -> verify cue & PR.
        store.startSession(from: store.weeklySplit.schedule(for: .monday))
        store.logSet(exerciseID: chestExercise.id, exerciseName: chestExercise.displayName, weightKg: 80, reps: 8, rpe: 8)
        store.finishActiveSession()

        let prev = store.previousSets(for: chestExercise.id)
        XCTAssertEqual(prev.count, 1)
        XCTAssertEqual(prev.first?.weightKg, 80)

        store.startSession(from: store.weeklySplit.schedule(for: .monday))
        store.logSet(exerciseID: chestExercise.id, exerciseName: chestExercise.displayName, weightKg: 85, reps: 8, rpe: 9)
        XCTAssertEqual(store.activeSession?.exercises.first?.sets.first?.isPersonalRecord, true)
        store.finishActiveSession()
        XCTAssertEqual(store.bestE1RM(for: chestExercise.id) ?? 0, ExerciseSetLog.estimated1RM(weightKg: 85, reps: 8), accuracy: 0.001)

        // P03 (F15 x F14): Log biceps exercise from body map and verify weight progression point.
        store.logSet(exerciseID: bicepsExercise.id, exerciseName: bicepsExercise.displayName, weightKg: 30, reps: 10)
        store.finishActiveSession()
        let bicepsProg = store.weightProgression(for: bicepsExercise.id, timeframe: .week)
        XCTAssertEqual(bicepsProg.last?.maxWeightKg, 30)
    }

    @MainActor
    func testP04P05P06P12P14_AnalyticsCalorieBalanceWeightAndGoalHistory() throws {
        let localStore = LocalStore(directory: tempDirectory)
        let ref = HistoryCalendar.date(for: "2026-10-15", calendar: calendar)!
        let d2WeeksAgo = calendar.date(byAdding: .day, value: -14, to: ref)!
        let d2MonthsAgo = calendar.date(byAdding: .day, value: -60, to: ref)!
        let d1YearAgo = calendar.date(byAdding: .day, value: -300, to: ref)!

        try localStore.saveWorkoutSessions([
            WorkoutSession(date: d1YearAgo, split: .legs, title: "Y1", startedAt: d1YearAgo, finishedAt: d1YearAgo.addingTimeInterval(1_800), exercises: [ExerciseSessionEntry(exerciseID: "0043", exerciseName: "Squat", sets: [ExerciseSetLog(setNumber: 1, weightKg: 90, reps: 5)])]),
            WorkoutSession(date: d2MonthsAgo, split: .legs, title: "M1", startedAt: d2MonthsAgo, finishedAt: d2MonthsAgo.addingTimeInterval(1_800), exercises: [ExerciseSessionEntry(exerciseID: "0043", exerciseName: "Squat", sets: [ExerciseSetLog(setNumber: 1, weightKg: 100, reps: 5)])]),
            WorkoutSession(date: d2WeeksAgo, split: .legs, title: "W1", startedAt: d2WeeksAgo, finishedAt: d2WeeksAgo.addingTimeInterval(1_800), exercises: [ExerciseSessionEntry(exerciseID: "0043", exerciseName: "Squat", sets: [ExerciseSetLog(setNumber: 1, weightKg: 110, reps: 5)])])
        ])

        let store = FitnessStore(localStore: localStore, notificationCenter: nil, isFixture: false)

        // P04 (F14 x F17): Month vs Year weight progression counts.
        XCTAssertEqual(store.weightProgression(for: "0043", timeframe: .month, referenceDate: ref).map(\.maxWeightKg), [110])
        XCTAssertEqual(store.weightProgression(for: "0043", timeframe: .year, referenceDate: ref).map(\.maxWeightKg), [90, 100, 110])

        // P05 (F12 x F16) & P12 (F16 x F12): Steps + workout + meals + weight change updating BMR.
        store.updateProfile(UserBodyProfile(heightCm: 175, weightKg: 80, age: 30, sex: .male, activityLevel: .moderatelyActive))
        store.logMeal(date: ref, name: "Balanced Day", category: .dinner, calories: 2_100, macros: MacroBreakdown(proteinG: 150, carbsG: 200, fatG: 70))
        let balanceAt80Kg = store.calorieBalance(on: ref, steps: 10_000)

        store.logBodyWeight(kg: 72, on: ref)
        let balanceAt72Kg = store.calorieBalance(on: ref, steps: 10_000)
        XCTAssertGreaterThan(balanceAt80Kg.bmrCalories, balanceAt72Kg.bmrCalories)
        XCTAssertGreaterThan(balanceAt80Kg.stepBurnCalories, balanceAt72Kg.stepBurnCalories)
        XCTAssertEqual(balanceAt72Kg.caloriesIn, 2_100)

        // P06 (F16 x F17) & P14 (F12 x F17): 7-day sleep/meals & goal change preserving past days.
        var history = ActivityHistory()
        let pastDay = calendar.date(byAdding: .day, value: -3, to: ref)!
        history.changeGoal(8_000, on: pastDay, calendar: calendar)
        history.setManualSteps(8_500, on: pastDay, observedAt: ref, calendar: calendar)
        history.changeGoal(12_000, on: ref, calendar: calendar)
        history.setManualSteps(9_000, on: ref, observedAt: ref, calendar: calendar)

        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: -offset, to: ref)!
            store.logSleep(date: day, bedTime: day.addingTimeInterval(-28_800), wakeTime: day, quality: 4)
        }
        let weekSummary = store.dashboardSummary(timeframe: .week, referenceDate: ref, activityHistory: history)
        XCTAssertEqual(weekSummary.averageSleepHours, 8.0, accuracy: 0.01)
        let pastTrend = weekSummary.stepTrend.first { $0.id == HistoryCalendar.key(for: pastDay, calendar: calendar) }
        let todayTrend = weekSummary.stepTrend.first { $0.id == HistoryCalendar.key(for: ref, calendar: calendar) }
        XCTAssertEqual(pastTrend?.goal, 8_000)
        XCTAssertEqual(pastTrend?.reachedGoal, true)
        XCTAssertEqual(todayTrend?.goal, 12_000)
        XCTAssertEqual(todayTrend?.reachedGoal, false)
    }

    @MainActor
    func testP07P08P09P10P11P13P15_SideloadBackupL10nThemeTimerAndMeshParity() async throws {
        // P07 (F12 x F8): Sideload manual fallback + ActivityHistory + summary.
        let activityStore = ActivityStore()
        let fitnessStore = FitnessStore(localStore: LocalStore(directory: tempDirectory), notificationCenter: PairwiseMockNotificationCenter(), isFixture: false)
        defer {
            try? fitnessStore.resetAllData(activityStore: activityStore)
        }

        await activityStore.connect()
        activityStore.addManualSteps(6_500)
        XCTAssertEqual(activityStore.stepsToday, 6_500)
        XCTAssertEqual(activityStore.snapshot.steps(), 6_500)

        // P08 (F7 x F13 x F14 x F16): Full backup roundtrip across all domains.
        fitnessStore.assignDay(.tuesday, split: .pull, title: "Pull Backup", muscleGroups: [.back], exerciseIDs: ["0027"])
        fitnessStore.logSet(exerciseID: "0027", exerciseName: "Row", weightKg: 70, reps: 8)
        fitnessStore.finishActiveSession()
        fitnessStore.logSleep(bedTime: Date().addingTimeInterval(-25_200), wakeTime: Date(), quality: 4)
        fitnessStore.logMeal(name: "Bowl", category: .lunch, calories: 700, macros: MacroBreakdown(proteinG: 45, carbsG: 80, fatG: 20))
        fitnessStore.logHydration(ml: 500)
        fitnessStore.logBodyWeight(kg: 76)
        let exported = try fitnessStore.exportBackupData(activityStore: activityStore)
        try fitnessStore.resetAllData(activityStore: activityStore)
        try fitnessStore.importBackupData(exported, activityStore: activityStore)
        XCTAssertEqual(activityStore.stepsToday, 6_500)
        XCTAssertEqual(fitnessStore.sessions.count, 1)
        XCTAssertEqual(fitnessStore.sleepEntries.count, 1)
        XCTAssertEqual(fitnessStore.mealEntries.count, 1)
        XCTAssertEqual(fitnessStore.hydrationEntries.first?.ml, 500)
        XCTAssertEqual(fitnessStore.profile.weightKg, 76)

        // P09 & P10 (F9 x F10 x F11): Themes x Appearances x Languages x SvgIconView.
        let suite = "PairwiseTheme-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let themeManager = ThemeManager(defaults: defaults)
        for theme in AppTheme.allCases {
            themeManager.theme = theme
            for appearance in [AppAppearance.light, .dark] {
                themeManager.appearance = appearance
                let scheme = appearance.colorScheme ?? .light
                let palette = themeManager.palette(for: scheme)
                XCTAssertNotEqual(palette.accent, palette.bgCanvas)
                _ = SvgIconView(icon: .footprints, size: 20, color: palette.accent)
            }
        }

        // P11 (F10 x F15): Localized UI chrome in vi/ja with English exercise instruction fallback.
        let loader = try ExerciseLibraryLoader(bundle: .main)
        let firstExercise = try XCTUnwrap(loader.exercises.first)
        for lang in [AppLanguage.vi, .ja] {
            ActivityStorage.defaults.set(lang.rawValue, forKey: Copy.storageKey)
            XCTAssertNotEqual(Copy.text("Body"), "Body")
            XCTAssertFalse(firstExercise.sanitizedInstructionSteps.isEmpty)
        }

        // P13 (F14 x F18): Rest timer start/adjust/stop.
        fitnessStore.startRestTimer(seconds: 90)
        fitnessStore.adjustRestTimer(delta: 15)
        XCTAssertEqual(fitnessStore.restRemainingSeconds, 105)
        fitnessStore.stopRestTimer()
        XCTAssertFalse(fitnessStore.isRestTimerRunning)

        // P15 (F3 x F5): All 10 BodyPart categories reachable from BodyRegionID.
        let reachableBodyParts = Set(BodyRegionID.allCases.map(\.bodyPart))
        XCTAssertEqual(reachableBodyParts, Set(BodyPart.allCases))
        for region in BodyRegionID.allCases {
            XCTAssertFalse(loader.exercises(for: region).isEmpty)
        }
    }

    // MARK: - Tier 4 Real-World Logic Workloads

    @MainActor
    func testTier4_Workloads_OnboardingPPLCutBackupTransformationAndFavorites() async throws {
        let loader = try ExerciseLibraryLoader(bundle: .main)
        let activityStore = ActivityStore()
        let store = FitnessStore(localStore: LocalStore(directory: tempDirectory), notificationCenter: nil, isFixture: false)
        defer {
            try? store.resetAllData(activityStore: activityStore)
        }

        // Scenario 1: First-launch sideloaded onboarding.
        await activityStore.connect()
        store.updateProfile(UserBodyProfile(heightCm: 176, weightKg: 78, age: 29, sex: .male, activityLevel: .moderatelyActive))
        store.updateGoals(PersonalGoals(dailySteps: 10_000, dailySleepHours: 8, dailyCalorieTarget: 2_100, weeklyWorkoutsTarget: 4, targetWeightKg: 74, dailyHydrationMl: 2_500))
        activityStore.addManualSteps(9_500)
        XCTAssertGreaterThan(store.calorieBalance(steps: activityStore.stepsToday).caloriesOut, 2_000)

        // Scenario 2 & 3: Offline body discovery -> Push/Pull/Legs/Upper setup -> progressive overload PR.
        let bench = try XCTUnwrap(loader.search(query: "bench press", region: .chest, equipment: .barbell).first)
        let row = try XCTUnwrap(loader.search(query: "row", region: .backUpper, equipment: .dumbbell).first)
        let cardio = try XCTUnwrap(loader.exercises(for: BodyRegionID.cardio).first)

        store.assignDay(.monday, split: .push, title: "Push", muscleGroups: [.chest], exerciseIDs: [bench.id])
        store.assignDay(.tuesday, split: .pull, title: "Pull", muscleGroups: [.back], exerciseIDs: [row.id])
        store.assignDay(.wednesday, split: .cardio, title: "Conditioning", muscleGroups: [.cardio], exerciseIDs: [cardio.id])

        store.startSession(from: store.weeklySplit.schedule(for: .monday))
        store.logSet(exerciseID: bench.id, exerciseName: bench.displayName, weightKg: 80, reps: 6)
        store.finishActiveSession()
        store.startSession(from: store.weeklySplit.schedule(for: .monday))
        store.logSet(exerciseID: bench.id, exerciseName: bench.displayName, weightKg: 85, reps: 6)
        XCTAssertEqual(store.activeSession?.exercises.first?.sets.first?.isPersonalRecord, true)
        store.finishActiveSession()

        // Scenario 4 & 9: Fat-loss cut day + meal favorites re-log.
        let today = calendar.startOfDay(for: Date())
        store.logSleep(date: today, bedTime: today.addingTimeInterval(-27_000), wakeTime: today, quality: 4)
        store.logMeal(date: today, name: "Protein Oats", category: .breakfast, calories: 450, macros: MacroBreakdown(proteinG: 35, carbsG: 55, fatG: 10), isFavorite: true)
        store.logMeal(date: today, name: "Chicken Salad", category: .lunch, calories: 600, macros: MacroBreakdown(proteinG: 55, carbsG: 40, fatG: 20))
        store.logMeal(date: today, name: "Salmon Bowl", category: .dinner, calories: 700, macros: MacroBreakdown(proteinG: 50, carbsG: 65, fatG: 24))
        store.logMeal(date: today, name: "Greek Yogurt", category: .snack, calories: 200, macros: MacroBreakdown(proteinG: 20, carbsG: 15, fatG: 5))
        store.logHydration(ml: 500, on: today)
        store.logHydration(ml: 500, on: today)

        let cutBalance = store.calorieBalance(on: today, steps: activityStore.stepsToday)
        XCTAssertEqual(cutBalance.caloriesIn, 1_950)
        XCTAssertLessThan(cutBalance.netBalance, 0)
        XCTAssertEqual(store.hydrationMl(on: today), 1_000)

        // Scenario 5: 7-day re-sign backup export -> wipe -> import.
        let backup = try store.exportBackupData(activityStore: activityStore)
        try store.resetAllData(activityStore: activityStore)
        try store.importBackupData(backup, activityStore: activityStore)
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.mealEntries.filter(\.isFavorite).count, 1)
        XCTAssertEqual(activityStore.stepsToday, 9_500)

        // Scenario 6 & 8: Multi-timeframe summary & goal revision preserving past days.
        let past = calendar.date(byAdding: .day, value: -2, to: today)!
        var history = activityStore.history
        history.changeGoal(8_000, on: past, calendar: calendar)
        history.setManualSteps(8_500, on: past, observedAt: today, calendar: calendar)
        history.changeGoal(12_000, on: today, calendar: calendar)

        let weekSummary = store.dashboardSummary(timeframe: .week, referenceDate: today, activityHistory: history)
        let monthSummary = store.dashboardSummary(timeframe: .month, referenceDate: today, activityHistory: history)
        let yearSummary = store.dashboardSummary(timeframe: .year, referenceDate: today, activityHistory: history)

        XCTAssertEqual(weekSummary.workoutsCompleted, 2)
        XCTAssertEqual(monthSummary.workoutsCompleted, 2)
        XCTAssertEqual(yearSummary.workoutsCompleted, 2)
        XCTAssertEqual(history.days[HistoryCalendar.key(for: past, calendar: calendar)]?.reachedGoal, true)
    }
}
