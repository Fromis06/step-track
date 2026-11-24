import XCTest
@testable import StepTrack

final class AnalyticsDashboardTests: XCTestCase {
    private var tempDirectory: URL!
    private let calendar = HistoryCalendar.calendar

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsDashboardTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func date(_ key: String) -> Date {
        HistoryCalendar.date(for: key, calendar: calendar)!
    }

    func testDashboardTimeframeDayCountAndDateRangeLeapVsNonLeap() {
        let feb2024 = date("2024-02-15")
        let feb2025 = date("2025-02-15")

        XCTAssertEqual(DashboardTimeframe.week.dayCount(for: feb2024, calendar: calendar), 7)
        XCTAssertEqual(DashboardTimeframe.month.dayCount(for: feb2024, calendar: calendar), 29)
        XCTAssertEqual(DashboardTimeframe.month.dayCount(for: feb2025, calendar: calendar), 28)
        XCTAssertEqual(DashboardTimeframe.year.dayCount(for: feb2024, calendar: calendar), 366)
        XCTAssertEqual(DashboardTimeframe.year.dayCount(for: feb2025, calendar: calendar), 365)

        let ref = date("2026-10-15")
        let weekRange = DashboardTimeframe.week.dateRange(endingAt: ref, calendar: calendar)
        XCTAssertEqual(HistoryCalendar.key(for: weekRange.start, calendar: calendar), "2026-10-09")
        XCTAssertEqual(HistoryCalendar.key(for: weekRange.end, calendar: calendar), "2026-10-15")

        let monthRange = DashboardTimeframe.month.dateRange(endingAt: ref, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.day], from: monthRange.start, to: monthRange.end).day, 29)

        let yearRange = DashboardTimeframe.year.dateRange(endingAt: ref, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.day], from: yearRange.start, to: yearRange.end).day, 364)
    }

    @MainActor
    func testEmptyHistorySummaryHasZeroCountsAndFiniteRatesAcrossAllTimeframes() {
        let store = FitnessStore(localStore: LocalStore(directory: tempDirectory), notificationCenter: nil, isFixture: false)
        let ref = date("2026-10-15")
        let emptyHistory = ActivityHistory()

        for timeframe in DashboardTimeframe.allCases {
            let summary = store.dashboardSummary(timeframe: timeframe, referenceDate: ref, activityHistory: emptyHistory)
            XCTAssertEqual(summary.timeframe, timeframe)
            XCTAssertEqual(summary.totalSteps, 0)
            XCTAssertEqual(summary.averageSteps, 0)
            XCTAssertEqual(summary.workoutsCompleted, 0)
            XCTAssertEqual(summary.totalVolumeKg, 0)
            XCTAssertEqual(summary.personalRecordsCount, 0)
            XCTAssertEqual(summary.averageSleepHours, 0)
            XCTAssertEqual(summary.averageCaloriesIn, 0)
            XCTAssertGreaterThan(summary.averageCaloriesOut, 0)
            XCTAssertEqual(summary.averageHydrationMl, 0)
            XCTAssertNil(summary.latestWeightKg)
            XCTAssertNil(summary.weightDeltaKg)
            XCTAssertEqual(summary.goalsCompletionRate, 0)
        }
    }

    @MainActor
    func testDashboardSummaryAggregatesWeekMonthYearAndWeightProgression() throws {
        let localStore = LocalStore(directory: tempDirectory)
        let ref = date("2026-10-15")
        let d1 = date("2026-10-10")
        let d2 = date("2026-10-14")
        let oldDate = date("2026-01-15")

        let s1 = WorkoutSession(
            date: oldDate,
            split: .push,
            title: "January Push",
            startedAt: oldDate,
            finishedAt: oldDate.addingTimeInterval(2_400),
            exercises: [
                ExerciseSessionEntry(
                    exerciseID: "0025",
                    exerciseName: "Barbell Bench Press",
                    sets: [ExerciseSetLog(setNumber: 1, weightKg: 70, reps: 8, isCompleted: true, isPersonalRecord: true)]
                )
            ]
        )
        let s2 = WorkoutSession(
            date: d1,
            split: .push,
            title: "October Push 1",
            startedAt: d1,
            finishedAt: d1.addingTimeInterval(2_400),
            exercises: [
                ExerciseSessionEntry(
                    exerciseID: "0025",
                    exerciseName: "Barbell Bench Press",
                    sets: [ExerciseSetLog(setNumber: 1, weightKg: 80, reps: 8, isCompleted: true, isPersonalRecord: true)]
                )
            ]
        )
        let s3 = WorkoutSession(
            date: d2,
            split: .push,
            title: "October Push 2",
            startedAt: d2,
            finishedAt: d2.addingTimeInterval(2_400),
            exercises: [
                ExerciseSessionEntry(
                    exerciseID: "0025",
                    exerciseName: "Barbell Bench Press",
                    sets: [ExerciseSetLog(setNumber: 1, weightKg: 85, reps: 8, isCompleted: true, isPersonalRecord: true)]
                )
            ]
        )
        try localStore.saveWorkoutSessions([s1, s2, s3])

        let store = FitnessStore(localStore: localStore, notificationCenter: nil, isFixture: false)
        store.updateGoals(PersonalGoals(dailySteps: 8_000, dailySleepHours: 7.5, weeklyWorkoutsTarget: 2, dailyHydrationMl: 2_000))

        store.logSleep(date: d1, bedTime: d1.addingTimeInterval(-28_800), wakeTime: d1, quality: 4)
        store.logSleep(date: d2, bedTime: d2.addingTimeInterval(-25_200), wakeTime: d2, quality: 4)
        store.logMeal(date: d1, name: "Meal 1", category: .lunch, calories: 1_400, macros: MacroBreakdown(proteinG: 80, carbsG: 140, fatG: 45))
        store.logHydration(ml: 2_200, on: d1)
        store.logBodyWeight(kg: 80.0, on: d1)
        store.logBodyWeight(kg: 78.5, on: d2)
        store.addChecklistGoal(title: "Goal A", targetDate: ref)
        if let firstGoalID = store.goalChecklist.items.first?.id {
            store.toggleChecklistGoal(id: firstGoalID)
        }

        var history = ActivityHistory()
        history.changeGoal(8_000, on: d1, calendar: calendar)
        history.setManualSteps(10_000, on: d1, observedAt: ref, calendar: calendar)
        history.setManualSteps(4_000, on: d2, observedAt: ref, calendar: calendar)

        // Week summary excludes January session.
        let weekSummary = store.dashboardSummary(timeframe: .week, referenceDate: ref, activityHistory: history)
        XCTAssertEqual(weekSummary.totalDaysCount, 7)
        XCTAssertEqual(weekSummary.totalSteps, 14_000)
        XCTAssertEqual(weekSummary.averageSteps, 2_000)
        XCTAssertEqual(weekSummary.goalDaysCount, 1)
        XCTAssertEqual(weekSummary.workoutsCompleted, 2)
        XCTAssertEqual(weekSummary.totalVolumeKg, 80 * 8 + 85 * 8, accuracy: 0.001)
        XCTAssertEqual(weekSummary.personalRecordsCount, 2)
        XCTAssertEqual(weekSummary.averageSleepHours, 7.5, accuracy: 0.01)
        XCTAssertEqual(weekSummary.averageCaloriesIn, 200)
        XCTAssertEqual(weekSummary.averageHydrationMl, 2_200)
        XCTAssertEqual(weekSummary.latestWeightKg ?? 0, 78.5, accuracy: 0.001)
        XCTAssertEqual(weekSummary.weightDeltaKg ?? 0, -1.5, accuracy: 0.001)
        XCTAssertGreaterThan(weekSummary.goalsCompletionRate, 0)
        XCTAssertLessThanOrEqual(weekSummary.goalsCompletionRate, 1.0)
        XCTAssertEqual(weekSummary.checklistCompletedCount, 1)
        XCTAssertEqual(weekSummary.checklistTotalCount, 1)

        let monthSummary = store.dashboardSummary(timeframe: .month, referenceDate: ref, activityHistory: history)
        XCTAssertEqual(monthSummary.totalDaysCount, 30)
        XCTAssertEqual(monthSummary.workoutsCompleted, 2)

        // Year summary includes January session.
        let yearSummary = store.dashboardSummary(timeframe: .year, referenceDate: ref, activityHistory: history)
        XCTAssertEqual(yearSummary.totalDaysCount, 365)
        XCTAssertEqual(yearSummary.workoutsCompleted, 3)

        // Weight progression ordering across timeframes.
        let weekProg = store.weightProgression(for: "0025", timeframe: .week, referenceDate: ref)
        XCTAssertEqual(weekProg.map(\.maxWeightKg), [80, 85])

        let yearProg = store.weightProgression(for: "0025", timeframe: .year, referenceDate: ref)
        XCTAssertEqual(yearProg.map(\.maxWeightKg), [70, 80, 85])
    }

    @MainActor
    func testYearBoundaryDec29ToJan4AndSparseHistory() throws {
        let localStore = LocalStore(directory: tempDirectory)
        let janEarly = date("2025-01-01")
        let decLate = date("2025-12-30")
        let janNext = date("2026-01-04")

        try localStore.saveWorkoutSessions([
            WorkoutSession(
                date: janEarly,
                split: .upper,
                title: "Jan 1",
                startedAt: janEarly,
                finishedAt: janEarly.addingTimeInterval(1_200),
                exercises: [ExerciseSessionEntry(exerciseID: "0025", exerciseName: "Bench", sets: [ExerciseSetLog(setNumber: 1, weightKg: 60, reps: 8)])]
            ),
            WorkoutSession(
                date: decLate,
                split: .upper,
                title: "Dec 30",
                startedAt: decLate,
                finishedAt: decLate.addingTimeInterval(1_200),
                exercises: [ExerciseSessionEntry(exerciseID: "0025", exerciseName: "Bench", sets: [ExerciseSetLog(setNumber: 1, weightKg: 75, reps: 8)])]
            )
        ])

        let store = FitnessStore(localStore: localStore, notificationCenter: nil, isFixture: false)
        var history = ActivityHistory()
        history.setManualSteps(5_000, on: date("2025-12-29"), observedAt: janNext, calendar: calendar)
        history.setManualSteps(7_000, on: janNext, observedAt: janNext, calendar: calendar)

        // Week crossing Dec 29, 2025 .. Jan 4, 2026 must contain all 7 days without dropping year transition.
        let boundaryWeek = store.dashboardSummary(timeframe: .week, referenceDate: janNext, activityHistory: history)
        XCTAssertEqual(boundaryWeek.stepTrend.count, 7)
        XCTAssertEqual(boundaryWeek.stepTrend.first?.id, "2025-12-29")
        XCTAssertEqual(boundaryWeek.stepTrend.last?.id, "2026-01-04")
        XCTAssertEqual(boundaryWeek.totalSteps, 12_000)
        XCTAssertEqual(boundaryWeek.workoutsCompleted, 1)

        // Sparse year summary ending Dec 31, 2025 captures both Jan 1 and Dec 30 sessions.
        let sparseYear = store.dashboardSummary(timeframe: .year, referenceDate: date("2025-12-31"), activityHistory: history)
        XCTAssertEqual(sparseYear.workoutsCompleted, 2)
    }
}
