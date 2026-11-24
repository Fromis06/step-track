import Foundation

struct SleepEntry: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var bedTime: Date
    var wakeTime: Date
    var quality: Int
    var note: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        bedTime: Date,
        wakeTime: Date,
        quality: Int = 3,
        note: String = ""
    ) {
        self.id = id
        self.date = date
        self.bedTime = bedTime
        self.wakeTime = wakeTime
        self.quality = min(5, max(1, quality))
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case id, date, bedTime, wakeTime, quality, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.date = try container.decode(Date.self, forKey: .date)
        self.bedTime = try container.decode(Date.self, forKey: .bedTime)
        self.wakeTime = try container.decode(Date.self, forKey: .wakeTime)
        self.quality = min(5, max(1, try container.decodeIfPresent(Int.self, forKey: .quality) ?? 3))
        self.note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    static func normalizedWakeTime(bedTime: Date, wakeTime: Date) -> Date {
        var adjusted = wakeTime
        var guardIterations = 0
        while adjusted < bedTime && guardIterations < 2 {
            adjusted = adjusted.addingTimeInterval(86_400)
            guardIterations += 1
        }
        return adjusted
    }

    var durationMinutes: Int {
        let end = Self.normalizedWakeTime(bedTime: bedTime, wakeTime: wakeTime)
        let minutes = Int((end.timeIntervalSince(bedTime) / 60.0).rounded())
        return min(1440, max(0, minutes))
    }

    var durationHours: Double {
        Double(durationMinutes) / 60.0
    }
}

enum MealCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    var icon: AppIcon {
        switch self {
        case .breakfast: .sun
        case .lunch: .utensils
        case .dinner: .moon
        case .snack: .zap
        }
    }
}

struct MacroBreakdown: Codable, Equatable, Hashable, Sendable {
    var proteinG: Double
    var carbsG: Double
    var fatG: Double

    init(proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0) {
        self.proteinG = max(0, proteinG)
        self.carbsG = max(0, carbsG)
        self.fatG = max(0, fatG)
    }

    static let zero = MacroBreakdown(proteinG: 0, carbsG: 0, fatG: 0)

    static func + (lhs: MacroBreakdown, rhs: MacroBreakdown) -> MacroBreakdown {
        MacroBreakdown(
            proteinG: lhs.proteinG + rhs.proteinG,
            carbsG: lhs.carbsG + rhs.carbsG,
            fatG: lhs.fatG + rhs.fatG
        )
    }

    var macroCalories: Double {
        proteinG * 4.0 + carbsG * 4.0 + fatG * 9.0
    }
}

struct MealEntry: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var name: String
    var category: MealCategory
    var calories: Int
    var macros: MacroBreakdown
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        name: String,
        category: MealCategory = .snack,
        calories: Int,
        macros: MacroBreakdown = .zero,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.date = date
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = category
        self.calories = max(0, calories)
        self.macros = macros
        self.isFavorite = isFavorite
    }

    enum CodingKeys: String, CodingKey {
        case id, date, name, category, calories, macros, isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.date = try container.decode(Date.self, forKey: .date)
        self.name = try container.decode(String.self, forKey: .name)
        self.category = try container.decode(MealCategory.self, forKey: .category)
        self.calories = max(0, try container.decode(Int.self, forKey: .calories))
        self.macros = try container.decodeIfPresent(MacroBreakdown.self, forKey: .macros) ?? .zero
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

struct HydrationEntry: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var ml: Int

    init(id: UUID = UUID(), date: Date = Date(), ml: Int) {
        self.id = id
        self.date = date
        self.ml = max(0, ml)
    }
}

struct BodyWeightEntry: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var weightKg: Double

    init(id: UUID = UUID(), date: Date = Date(), weightKg: Double) {
        self.id = id
        self.date = date
        self.weightKg = min(400.0, max(20.0, weightKg))
    }
}

enum BiologicalSex: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case male
    case female
    case other

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case sedentary
    case lightlyActive
    case moderatelyActive
    case veryActive
    case athlete

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .lightlyActive: 1.375
        case .moderatelyActive: 1.55
        case .veryActive: 1.725
        case .athlete: 1.9
        }
    }

    var localizationKey: String {
        switch self {
        case .sedentary: "Sedentary"
        case .lightlyActive: "Lightly Active"
        case .moderatelyActive: "Moderate"
        case .veryActive: "Active"
        case .athlete: "Very Active"
        }
    }
}

struct UserBodyProfile: Codable, Equatable, Hashable, Sendable {
    var heightCm: Double
    var weightKg: Double
    var age: Int
    var sex: BiologicalSex
    var activityLevel: ActivityLevel

