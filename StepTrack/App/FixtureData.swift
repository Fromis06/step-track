import Foundation

#if DEBUG
enum FixtureData {
    static func seed(fitness: FitnessStore, activity: ActivityStore) {
        let now = Date()
        let payload = makeBackupPayload(referenceDate: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        try? fitness.importBackupData(data, activityStore: activity)
    }

    static func makeBackupPayload(referenceDate now: Date = Date()) -> AppBackupPayload {
        let calendar = HistoryCalendar.calendar
        let todayStart = calendar.startOfDay(for: now)
        let currentYear = calendar.component(.year, from: todayStart)
        let janFirst = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1)) ?? todayStart
        let yearAgo = calendar.date(byAdding: .day, value: -364, to: todayStart) ?? todayStart
        let startDate = min(janFirst, yearAgo)

        let totalDays = max(1, (calendar.dateComponents([.day], from: startDate, to: todayStart).day ?? 0) + 1)
        let goalChangeDate = calendar.date(byAdding: .day, value: -60, to: todayStart) ?? todayStart

        // 1. ActivityHistory across full range (ensuring Jan 1 of current year is populated)
        var history = ActivityHistory()
        history.changeGoal(6_000, on: startDate, calendar: calendar)
        if goalChangeDate > startDate {
            history.changeGoal(8_000, on: goalChangeDate, calendar: calendar)
        }

        var stepSamples: [ActivityDay] = []
        stepSamples.reserveCapacity(totalDays)
        for offset in 0..<totalDays {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            let steps: Int
            if offset == totalDays - 1 {
                steps = 6_840
            } else {
                let wave = (offset * 7919 + 104729) % 6_200
                steps = 4_800 + wave
            }
            stepSamples.append(ActivityDay(date: dayDate, steps: steps))
        }
        history.merge(stepSamples, observedAt: now, calendar: calendar)

        // 2. WeeklySplit using verified exercises.json IDs
        let split = WeeklySplit(days: [
            DaySchedule(
                weekday: .monday,
                split: .push,
                title: "Push",
                muscleGroups: [.chest, .shoulders, .upperArms],
                exerciseIDs: ["0025", "0047", "0041", "0030"]
            ),
            DaySchedule(
                weekday: .tuesday,
                split: .pull,
                title: "Pull",
                muscleGroups: [.back, .upperArms],
                exerciseIDs: ["0027", "0007", "0031"]
            ),
            DaySchedule(
                weekday: .wednesday,
                split: .legs,
                title: "Legs",
                muscleGroups: [.upperLegs, .lowerLegs, .waist],
                exerciseIDs: ["0043", "0032", "0001"]
            ),
            DaySchedule(weekday: .thursday, split: .rest),
            DaySchedule(
                weekday: .friday,
                split: .upper,
                title: "Upper",
                muscleGroups: [.chest, .back, .shoulders, .upperArms],
                exerciseIDs: ["0025", "0027", "0041", "0031"]
            ),
            DaySchedule(
                weekday: .saturday,
                split: .lower,
                title: "Lower",
                muscleGroups: [.upperLegs, .waist],
                exerciseIDs: ["0043", "0032", "0001"]
            ),
            DaySchedule(weekday: .sunday, split: .rest)
        ])

        // 3. WorkoutTemplates
        let templates = [
            WorkoutTemplate(
                name: "Push",
                split: .push,
                exerciseIDs: ["0025", "0047", "0041", "0030"],
                defaultSetsPerExercise: 3,
                createdAt: startDate
            ),
            WorkoutTemplate(
                name: "Pull",
                split: .pull,
                exerciseIDs: ["0027", "0007", "0031"],
                defaultSetsPerExercise: 3,
                createdAt: startDate
            ),
            WorkoutTemplate(
                name: "Legs",
                split: .legs,
                exerciseIDs: ["0043", "0032", "0001"],
                defaultSetsPerExercise: 3,
                createdAt: startDate
            )
        ]

        // 4. Progressive 12-month WorkoutSessions & accurate PR flags
        var sessions: [WorkoutSession] = []
        var bestE1RMByExercise: [String: Double] = [:]
        var sessionCounter = 0

