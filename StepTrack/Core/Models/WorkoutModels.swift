import Foundation

enum Weekday: Int, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    var id: Int { rawValue }

    var shortKey: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    var nameKey: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    static func from(date: Date, calendar: Calendar = HistoryCalendar.calendar) -> Weekday {
        let appleWeekday = calendar.component(.weekday, from: date)
        let mapped = appleWeekday == 1 ? 7 : appleWeekday - 1
        return Weekday(rawValue: mapped) ?? .monday
    }
}

enum SplitType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case push
    case pull
    case legs
    case upper
    case lower
    case fullBody
    case cardio
    case rest
    case custom

    var id: String { rawValue }

    var isRest: Bool { self == .rest }

    var titleKey: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .upper: "Upper"
        case .lower: "Lower"
        case .fullBody: "Full Body"
        case .cardio: "Cardio"
        case .rest: "Rest"
        case .custom: "Custom"
        }
    }

    var defaultMuscleGroups: [BodyPart] {
        switch self {
        case .push: [.chest, .shoulders, .upperArms]
        case .pull: [.back, .upperArms, .lowerArms]
        case .legs: [.upperLegs, .lowerLegs]
        case .upper: [.chest, .back, .shoulders, .upperArms]
        case .lower: [.upperLegs, .lowerLegs, .waist]
        case .fullBody: [.chest, .back, .shoulders, .upperLegs, .waist]
        case .cardio: [.cardio]
        case .rest: []
        case .custom: []
        }
    }

    var icon: AppIcon {
        switch self {
        case .push, .pull, .upper, .fullBody: .dumbbell
        case .legs, .lower: .footprints
        case .cardio: .heartPulse
        case .rest: .moon
        case .custom: .slidersHorizontal
        }
    }
}

struct DaySchedule: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: Weekday { weekday }
    var weekday: Weekday
    var split: SplitType
    var title: String
    var muscleGroups: [BodyPart]
    var exerciseIDs: [String]

    init(
        weekday: Weekday,
        split: SplitType,
        title: String? = nil,
        muscleGroups: [BodyPart]? = nil,
        exerciseIDs: [String] = []
    ) {
        self.weekday = weekday
        self.split = split
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.title = trimmed.isEmpty ? split.titleKey : trimmed
        self.muscleGroups = muscleGroups ?? split.defaultMuscleGroups
        self.exerciseIDs = exerciseIDs
    }
}

struct WeeklySplit: Codable, Equatable, Sendable {
    var days: [DaySchedule]

    init(days: [DaySchedule] = []) {
        self.days = Self.normalize(days)
    }

    enum CodingKeys: String, CodingKey {
        case days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedDays = try container.decodeIfPresent([DaySchedule].self, forKey: .days) ?? []
        self.days = Self.normalize(decodedDays)
    }

    static func normalize(_ rawDays: [DaySchedule]) -> [DaySchedule] {
        var byWeekday: [Weekday: DaySchedule] = [:]
        for item in rawDays where byWeekday[item.weekday] == nil {
            byWeekday[item.weekday] = item
        }
        return Weekday.allCases.map { weekday in
            byWeekday[weekday] ?? DaySchedule(weekday: weekday, split: .rest)
        }
    }

    static let defaultSplit = WeeklySplit(days: [
        DaySchedule(weekday: .monday, split: .push),
        DaySchedule(weekday: .tuesday, split: .pull),
        DaySchedule(weekday: .wednesday, split: .legs),
        DaySchedule(weekday: .thursday, split: .rest),
        DaySchedule(weekday: .friday, split: .upper),
        DaySchedule(weekday: .saturday, split: .lower),
        DaySchedule(weekday: .sunday, split: .rest)
    ])

    func schedule(for weekday: Weekday) -> DaySchedule {
        days.first { $0.weekday == weekday } ?? DaySchedule(weekday: weekday, split: .rest)
    }

    mutating func assign(
        _ weekday: Weekday,
        split: SplitType,
        title: String,
        muscleGroups: [BodyPart],
        exerciseIDs: [String]
    ) {
        let updated = DaySchedule(
            weekday: weekday,
            split: split,
            title: title,
            muscleGroups: muscleGroups,
            exerciseIDs: exerciseIDs
        )
        var map = Dictionary(uniqueKeysWithValues: days.map { ($0.weekday, $0) })
        map[weekday] = updated
        days = Weekday.allCases.map { map[$0] ?? DaySchedule(weekday: $0, split: .rest) }
    }
}