    init(
        heightCm: Double = 170,
        weightKg: Double = 70,
        age: Int = 28,
        sex: BiologicalSex = .male,
        activityLevel: ActivityLevel = .moderatelyActive
    ) {
        self.heightCm = min(250, max(100, heightCm))
        self.weightKg = min(400, max(20, weightKg))
        self.age = min(120, max(12, age))
        self.sex = sex
        self.activityLevel = activityLevel
    }

    var bmr: Double {
        let base = 10.0 * weightKg + 6.25 * heightCm - 5.0 * Double(age)
        let sexOffset: Double
        switch sex {
        case .male: sexOffset = 5.0
        case .female: sexOffset = -161.0
        case .other: sexOffset = -78.0
        }
        return max(800.0, base + sexOffset)
    }

    var tdee: Double {
        bmr * activityLevel.multiplier
    }
}

struct PersonalGoals: Codable, Equatable, Hashable, Sendable {
    var dailySteps: Int
    var dailySleepHours: Double
    var dailyCalorieTarget: Int
    var weeklyWorkoutsTarget: Int
    var targetWeightKg: Double?
    var dailyHydrationMl: Int
    var dailyProteinG: Int
    var dailyCarbsG: Int
    var dailyFatG: Int

    init(
        dailySteps: Int = 8_000,
        dailySleepHours: Double = 8.0,
        dailyCalorieTarget: Int = 2_200,
        weeklyWorkoutsTarget: Int = 4,
        targetWeightKg: Double? = nil,
        dailyHydrationMl: Int = 2_500,
        dailyProteinG: Int = 140,
        dailyCarbsG: Int = 240,
        dailyFatG: Int = 70
    ) {
        self.dailySteps = max(500, min(50_000, dailySteps))
        self.dailySleepHours = min(16.0, max(3.0, dailySleepHours))
        self.dailyCalorieTarget = max(800, min(10_000, dailyCalorieTarget))
        self.weeklyWorkoutsTarget = max(1, min(14, weeklyWorkoutsTarget))
        self.targetWeightKg = targetWeightKg.map { min(400.0, max(20.0, $0)) }
        self.dailyHydrationMl = max(500, min(10_000, dailyHydrationMl))
        self.dailyProteinG = max(20, min(500, dailyProteinG))
        self.dailyCarbsG = max(20, min(1_000, dailyCarbsG))
        self.dailyFatG = max(10, min(400, dailyFatG))
    }

    enum CodingKeys: String, CodingKey {
        case dailySteps, dailySleepHours, dailyCalorieTarget, weeklyWorkoutsTarget
        case targetWeightKg, dailyHydrationMl, dailyProteinG, dailyCarbsG, dailyFatG
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let steps = try container.decodeIfPresent(Int.self, forKey: .dailySteps) ?? 8_000
        let sleep = try container.decodeIfPresent(Double.self, forKey: .dailySleepHours) ?? 8.0
        let calories = try container.decodeIfPresent(Int.self, forKey: .dailyCalorieTarget) ?? 2_200
        let workouts = try container.decodeIfPresent(Int.self, forKey: .weeklyWorkoutsTarget) ?? 4
        let targetWeight = try container.decodeIfPresent(Double.self, forKey: .targetWeightKg)
        let hydration = try container.decodeIfPresent(Int.self, forKey: .dailyHydrationMl) ?? 2_500
        let protein = try container.decodeIfPresent(Int.self, forKey: .dailyProteinG) ?? 140
        let carbs = try container.decodeIfPresent(Int.self, forKey: .dailyCarbsG) ?? 240
        let fat = try container.decodeIfPresent(Int.self, forKey: .dailyFatG) ?? 70
        self.init(
            dailySteps: steps,
            dailySleepHours: sleep,
            dailyCalorieTarget: calories,
            weeklyWorkoutsTarget: workouts,
            targetWeightKg: targetWeight,
            dailyHydrationMl: hydration,
            dailyProteinG: protein,
            dailyCarbsG: carbs,
            dailyFatG: fat
        )
    }
}

struct CalorieBalance: Equatable, Sendable {
    var caloriesIn: Int
    var bmrCalories: Int
    var neatCalories: Int
    var stepBurnCalories: Int
    var workoutBurnCalories: Int
    var targetCalories: Int
    var macrosConsumed: MacroBreakdown

    var caloriesOut: Int {
        bmrCalories + neatCalories + stepBurnCalories + workoutBurnCalories
    }

    var netBalance: Int {
        caloriesIn - caloriesOut
    }

    var remainingCalories: Int {
        targetCalories - caloriesIn
    }
}
