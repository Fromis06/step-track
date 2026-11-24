import XCTest
@testable import StepTrack

final class HealthAndGoalsTests: XCTestCase {
    private var tempDirectory: URL!

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        value.firstWeekday = 2
        return value
    }

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthAndGoalsTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testSleepEntryMidnightWrapAndQualityClamping() {
        let bed = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 23, minute: 15))!
        // Wake time represented on same nominal date as bedTime (06:45) wraps forward +1 day.
        let nominalWake = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 6, minute: 45))!

        let normalized = SleepEntry.normalizedWakeTime(bedTime: bed, wakeTime: nominalWake)
        XCTAssertGreaterThan(normalized, bed)

        let entryLow = SleepEntry(date: bed, bedTime: bed, wakeTime: nominalWake, quality: 0, note: "  good ")
        XCTAssertEqual(entryLow.durationMinutes, 450)
        XCTAssertEqual(entryLow.durationHours, 7.5, accuracy: 0.001)
        XCTAssertEqual(entryLow.quality, 1)
        XCTAssertEqual(entryLow.note, "good")

        let entryHigh = SleepEntry(date: bed, bedTime: bed, wakeTime: nominalWake, quality: 99)
        XCTAssertEqual(entryHigh.quality, 5)
    }

    func testMealEntryMacrosHydrationAndBodyWeightClamping() {
        let negativeMacros = MacroBreakdown(proteinG: -10, carbsG: 30, fatG: 10)
        XCTAssertEqual(negativeMacros.proteinG, 0)
        XCTAssertEqual(negativeMacros.macroCalories, 30 * 4 + 10 * 9, accuracy: 0.001)

        let combined = MacroBreakdown(proteinG: 20, carbsG: 40, fatG: 5) + MacroBreakdown(proteinG: 10, carbsG: 10, fatG: 5)
        XCTAssertEqual(combined.proteinG, 30)
        XCTAssertEqual(combined.carbsG, 50)
        XCTAssertEqual(combined.fatG, 10)

        let meal = MealEntry(name: "  Chicken Bowl ", category: .lunch, calories: -200, macros: combined)
        XCTAssertEqual(meal.name, "Chicken Bowl")
        XCTAssertEqual(meal.calories, 0)

        let hydration = HydrationEntry(ml: -100)
        XCTAssertEqual(hydration.ml, 0)

        let tooLight = BodyWeightEntry(weightKg: 5)
        let tooHeavy = BodyWeightEntry(weightKg: 800)
        XCTAssertEqual(tooLight.weightKg, 20.0)
        XCTAssertEqual(tooHeavy.weightKg, 400.0)
    }

    func testUserBodyProfileMifflinStJeorAndPersonalGoalsClamping() {
        let male = UserBodyProfile(heightCm: 180, weightKg: 80, age: 30, sex: .male, activityLevel: .moderatelyActive)
        // 10*80 + 6.25*180 - 5*30 + 5 = 800 + 1125 - 150 + 5 = 1780
        XCTAssertEqual(male.bmr, 1_780, accuracy: 0.001)
        XCTAssertEqual(male.tdee, 1_780 * 1.55, accuracy: 0.001)

        let female = UserBodyProfile(heightCm: 165, weightKg: 60, age: 25, sex: .female, activityLevel: .sedentary)
        // 10*60 + 6.25*165 - 5*25 - 161 = 600 + 1031.25 - 125 - 161 = 1345.25
        XCTAssertEqual(female.bmr, 1_345.25, accuracy: 0.001)
        XCTAssertEqual(female.tdee, 1_345.25 * 1.2, accuracy: 0.001)

        let other = UserBodyProfile(heightCm: 170, weightKg: 70, age: 30, sex: .other, activityLevel: .athlete)
        // 10*70 + 6.25*170 - 5*30 - 78 = 700 + 1062.5 - 150 - 78 = 1534.5
        XCTAssertEqual(other.bmr, 1_534.5, accuracy: 0.001)
        XCTAssertEqual(other.tdee, 1_534.5 * 1.9, accuracy: 0.001)

        // Minimum BMR floor is 800.
        let extremeLow = UserBodyProfile(heightCm: 50, weightKg: 10, age: 150, sex: .female, activityLevel: .lightlyActive)
        XCTAssertEqual(extremeLow.heightCm, 100)
        XCTAssertEqual(extremeLow.weightKg, 20)
        XCTAssertEqual(extremeLow.age, 120)
        XCTAssertEqual(extremeLow.bmr, 800.0)

        for level in ActivityLevel.allCases {
            let p = UserBodyProfile(heightCm: 170, weightKg: 70, age: 28, sex: .male, activityLevel: level)
            XCTAssertEqual(p.tdee, p.bmr * level.multiplier, accuracy: 0.001)
        }

        let clampedGoals = PersonalGoals(
            dailySteps: 10,
            dailySleepHours: 1,
            dailyCalorieTarget: 100,
            weeklyWorkoutsTarget: 0,
            targetWeightKg: 500,
            dailyHydrationMl: 100,
            dailyProteinG: 1,
            dailyCarbsG: 5_000,
            dailyFatG: 1
        )
        XCTAssertEqual(clampedGoals.dailySteps, 500)
        XCTAssertEqual(clampedGoals.dailySleepHours, 3.0)
        XCTAssertEqual(clampedGoals.dailyCalorieTarget, 800)
        XCTAssertEqual(clampedGoals.weeklyWorkoutsTarget, 1)
        XCTAssertEqual(clampedGoals.targetWeightKg, 400.0)
        XCTAssertEqual(clampedGoals.dailyHydrationMl, 500)
        XCTAssertEqual(clampedGoals.dailyProteinG, 20)
        XCTAssertEqual(clampedGoals.dailyCarbsG, 1_000)
        XCTAssertEqual(clampedGoals.dailyFatG, 10)
    }

    @MainActor
    func testFitnessStoreHealthLoggingAndCalorieBalanceCalculation() {
        let store = FitnessStore(localStore: LocalStore(directory: tempDirectory), notificationCenter: nil, isFixture: false)
        let today = HistoryCalendar.calendar.startOfDay(for: Date())
        let yesterday = HistoryCalendar.calendar.date(byAdding: .day, value: -1, to: today)!

        // Guards against empty meal names and non-positive hydration.
        store.logMeal(date: today, name: "   ", category: .snack, calories: 200, macros: .zero)
        XCTAssertTrue(store.mealEntries.isEmpty)
        store.logHydration(ml: 0, on: today)
        store.logHydration(ml: -250, on: today)
        XCTAssertTrue(store.hydrationEntries.isEmpty)

        // Zero-entry baseline balance still returns finite BMR + NEAT.
        let emptyBalance = store.calorieBalance(on: today, steps: 0)
        XCTAssertEqual(emptyBalance.caloriesIn, 0)
        XCTAssertEqual(emptyBalance.bmrCalories, Int(store.profile.bmr.rounded()))
        XCTAssertEqual(emptyBalance.neatCalories, Int(max(0, store.profile.tdee - store.profile.bmr).rounded()))
        XCTAssertEqual(emptyBalance.stepBurnCalories, 0)
        XCTAssertEqual(emptyBalance.workoutBurnCalories, 0)
        XCTAssertEqual(emptyBalance.caloriesOut, emptyBalance.bmrCalories + emptyBalance.neatCalories)

        // Log meals on today and yesterday (local calendar day filtering must isolate them).
        store.logMeal(date: today, name: "Breakfast Oats", category: .breakfast, calories: 550, macros: MacroBreakdown(proteinG: 30, carbsG: 75, fatG: 12))
        store.logMeal(date: yesterday, name: "Yesterday Dinner", category: .dinner, calories: 900, macros: MacroBreakdown(proteinG: 50, carbsG: 80, fatG: 35))
        if let mealID = store.mealEntries.first(where: { $0.name == "Breakfast Oats" })?.id {
            store.toggleMealFavorite(id: mealID)
            XCTAssertEqual(store.mealEntries.first(where: { $0.id == mealID })?.isFavorite, true)
        } else {
            XCTFail("Expected meal entry")
        }

        store.logHydration(ml: 500, on: today)
        store.logHydration(ml: 250, on: today)
        store.logHydration(ml: 1_000, on: yesterday)
        XCTAssertEqual(store.hydrationMl(on: today), 750)
        XCTAssertEqual(store.hydrationMl(on: yesterday), 1_000)

        store.logBodyWeight(kg: 82.0, on: today)
        XCTAssertEqual(store.profile.weightKg, 82.0)

        store.logSet(exerciseID: "0025", exerciseName: "Bench Press", weightKg: 80, reps: 8)
        store.finishActiveSession()

        let balance = store.calorieBalance(on: today, steps: 10_000)
        XCTAssertEqual(balance.caloriesIn, 550)
        XCTAssertEqual(balance.stepBurnCalories, ActivityHistory.estimatedCalories(forSteps: 10_000, bodyWeightKg: 82.0))
        XCTAssertGreaterThan(balance.workoutBurnCalories, 0)
        XCTAssertEqual(
            balance.caloriesOut,
            balance.bmrCalories + balance.neatCalories + balance.stepBurnCalories + balance.workoutBurnCalories
        )
        XCTAssertEqual(balance.netBalance, balance.caloriesIn - balance.caloriesOut)
        XCTAssertEqual(balance.remainingCalories, store.goals.dailyCalorieTarget - 550)
    }
}