struct ExerciseSetLog: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var setNumber: Int
    var weightKg: Double
    var reps: Int
    var rpe: Double?
    var isCompleted: Bool
    var isPersonalRecord: Bool
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        setNumber: Int,
        weightKg: Double,
        reps: Int,
        rpe: Double? = nil,
        isCompleted: Bool = true,
        isPersonalRecord: Bool = false,
        completedAt: Date? = Date()
    ) {
        self.id = id
        self.setNumber = max(1, setNumber)
        self.weightKg = max(0, weightKg)
        self.reps = max(0, reps)
        self.rpe = rpe.map { min(10.0, max(1.0, $0)) }
        self.isCompleted = isCompleted
        self.isPersonalRecord = isPersonalRecord
        self.completedAt = isCompleted ? (completedAt ?? Date()) : nil
    }

    enum CodingKeys: String, CodingKey {
        case id, setNumber, weightKg, reps, rpe, isCompleted, isPersonalRecord, completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.setNumber = max(1, try container.decode(Int.self, forKey: .setNumber))
        self.weightKg = max(0, try container.decode(Double.self, forKey: .weightKg))
        self.reps = max(0, try container.decode(Int.self, forKey: .reps))
        self.rpe = try container.decodeIfPresent(Double.self, forKey: .rpe).map { min(10.0, max(1.0, $0)) }
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? true
        self.isPersonalRecord = try container.decodeIfPresent(Bool.self, forKey: .isPersonalRecord) ?? false
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    var estimated1RM: Double {
        Self.estimated1RM(weightKg: weightKg, reps: reps)
    }

    var volumeKg: Double {
        isCompleted ? weightKg * Double(reps) : 0
    }

    static func estimated1RM(weightKg: Double, reps: Int) -> Double {
        guard weightKg > 0, reps > 0 else { return 0 }
        if reps == 1 { return weightKg }
        return weightKg * (1.0 + Double(reps) / 30.0)
    }
}

struct ExerciseSessionEntry: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var exerciseID: String
    var exerciseName: String
    var sets: [ExerciseSetLog]

    init(
        id: UUID = UUID(),
        exerciseID: String,
        exerciseName: String,
        sets: [ExerciseSetLog] = []
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.sets = sets
    }

    var completedSets: [ExerciseSetLog] {
        sets.filter(\.isCompleted)
    }

    var completedSetsCount: Int {
        completedSets.count
    }

    var bestE1RM: Double {
        completedSets.map(\.estimated1RM).max() ?? 0
    }

    var maxWeightKg: Double {
        completedSets.map(\.weightKg).max() ?? 0
    }

    var totalVolumeKg: Double {
        completedSets.reduce(0) { $0 + $1.volumeKg }
    }

    var hasPersonalRecord: Bool {
        completedSets.contains(where: \.isPersonalRecord)
    }
}

struct WorkoutSession: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var split: SplitType
    var title: String
    var startedAt: Date
    var finishedAt: Date?
    var exercises: [ExerciseSessionEntry]
    var notes: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        split: SplitType = .custom,
        title: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        exercises: [ExerciseSessionEntry] = [],
        notes: String = ""
    ) {
        self.id = id
        self.date = date
        self.split = split
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmed.isEmpty ? split.titleKey : trimmed
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exercises = exercises
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id, date, split, title, startedAt, finishedAt, exercises, notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.date = try container.decode(Date.self, forKey: .date)
        self.split = try container.decode(SplitType.self, forKey: .split)
        self.title = try container.decode(String.self, forKey: .title)
        self.startedAt = try container.decode(Date.self, forKey: .startedAt)
        self.finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        self.exercises = try container.decodeIfPresent([ExerciseSessionEntry].self, forKey: .exercises) ?? []
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    var isFinished: Bool { finishedAt != nil }

    var durationSeconds: TimeInterval {
        let end = finishedAt ?? startedAt
        return max(0, end.timeIntervalSince(startedAt))
    }

    var totalVolumeKg: Double {
        exercises.reduce(0) { $0 + $1.totalVolumeKg }
    }

    var completedSetsCount: Int {
        exercises.reduce(0) { $0 + $1.completedSetsCount }
    }

    var personalRecordCount: Int {
        exercises.reduce(0) { count, entry in
            count + entry.completedSets.filter(\.isPersonalRecord).count
        }
    }

    func estimatedCaloriesBurned(bodyWeightKg: Double = 70) -> Int {
        guard completedSetsCount > 0 else { return 0 }
        let safeWeight = max(30, bodyWeightKg)
        let activeHours = max(durationSeconds / 3600.0, Double(completedSetsCount) * 2.0 / 60.0)
        let raw = activeHours * 4.5 * safeWeight + totalVolumeKg * 0.015
        return max(1, Int(raw.rounded()))
    }
}

struct WorkoutTemplate: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    var split: SplitType
    var exerciseIDs: [String]
    var defaultSetsPerExercise: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        split: SplitType = .custom,
        exerciseIDs: [String] = [],
        defaultSetsPerExercise: Int = 3,
        createdAt: Date = Date()
    ) {
        self.id = id
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed.isEmpty ? split.titleKey : trimmed
        self.split = split
        self.exerciseIDs = exerciseIDs
        self.defaultSetsPerExercise = max(1, min(12, defaultSetsPerExercise))
        self.createdAt = createdAt
    }
}

enum PersonalRecordDetector {
    static func isPersonalRecord(weightKg: Double, reps: Int, priorBestE1RM: Double?) -> Bool {
        let candidate = ExerciseSetLog.estimated1RM(weightKg: weightKg, reps: reps)
        guard candidate > 0 else { return false }
        guard let priorBestE1RM, priorBestE1RM > 0 else { return true }
        return candidate > priorBestE1RM + 0.001
    }
}

struct WeightProgressPoint: Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var maxWeightKg: Double
    var estimated1RM: Double
    var totalVolumeKg: Double
    var isPR: Bool
}