        for offset in 0..<(totalDays - 1) {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            let weekday = Weekday.from(date: dayDate, calendar: calendar)
            let schedule = split.schedule(for: weekday)
            guard !schedule.split.isRest, !schedule.exerciseIDs.isEmpty else { continue }

            let progressRatio = Double(offset) / Double(max(1, totalDays - 1))
            let sessionStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: dayDate) ?? dayDate
            let sessionEnd = sessionStart.addingTimeInterval(3_000)

            var exerciseEntries: [ExerciseSessionEntry] = []
            for exID in schedule.exerciseIDs {
                let (name, baseWeight, maxGain) = exerciseSeedMeta(for: exID)
                let rawWeight = baseWeight + maxGain * progressRatio
                let topWeight = (rawWeight * 2.0).rounded() / 2.0
                let warmupWeight = max(10.0, ((topWeight * 0.8) * 2.0).rounded() / 2.0)

                var sets: [ExerciseSetLog] = []
                let repsList = [10, 8, 8]
                let weights = [warmupWeight, topWeight, topWeight]
                for idx in 0..<3 {
                    let w = weights[idx]
                    let r = repsList[idx]
                    let prior = bestE1RMByExercise[exID]
                    let isPR = PersonalRecordDetector.isPersonalRecord(weightKg: w, reps: r, priorBestE1RM: prior)
                    let candidate = ExerciseSetLog.estimated1RM(weightKg: w, reps: r)
                    if candidate > (prior ?? 0) {
                        bestE1RMByExercise[exID] = candidate
                    }
                    sets.append(
                        ExerciseSetLog(
                            setNumber: idx + 1,
                            weightKg: w,
                            reps: r,
                            rpe: idx == 2 ? 8.5 : 7.5,
                            isCompleted: true,
                            isPersonalRecord: isPR,
                            completedAt: sessionStart.addingTimeInterval(TimeInterval((idx + 1) * 300))
                        )
                    )
                }
                exerciseEntries.append(
                    ExerciseSessionEntry(
                        exerciseID: exID,
                        exerciseName: name,
                        sets: sets
                    )
                )
            }

