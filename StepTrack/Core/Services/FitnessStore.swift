import Foundation
import SwiftUI
@preconcurrency import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class FitnessStore: ObservableObject {
    static let restTimerNotificationID = "rest-timer-complete"

    @Published private(set) var weeklySplit: WeeklySplit
    @Published private(set) var sessions: [WorkoutSession]
    @Published private(set) var activeSession: WorkoutSession?
    @Published private(set) var templates: [WorkoutTemplate]
    @Published private(set) var sleepEntries: [SleepEntry]
    @Published private(set) var mealEntries: [MealEntry]
    @Published private(set) var hydrationEntries: [HydrationEntry]
    @Published private(set) var bodyWeightEntries: [BodyWeightEntry]
    @Published private(set) var profile: UserBodyProfile
    @Published private(set) var goals: PersonalGoals
    @Published private(set) var goalChecklist: GoalChecklistStore
    @Published private(set) var persistenceMessage: String?

    @Published private(set) var restRemainingSeconds: Int = 0
    @Published private(set) var restTotalSeconds: Int = 0
    @Published private(set) var isRestTimerRunning: Bool = false

    private let localStore: LocalStore
    private let notificationCenter: (any NotificationScheduling)?
    private let isFixtureMode: Bool
    private var restEndDate: Date?
    private var restTimerTask: Task<Void, Never>?

    init(
        localStore: LocalStore = LocalStore(),
        notificationCenter: (any NotificationScheduling)? = nil,
        isFixture: Bool? = nil
    ) {
        self.localStore = localStore
        self.notificationCenter = notificationCenter
        #if DEBUG
        let runningUITestFixture = isFixture ?? ProcessInfo.processInfo.arguments.contains("--ui-fixture")
        #else
        let runningUITestFixture = isFixture ?? false
        #endif
        self.isFixtureMode = runningUITestFixture

        if runningUITestFixture {
            self.weeklySplit = .defaultSplit
            self.sessions = []
            self.templates = []
            self.sleepEntries = []
            self.mealEntries = []
            self.hydrationEntries = []
            self.bodyWeightEntries = []
            self.profile = UserBodyProfile()
            self.goals = PersonalGoals()
            self.goalChecklist = GoalChecklistStore()
            loadFixtureData()
        } else {
            self.weeklySplit = localStore.loadWeeklySplit()
            self.sessions = localStore.loadWorkoutSessions().sorted { $0.date > $1.date }
            self.templates = localStore.loadWorkoutTemplates().sorted { $0.createdAt > $1.createdAt }
            self.sleepEntries = localStore.loadSleepEntries().sorted { $0.date > $1.date }
            self.mealEntries = localStore.loadMealEntries().sorted { $0.date > $1.date }
            self.hydrationEntries = localStore.loadHydrationEntries().sorted { $0.date > $1.date }
            self.bodyWeightEntries = localStore.loadBodyWeightEntries().sorted { $0.date > $1.date }
            self.profile = localStore.loadProfile()
            self.goals = localStore.loadGoals()
            self.goalChecklist = localStore.loadGoalChecklist()
        }
    }

    deinit {
        restTimerTask?.cancel()
    }

    // MARK: - Weekly Split

    var todayAssignment: DaySchedule {
        weeklySplit.schedule(for: Weekday.from(date: Date()))
    }

    func assignDay(
        _ weekday: Weekday,
        split: SplitType,
        title: String,
        muscleGroups: [BodyPart],
        exerciseIDs: [String]
    ) {
        var updated = weeklySplit
        updated.assign(weekday, split: split, title: title, muscleGroups: muscleGroups, exerciseIDs: exerciseIDs)
        weeklySplit = updated
        persist { try localStore.saveWeeklySplit(updated) }
    }

    // MARK: - Workouts & Weight (kg) Logging

    func startSession(from schedule: DaySchedule? = nil) {
        let now = Date()
        let chosen = schedule ?? todayAssignment
        let library = ExerciseLibraryLoader.shared
        let entries = chosen.exerciseIDs.map { exerciseID in
            let name = library.exercise(id: exerciseID)?.displayName ?? exerciseID
            return ExerciseSessionEntry(exerciseID: exerciseID, exerciseName: name)
        }
        activeSession = WorkoutSession(
            date: now,
            split: chosen.split,
            title: chosen.title,
            startedAt: now,
            finishedAt: nil,
            exercises: entries
        )
    }

    func startSession(from template: WorkoutTemplate, exerciseNames: [String: String] = [:]) {
        let now = Date()
        let library = ExerciseLibraryLoader.shared
        let entries = template.exerciseIDs.map { exerciseID in
            let name = exerciseNames[exerciseID] ?? library.exercise(id: exerciseID)?.displayName ?? exerciseID
            return ExerciseSessionEntry(exerciseID: exerciseID, exerciseName: name)
        }
        activeSession = WorkoutSession(
            date: now,
            split: template.split,
            title: template.name,
            startedAt: now,
            finishedAt: nil,
            exercises: entries
        )
    }

    func logSet(
        exerciseID: String,
        exerciseName: String,
        weightKg: Double,
        reps: Int,
        rpe: Double? = nil
    ) {
        if activeSession == nil {
            startSession(from: DaySchedule(weekday: Weekday.from(date: Date()), split: .custom))
        }
        guard var session = activeSession else { return }

        let priorBest = currentBestE1RM(for: exerciseID, including: session)
        let isPR = PersonalRecordDetector.isPersonalRecord(
            weightKg: weightKg,
            reps: reps,
            priorBestE1RM: priorBest
        )

        if let index = session.exercises.firstIndex(where: { $0.exerciseID == exerciseID }) {
            let nextNumber = session.exercises[index].sets.count + 1
            let setLog = ExerciseSetLog(
                setNumber: nextNumber,
                weightKg: weightKg,
                reps: reps,
                rpe: rpe,
                isCompleted: true,
                isPersonalRecord: isPR,
                completedAt: Date()
            )
            session.exercises[index].sets.append(setLog)
        } else {
            let setLog = ExerciseSetLog(
                setNumber: 1,
                weightKg: weightKg,
                reps: reps,
                rpe: rpe,
                isCompleted: true,
                isPersonalRecord: isPR,
                completedAt: Date()
            )
            session.exercises.append(
                ExerciseSessionEntry(
                    exerciseID: exerciseID,
                    exerciseName: exerciseName,
                    sets: [setLog]
                )
            )
        }

        activeSession = session
    }

    func toggleSetCompletion(exerciseEntryID: UUID, setID: UUID) {
        guard var session = activeSession,
              let exIndex = session.exercises.firstIndex(where: { $0.id == exerciseEntryID }),
              let setIndex = session.exercises[exIndex].sets.firstIndex(where: { $0.id == setID }) else {
            return
        }

        var targetSet = session.exercises[exIndex].sets[setIndex]
        targetSet.isCompleted.toggle()
        targetSet.completedAt = targetSet.isCompleted ? Date() : nil

        if targetSet.isCompleted {
            let exerciseID = session.exercises[exIndex].exerciseID
            var sessionWithoutTarget = session
            sessionWithoutTarget.exercises[exIndex].sets.remove(at: setIndex)
            let priorBest = currentBestE1RM(for: exerciseID, including: sessionWithoutTarget)
            targetSet.isPersonalRecord = PersonalRecordDetector.isPersonalRecord(
                weightKg: targetSet.weightKg,
                reps: targetSet.reps,
                priorBestE1RM: priorBest
            )
        } else {
            targetSet.isPersonalRecord = false
        }

        session.exercises[exIndex].sets[setIndex] = targetSet
        activeSession = session
    }

    func deleteSet(exerciseEntryID: UUID, setID: UUID) {
        guard var session = activeSession,
              let exIndex = session.exercises.firstIndex(where: { $0.id == exerciseEntryID }) else {
            return
        }
        session.exercises[exIndex].sets.removeAll { $0.id == setID }
        for idx in session.exercises[exIndex].sets.indices {
            session.exercises[exIndex].sets[idx].setNumber = idx + 1
        }
        activeSession = session
    }

    func finishActiveSession() {
        guard var session = activeSession else { return }
        session.finishedAt = Date()
        session.exercises = session.exercises.filter { $0.sets.contains(where: \.isCompleted) }
        activeSession = nil
        guard session.completedSetsCount > 0 else { return }
        sessions.insert(session, at: 0)
        sessions.sort { $0.date > $1.date }
        persist { try localStore.saveWorkoutSessions(sessions) }
    }

    func discardActiveSession() {
        activeSession = nil
    }

    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        persist { try localStore.saveWorkoutSessions(sessions) }
    }

    func previousSets(for exerciseID: String) -> [ExerciseSetLog] {
        for session in sessions {
            if let entry = session.exercises.first(where: { $0.exerciseID == exerciseID && !$0.completedSets.isEmpty }) {
                return entry.completedSets
            }
        }
        return []
    }

    func bestE1RM(for exerciseID: String) -> Double? {
        let best = sessions
            .flatMap(\.exercises)
            .filter { $0.exerciseID == exerciseID }
            .map(\.bestE1RM)
            .max() ?? 0
        return best > 0 ? best : nil
    }

    func weightProgression(
        for exerciseID: String,
        timeframe: DashboardTimeframe,
        referenceDate: Date = Date()
    ) -> [WeightProgressPoint] {
        let calendar = HistoryCalendar.calendar
        let range = timeframe.dateRange(endingAt: referenceDate, calendar: calendar)
        let endOfReference = calendar.date(byAdding: .day, value: 1, to: range.end) ?? referenceDate

        return sessions
            .filter { $0.date >= range.start && $0.date < endOfReference }
            .compactMap { session -> WeightProgressPoint? in
                guard let entry = session.exercises.first(where: { $0.exerciseID == exerciseID }),
                      entry.completedSetsCount > 0 else {
                    return nil
                }
                return WeightProgressPoint(
                    id: session.id,
                    date: session.date,
                    maxWeightKg: entry.maxWeightKg,
                    estimated1RM: entry.bestE1RM,
                    totalVolumeKg: entry.totalVolumeKg,
                    isPR: entry.hasPersonalRecord
                )
            }
            .sorted { $0.date < $1.date }
    }

    private func currentBestE1RM(for exerciseID: String, including session: WorkoutSession) -> Double? {
        let historical = bestE1RM(for: exerciseID) ?? 0
        let inSession = session.exercises
            .filter { $0.exerciseID == exerciseID }
            .map(\.bestE1RM)
            .max() ?? 0
        let combined = max(historical, inSession)
        return combined > 0 ? combined : nil
    }

    // MARK: - Workout Templates

    func saveTemplate(
        name: String,
        split: SplitType,
        exerciseIDs: [String],
        defaultSetsPerExercise: Int = 3
    ) {
        let template = WorkoutTemplate(
            name: name,
            split: split,
            exerciseIDs: exerciseIDs,
            defaultSetsPerExercise: defaultSetsPerExercise
        )
        templates.insert(template, at: 0)
        persist { try localStore.saveWorkoutTemplates(templates) }
    }

    func deleteTemplate(id: UUID) {
        templates.removeAll { $0.id == id }
        persist { try localStore.saveWorkoutTemplates(templates) }
    }

    // MARK: - Rest Timer

    func startRestTimer(seconds: Int) {
        let clamped = max(5, min(3_600, seconds))
        restTimerTask?.cancel()
        restTotalSeconds = clamped
        restRemainingSeconds = clamped
        restEndDate = Date().addingTimeInterval(TimeInterval(clamped))
        isRestTimerRunning = true
        scheduleRestNotification(seconds: clamped)
        runRestTimerLoop()
    }

    func adjustRestTimer(delta: Int) {
        guard isRestTimerRunning || restRemainingSeconds > 0 else {
            if delta > 0 { startRestTimer(seconds: delta) }
            return
        }
        let nextRemaining = max(0, min(3_600, restRemainingSeconds + delta))
        if nextRemaining == 0 {
            stopRestTimer()
            return
        }
        restRemainingSeconds = nextRemaining
        restTotalSeconds = max(restTotalSeconds, nextRemaining)
        restEndDate = Date().addingTimeInterval(TimeInterval(nextRemaining))
        if isRestTimerRunning {
            scheduleRestNotification(seconds: nextRemaining)
        }
    }

    func stopRestTimer() {
        restTimerTask?.cancel()
        restTimerTask = nil
        restEndDate = nil
        restRemainingSeconds = 0
        restTotalSeconds = 0
        isRestTimerRunning = false
        cancelRestNotification()
    }

    private func runRestTimerLoop() {
        restTimerTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let endDate = self.restEndDate else { break }
                let remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
                self.restRemainingSeconds = remaining
                if remaining <= 0 {
                    self.completeRestTimer()
                    break
                }
            }
        }
    }

    private func completeRestTimer() {
        restTimerTask = nil
        restEndDate = nil
        restRemainingSeconds = 0
        isRestTimerRunning = false
        cancelRestNotification()
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    private var resolvedNotificationCenter: (any NotificationScheduling)? {
        if let notificationCenter {
            return notificationCenter
        }
        guard Bundle.main.bundleIdentifier != nil else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }

    private func scheduleRestNotification(seconds: Int) {
        guard !isFixtureMode, seconds > 0, let center = resolvedNotificationCenter else { return }
        let content = UNMutableNotificationContent()
        content.title = Copy.text("Rest Timer")
        content.body = Copy.text("Rest complete")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(seconds),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.restTimerNotificationID,
            content: content,
            trigger: trigger
        )
        Task {
            try? await center.add(request)
        }
    }

    private func cancelRestNotification() {
        guard !isFixtureMode, let center = resolvedNotificationCenter else { return }
        center.removePendingNotificationRequests(withIdentifiers: [Self.restTimerNotificationID])
    }

    // MARK: - Health, Nutrition, Hydration, Weight & Goals

    func calorieBalance(on date: Date = Date(), steps: Int) -> CalorieBalance {
        let calendar = HistoryCalendar.calendar
        let dayMeals = mealEntries.filter { calendar.isDate($0.date, inSameDayAs: date) }
        let caloriesIn = dayMeals.reduce(0) { $0 + $1.calories }
        let macros = dayMeals.reduce(MacroBreakdown.zero) { $0 + $1.macros }

        let bmrCalories = Int(profile.bmr.rounded())
        let neatCalories = Int(max(0, profile.tdee - profile.bmr).rounded())
        let stepBurn = ActivityHistory.estimatedCalories(forSteps: steps, bodyWeightKg: profile.weightKg)

        var workoutBurn = sessions
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.estimatedCaloriesBurned(bodyWeightKg: profile.weightKg) }

        if let activeSession,
           calendar.isDate(activeSession.date, inSameDayAs: date),
           activeSession.completedSetsCount > 0 {
            workoutBurn += activeSession.estimatedCaloriesBurned(bodyWeightKg: profile.weightKg)
        }

        return CalorieBalance(
            caloriesIn: caloriesIn,
            bmrCalories: bmrCalories,
            neatCalories: neatCalories,
            stepBurnCalories: stepBurn,
            workoutBurnCalories: workoutBurn,
            targetCalories: goals.dailyCalorieTarget,
            macrosConsumed: macros
        )
    }

    func logSleep(
        date: Date = Date(),
        bedTime: Date,
        wakeTime: Date,
        quality: Int = 3,
        note: String = ""
    ) {
        let entry = SleepEntry(
            date: date,
            bedTime: bedTime,
            wakeTime: wakeTime,
            quality: quality,
            note: note
        )
        sleepEntries.insert(entry, at: 0)
        sleepEntries.sort { $0.date > $1.date }
        persist { try localStore.saveSleepEntries(sleepEntries) }
    }

    func deleteSleep(id: UUID) {
        sleepEntries.removeAll { $0.id == id }
        persist { try localStore.saveSleepEntries(sleepEntries) }
    }

    func logMeal(
        date: Date = Date(),
        name: String,
        category: MealCategory,
        calories: Int,
        macros: MacroBreakdown,
        isFavorite: Bool = false
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = MealEntry(
            date: date,
            name: trimmed,
            category: category,
            calories: calories,
            macros: macros,
            isFavorite: isFavorite
        )
        mealEntries.insert(entry, at: 0)
        mealEntries.sort { $0.date > $1.date }
        persist { try localStore.saveMealEntries(mealEntries) }
    }

    func toggleMealFavorite(id: UUID) {
        guard let index = mealEntries.firstIndex(where: { $0.id == id }) else { return }
        mealEntries[index].isFavorite.toggle()
        persist { try localStore.saveMealEntries(mealEntries) }
    }

    func deleteMeal(id: UUID) {
        mealEntries.removeAll { $0.id == id }
        persist { try localStore.saveMealEntries(mealEntries) }
    }

    func logHydration(ml: Int, on date: Date = Date()) {
        guard ml > 0 else { return }
        let entry = HydrationEntry(date: date, ml: ml)
        hydrationEntries.insert(entry, at: 0)
        hydrationEntries.sort { $0.date > $1.date }
        persist { try localStore.saveHydrationEntries(hydrationEntries) }
    }

    func deleteHydration(id: UUID) {
        hydrationEntries.removeAll { $0.id == id }
        persist { try localStore.saveHydrationEntries(hydrationEntries) }
    }

    func hydrationMl(on date: Date = Date()) -> Int {
        let calendar = HistoryCalendar.calendar
        return hydrationEntries
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.ml }
    }

    func sleepHours(on date: Date = Date()) -> Double {
        let calendar = HistoryCalendar.calendar
        return sleepEntries
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.durationHours }
    }

    func logBodyWeight(kg: Double, on date: Date = Date()) {
        let entry = BodyWeightEntry(date: date, weightKg: kg)
        bodyWeightEntries.insert(entry, at: 0)
        bodyWeightEntries.sort { $0.date > $1.date }
        profile.weightKg = entry.weightKg
        persist {
            try localStore.saveBodyWeightEntries(bodyWeightEntries)
            try localStore.saveProfile(profile)
        }
    }

    func deleteBodyWeight(id: UUID) {
        bodyWeightEntries.removeAll { $0.id == id }
        persist { try localStore.saveBodyWeightEntries(bodyWeightEntries) }
    }

    func updateGoals(_ updated: PersonalGoals) {
        goals = updated
        persist { try localStore.saveGoals(updated) }
    }

    func updateProfile(_ updated: UserBodyProfile) {
        profile = updated
        persist { try localStore.saveProfile(updated) }
    }

    func addChecklistGoal(title: String, targetDate: Date = Date()) {
        goalChecklist.addGoal(title: title, targetDate: targetDate)
        persist { try localStore.saveGoalChecklist(goalChecklist) }
    }

    func toggleChecklistGoal(id: UUID) {
        goalChecklist.toggleCompletion(id: id)
        persist { try localStore.saveGoalChecklist(goalChecklist) }
    }

    func deleteChecklistGoals(at offsets: IndexSet, isComplete: Bool) {
        goalChecklist.deleteGoals(at: offsets, isComplete: isComplete)
        persist { try localStore.saveGoalChecklist(goalChecklist) }
    }

    // MARK: - Analytics Summary (Week / Month / Year)

    func dashboardSummary(
        timeframe: DashboardTimeframe,
        referenceDate: Date = Date(),
        activityHistory: ActivityHistory
    ) -> AnalyticsSummary {
        let calendar = HistoryCalendar.calendar
        let range = timeframe.dateRange(endingAt: referenceDate, calendar: calendar)
        let totalDays = max(1, (calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 0) + 1)

        var stepTrend: [StepTrendPoint] = []
        var strengthTrend: [StrengthTrendPoint] = []
        var sleepTrend: [SleepTrendPoint] = []
        var calorieTrend: [CalorieTrendPoint] = []

        var totalSteps = 0
        var goalDaysCount = 0
        var workoutsCompleted = 0
        var totalVolumeKg = 0.0
        var personalRecordsCount = 0

        var loggedSleepDays = 0
        var totalSleepHours = 0.0
        var sleepTargetDaysHit = 0

        var totalCaloriesIn = 0
        var totalCaloriesOut = 0
        var loggedHydrationDays = 0
        var totalHydrationMl = 0
        var hydrationTargetDaysHit = 0

        for offset in 0..<totalDays {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: range.start) else { continue }
            let dayKey = HistoryCalendar.key(for: dayDate, calendar: calendar)

            // Steps
            let historical = activityHistory.days[dayKey]
            let steps = historical?.steps ?? 0
            let dayGoal = historical?.goal ?? activityHistory.goal(on: dayKey) ?? goals.dailySteps
            let reached = steps >= dayGoal && dayGoal > 0
            totalSteps += steps
            if reached { goalDaysCount += 1 }
            stepTrend.append(StepTrendPoint(id: dayKey, date: dayDate, steps: steps, goal: dayGoal, reachedGoal: reached))

            // Workouts
            let daySessions = sessions.filter { calendar.isDate($0.date, inSameDayAs: dayDate) }
            let dayVolume = daySessions.reduce(0.0) { $0 + $1.totalVolumeKg }
            let dayMaxE1RM = daySessions.flatMap(\.exercises).map(\.bestE1RM).max() ?? 0
            let dayPRs = daySessions.reduce(0) { $0 + $1.personalRecordCount }
            workoutsCompleted += daySessions.count
            totalVolumeKg += dayVolume
            personalRecordsCount += dayPRs
            strengthTrend.append(StrengthTrendPoint(
                id: dayKey,
                date: dayDate,
                totalVolumeKg: dayVolume,
                workoutsCount: daySessions.count,
                maxE1RM: dayMaxE1RM
            ))

            // Sleep
            let daySleep = sleepEntries
                .filter { calendar.isDate($0.date, inSameDayAs: dayDate) }
                .reduce(0.0) { $0 + $1.durationHours }
            if daySleep > 0 {
                loggedSleepDays += 1
                totalSleepHours += daySleep
                if daySleep >= goals.dailySleepHours { sleepTargetDaysHit += 1 }
            }
            sleepTrend.append(SleepTrendPoint(
                id: dayKey,
                date: dayDate,
                hours: daySleep,
                targetHours: goals.dailySleepHours
            ))

            // Calories
            let balance = calorieBalance(on: dayDate, steps: steps)
            totalCaloriesIn += balance.caloriesIn
            totalCaloriesOut += balance.caloriesOut
            calorieTrend.append(CalorieTrendPoint(
                id: dayKey,
                date: dayDate,
                caloriesIn: balance.caloriesIn,
                caloriesOut: balance.caloriesOut
            ))

            // Hydration
            let dayWater = hydrationEntries
                .filter { calendar.isDate($0.date, inSameDayAs: dayDate) }
                .reduce(0) { $0 + $1.ml }
            if dayWater > 0 {
                loggedHydrationDays += 1
                totalHydrationMl += dayWater
                if dayWater >= goals.dailyHydrationMl { hydrationTargetDaysHit += 1 }
            }
        }

        let endOfReference = calendar.date(byAdding: .day, value: 1, to: range.end) ?? referenceDate
        let periodWeights = bodyWeightEntries
            .filter { $0.date >= range.start && $0.date < endOfReference }
            .sorted { $0.date < $1.date }
        let weightTrend = periodWeights.map {
            BodyWeightTrendPoint(id: $0.id.uuidString, date: $0.date, weightKg: $0.weightKg)
        }
        let latestWeightKg = periodWeights.last?.weightKg ?? bodyWeightEntries.first?.weightKg
        let weightDeltaKg: Double? = periodWeights.count >= 2
            ? (periodWeights.last!.weightKg - periodWeights.first!.weightKg)
            : nil

        // Goals completion rate across active goal dimensions
        var completionDimensions: [Double] = []
        completionDimensions.append(Double(goalDaysCount) / Double(totalDays))

        let weeksInPeriod = max(1.0, Double(totalDays) / 7.0)
        let targetWorkouts = max(1.0, Double(goals.weeklyWorkoutsTarget) * weeksInPeriod)
        completionDimensions.append(min(1.0, Double(workoutsCompleted) / targetWorkouts))

        if loggedSleepDays > 0 {
            completionDimensions.append(Double(sleepTargetDaysHit) / Double(loggedSleepDays))
        }
        if loggedHydrationDays > 0 {
            completionDimensions.append(Double(hydrationTargetDaysHit) / Double(loggedHydrationDays))
        }
        let checklistTotal = goalChecklist.items.count
        let checklistCompleted = goalChecklist.completeGoals.count
        if checklistTotal > 0 {
            completionDimensions.append(Double(checklistCompleted) / Double(checklistTotal))
        }
        let goalsCompletionRate = completionDimensions.isEmpty
            ? 0
            : min(1.0, max(0.0, completionDimensions.reduce(0, +) / Double(completionDimensions.count)))

        return AnalyticsSummary(
            timeframe: timeframe,
            totalSteps: totalSteps,
            averageSteps: totalSteps / totalDays,
            goalDaysCount: goalDaysCount,
            totalDaysCount: totalDays,
            workoutsCompleted: workoutsCompleted,
            totalVolumeKg: totalVolumeKg,
            personalRecordsCount: personalRecordsCount,
            averageSleepHours: loggedSleepDays > 0 ? totalSleepHours / Double(loggedSleepDays) : 0,
            averageCaloriesIn: totalCaloriesIn / totalDays,
            averageCaloriesOut: totalCaloriesOut / totalDays,
            averageHydrationMl: loggedHydrationDays > 0 ? totalHydrationMl / loggedHydrationDays : 0,
            latestWeightKg: latestWeightKg,
            weightDeltaKg: weightDeltaKg,
            goalsCompletionRate: goalsCompletionRate,
            checklistCompletedCount: checklistCompleted,
            checklistTotalCount: checklistTotal,
            stepTrend: stepTrend,
            strengthTrend: strengthTrend,
            sleepTrend: sleepTrend,
            calorieTrend: calorieTrend,
            weightTrend: weightTrend
        )
    }

    // MARK: - Backup & Reset

    func exportBackupData(activityStore: ActivityStore) throws -> Data {
        try localStore.exportBackupData(
            activityHistory: activityStore.history,
            dailyStepGoal: activityStore.dailyGoal
        )
    }

    func importBackupData(_ data: Data, activityStore: ActivityStore) throws {
        let payload = try localStore.importBackupData(data)
        weeklySplit = payload.weeklySplit
        sessions = payload.workoutSessions.sorted { $0.date > $1.date }
        templates = payload.workoutTemplates.sorted { $0.createdAt > $1.createdAt }
        sleepEntries = payload.sleepEntries.sorted { $0.date > $1.date }
        mealEntries = payload.mealEntries.sorted { $0.date > $1.date }
        hydrationEntries = payload.hydrationEntries.sorted { $0.date > $1.date }
        bodyWeightEntries = payload.bodyWeightEntries.sorted { $0.date > $1.date }
        profile = payload.profile
        goals = payload.goals
        goalChecklist = payload.goalChecklist
        activeSession = nil
        persistenceMessage = nil
        activityStore.applyRestoredBackup(history: payload.activityHistory, goal: payload.dailyStepGoal)
    }

    func resetAllData(activityStore: ActivityStore) throws {
        stopRestTimer()
        try localStore.clearAll()
        weeklySplit = .defaultSplit
        sessions = []
        activeSession = nil
        templates = []
        sleepEntries = []
        mealEntries = []
        hydrationEntries = []
        bodyWeightEntries = []
        profile = UserBodyProfile()
        goals = PersonalGoals()
        goalChecklist = GoalChecklistStore()
        persistenceMessage = nil
        activityStore.clearSavedData()
    }

    private func persist(_ operation: () throws -> Void) {
        guard !isFixtureMode else { return }
        do {
            try operation()
            persistenceMessage = nil
        } catch {
            persistenceMessage = "Could not save history. Please try again."
        }
    }

    #if DEBUG
    private func loadFixtureData() {
        let now = Date()
        let calendar = HistoryCalendar.calendar
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now

        weeklySplit = .defaultSplit
        sessions = [
            WorkoutSession(
                date: yesterday,
                split: .push,
                title: "Push",
                startedAt: yesterday.addingTimeInterval(-3_600),
                finishedAt: yesterday,
                exercises: [
                    ExerciseSessionEntry(
                        exerciseID: "0025",
                        exerciseName: "Barbell bench press",
                        sets: [
                            ExerciseSetLog(setNumber: 1, weightKg: 60, reps: 10, isCompleted: true, isPersonalRecord: false),
                            ExerciseSetLog(setNumber: 2, weightKg: 70, reps: 8, isCompleted: true, isPersonalRecord: true)
                        ]
                    )
                ]
            )
        ]
        sleepEntries = [
            SleepEntry(
                date: now,
                bedTime: now.addingTimeInterval(-8 * 3_600),
                wakeTime: now,
                quality: 4
            )
        ]
        mealEntries = [
            MealEntry(
                date: now,
                name: "Chicken Rice Bowl",
                category: .lunch,
                calories: 650,
                macros: MacroBreakdown(proteinG: 48, carbsG: 72, fatG: 16),
                isFavorite: true
            )
        ]
        hydrationEntries = [HydrationEntry(date: now, ml: 1_500)]
        bodyWeightEntries = [BodyWeightEntry(date: now, weightKg: 70.0)]
    }
    #endif
}