            sessions.append(
                WorkoutSession(
                    date: sessionStart,
                    split: schedule.split,
                    title: schedule.title,
                    startedAt: sessionStart,
                    finishedAt: sessionEnd,
                    exercises: exerciseEntries
                )
            )
            sessionCounter += 1
        }

        // 5. Sleep entries (last 90 days daily + weekly earlier in year)
        var sleepEntries: [SleepEntry] = []
        for offset in 0..<totalDays {
            let daysFromToday = (totalDays - 1) - offset
            guard daysFromToday < 90 || offset % 3 == 0 else { continue }
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            let wakeTime = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: dayDate) ?? dayDate
            let minutesSlept: Int
            if daysFromToday == 0 {
                minutesSlept = 465 // 7h 45m
            } else {
                minutesSlept = 420 + ((offset * 17) % 90)
            }
            let bedTime = wakeTime.addingTimeInterval(TimeInterval(-minutesSlept * 60))
            let quality = daysFromToday == 0 ? 4 : (3 + (offset % 3))
            sleepEntries.append(
                SleepEntry(
                    date: dayDate,
                    bedTime: bedTime,
                    wakeTime: wakeTime,
                    quality: min(5, max(1, quality))
                )
            )
        }

        // 6. Meal entries (14 recent days + weekly historical samples)
        var mealEntries: [MealEntry] = []
        for offset in 0..<totalDays {
            let daysFromToday = (totalDays - 1) - offset
            guard daysFromToday < 14 || offset % 7 == 0 else { continue }
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }

            mealEntries.append(
                MealEntry(
                    date: calendar.date(bySettingHour: 8, minute: 15, second: 0, of: dayDate) ?? dayDate,
                    name: "Oatmeal Berry Bowl",
                    category: .breakfast,
                    calories: 460,
                    macros: MacroBreakdown(proteinG: 24, carbsG: 64, fatG: 11),
                    isFavorite: true
                )
            )
            mealEntries.append(
                MealEntry(
                    date: calendar.date(bySettingHour: 12, minute: 30, second: 0, of: dayDate) ?? dayDate,
                    name: "Chicken Rice Bowl",
                    category: .lunch,
                    calories: 650,
                    macros: MacroBreakdown(proteinG: 48, carbsG: 72, fatG: 16),
                    isFavorite: true
                )
            )
            if daysFromToday == 0 {
                mealEntries.append(
                    MealEntry(
                        date: calendar.date(bySettingHour: 15, minute: 30, second: 0, of: dayDate) ?? dayDate,
                        name: "Greek Yogurt",
                        category: .snack,
                        calories: 210,
                        macros: MacroBreakdown(proteinG: 18, carbsG: 20, fatG: 5),
                        isFavorite: false
                    )
                )
            } else {
                mealEntries.append(
                    MealEntry(
                        date: calendar.date(bySettingHour: 19, minute: 0, second: 0, of: dayDate) ?? dayDate,
                        name: "Salmon Sweet Potato",
                        category: .dinner,
                        calories: 720,
                        macros: MacroBreakdown(proteinG: 46, carbsG: 68, fatG: 24),
                        isFavorite: false
                    )
                )
            }
        }

        // 7. Hydration entries (14 recent days + weekly samples; today = 1,500 ml)
        var hydrationEntries: [HydrationEntry] = []
        for offset in 0..<totalDays {
            let daysFromToday = (totalDays - 1) - offset
            guard daysFromToday < 14 || offset % 7 == 0 else { continue }
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            if daysFromToday == 0 {
                for hour in [9, 12, 15] {
                    let entryDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayDate) ?? dayDate
                    hydrationEntries.append(HydrationEntry(date: entryDate, ml: 500))
                }
            } else {
                let entryDate = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: dayDate) ?? dayDate
                hydrationEntries.append(HydrationEntry(date: entryDate, ml: 2_000 + (offset % 3) * 250))
            }
        }

        // 8. Body weight progression across 12 months (74.5 kg -> 71.2 kg)
        var bodyWeightEntries: [BodyWeightEntry] = []
        for offset in stride(from: 0, to: totalDays, by: 14) {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            let ratio = Double(offset) / Double(max(1, totalDays - 1))
            let weight = ((74.5 - 3.3 * ratio) * 10.0).rounded() / 10.0
            bodyWeightEntries.append(BodyWeightEntry(date: dayDate, weightKg: weight))
        }
        bodyWeightEntries.append(BodyWeightEntry(date: now, weightKg: 71.2))

        // 9. Profile, Goals & Checklist
        let profile = UserBodyProfile(
            heightCm: 175,
            weightKg: 71.2,
            age: 28,
            sex: .male,
            activityLevel: .moderatelyActive
        )

        let goals = PersonalGoals(
            dailySteps: 8_000,
            dailySleepHours: 8.0,
            dailyCalorieTarget: 2_200,
            weeklyWorkoutsTarget: 4,
            targetWeightKg: 70.0,
            dailyHydrationMl: 2_500,
            dailyProteinG: 150,
            dailyCarbsG: 240,
            dailyFatG: 70
        )

        var checklist = GoalChecklistStore()
        checklist.addGoal(title: "Bench press 80 kg", targetDate: now, isComplete: true)
        checklist.addGoal(title: "8 hours sleep", targetDate: now, isComplete: false)
        checklist.addGoal(title: "2,500 ml daily hydration", targetDate: now, isComplete: false)

        return AppBackupPayload(
            exportedAt: now,
            activityHistory: history,
            dailyStepGoal: 8_000,
            weeklySplit: split,
            workoutSessions: sessions,
            workoutTemplates: templates,
            sleepEntries: sleepEntries,
            mealEntries: mealEntries,
            hydrationEntries: hydrationEntries,
            bodyWeightEntries: bodyWeightEntries,
            profile: profile,
            goals: goals,
            goalChecklist: checklist
        )
    }

    private static func exerciseSeedMeta(for exerciseID: String) -> (name: String, baseWeight: Double, maxGain: Double) {
        switch exerciseID {
        case "0025": return ("Barbell bench press", 55.0, 25.0)
        case "0047": return ("Barbell incline bench press", 45.0, 20.0)
        case "0041": return ("Barbell front raise", 15.0, 10.0)
        case "0030": return ("Barbell close-grip bench press", 45.0, 20.0)
        case "0027": return ("Barbell bent over row", 50.0, 25.0)
        case "0007": return ("Alternate lateral pulldown", 45.0, 20.0)
        case "0031": return ("Barbell curl", 22.5, 12.5)
        case "0043": return ("Barbell full squat", 75.0, 40.0)
        case "0032": return ("Barbell deadlift", 90.0, 45.0)
        case "0001": return ("3/4 sit-up", 10.0, 10.0)
        default: return ("Barbell bench press", 50.0, 20.0)
        }
    }
}
#endif
