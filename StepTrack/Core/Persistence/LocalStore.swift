import Foundation

enum LocalStoreError: Error, LocalizedError, Equatable {
    case corruptBackupData
    case unsupportedBackupVersion(Int)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .corruptBackupData:
            return "Invalid backup file"
        case .unsupportedBackupVersion(let version):
            return "Unsupported backup version (\(version))"
        case .writeFailed(let detail):
            return "Could not save local data: \(detail)"
        }
    }
}

struct AppBackupPayload: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String
    var activityHistory: ActivityHistory
    var dailyStepGoal: Int
    var weeklySplit: WeeklySplit
    var workoutSessions: [WorkoutSession]
    var workoutTemplates: [WorkoutTemplate]
    var sleepEntries: [SleepEntry]
    var mealEntries: [MealEntry]
    var hydrationEntries: [HydrationEntry]
    var bodyWeightEntries: [BodyWeightEntry]
    var profile: UserBodyProfile
    var goals: PersonalGoals
    var goalChecklist: GoalChecklistStore

    init(
        schemaVersion: Int = AppBackupPayload.currentSchemaVersion,
        exportedAt: Date = Date(),
        appVersion: String = "1.0.0",
        activityHistory: ActivityHistory,
        dailyStepGoal: Int,
        weeklySplit: WeeklySplit,
        workoutSessions: [WorkoutSession],
        workoutTemplates: [WorkoutTemplate],
        sleepEntries: [SleepEntry],
        mealEntries: [MealEntry],
        hydrationEntries: [HydrationEntry],
        bodyWeightEntries: [BodyWeightEntry],
        profile: UserBodyProfile,
        goals: PersonalGoals,
        goalChecklist: GoalChecklistStore
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.activityHistory = activityHistory
        self.dailyStepGoal = dailyStepGoal
        self.weeklySplit = weeklySplit
        self.workoutSessions = workoutSessions
        self.workoutTemplates = workoutTemplates
        self.sleepEntries = sleepEntries
        self.mealEntries = mealEntries
        self.hydrationEntries = hydrationEntries
        self.bodyWeightEntries = bodyWeightEntries
        self.profile = profile
        self.goals = goals
        self.goalChecklist = goalChecklist
    }
}

final class LocalStore {
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StepTrack", isDirectory: true)
    }

    let directory: URL
    let historyFileURL: URL
    private let fileManager: FileManager
    private let writer: (URL, Data) throws -> Void

    init(
        directory: URL = LocalStore.defaultDirectory,
        fileManager: FileManager = .default,
        writer: ((URL, Data) throws -> Void)? = nil
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.historyFileURL = directory.standardizedFileURL == Self.defaultDirectory.standardizedFileURL
            ? HistoryStorage.fileURL
            : directory.appendingPathComponent("activity-history.json")
        self.writer = writer ?? { url, data in
            try data.write(to: url, options: .atomic)
        }
    }

    private enum StoreFile: String, CaseIterable {
        case weeklySplit = "weekly-split.json"
        case workoutSessions = "workout-sessions.json"
        case workoutTemplates = "workout-templates.json"
        case sleepEntries = "sleep-entries.json"
        case mealEntries = "meal-entries.json"
        case hydrationEntries = "hydration-entries.json"
        case bodyWeightEntries = "body-weight-entries.json"
        case userProfile = "user-profile.json"
        case personalGoals = "personal-goals.json"
        case goalChecklist = "goal-checklist.json"
    }

    private func url(for file: StoreFile) -> URL {
        directory.appendingPathComponent(file.rawValue)
    }

    private var managedFileURLs: [URL] {
        StoreFile.allCases.map { url(for: $0) } + [historyFileURL]
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func load<T: Decodable>(_ type: T.Type, from file: StoreFile, fallback: T) -> T {
        let fileURL = url(for: file)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? makeDecoder().decode(T.self, from: data) else {
            return fallback
        }
        return decoded
    }

    private func save<T: Encodable>(_ value: T, to file: StoreFile) throws {
        let fileURL = url(for: file)
        try ensureDirectory(for: fileURL)
        let data = try makeEncoder().encode(value)
        do {
            try writer(fileURL, data)
        } catch {
            throw LocalStoreError.writeFailed(error.localizedDescription)
        }
    }

    private func ensureDirectory(for fileURL: URL) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    // MARK: - Domain Load / Save

    func loadWeeklySplit() -> WeeklySplit {
        load(WeeklySplit.self, from: .weeklySplit, fallback: .defaultSplit)
    }

    func saveWeeklySplit(_ value: WeeklySplit) throws {
        try save(value, to: .weeklySplit)
    }

    func loadWorkoutSessions() -> [WorkoutSession] {
        load([WorkoutSession].self, from: .workoutSessions, fallback: [])
    }

    func saveWorkoutSessions(_ value: [WorkoutSession]) throws {
        try save(value, to: .workoutSessions)
    }

    func loadWorkoutTemplates() -> [WorkoutTemplate] {
        load([WorkoutTemplate].self, from: .workoutTemplates, fallback: [])
    }

    func saveWorkoutTemplates(_ value: [WorkoutTemplate]) throws {
        try save(value, to: .workoutTemplates)
    }

    func loadSleepEntries() -> [SleepEntry] {
        load([SleepEntry].self, from: .sleepEntries, fallback: [])
    }

    func saveSleepEntries(_ value: [SleepEntry]) throws {
        try save(value, to: .sleepEntries)
    }

    func loadMealEntries() -> [MealEntry] {
        load([MealEntry].self, from: .mealEntries, fallback: [])
    }

    func saveMealEntries(_ value: [MealEntry]) throws {
        try save(value, to: .mealEntries)
    }

    func loadHydrationEntries() -> [HydrationEntry] {
        load([HydrationEntry].self, from: .hydrationEntries, fallback: [])
    }

    func saveHydrationEntries(_ value: [HydrationEntry]) throws {
        try save(value, to: .hydrationEntries)
    }

    func loadBodyWeightEntries() -> [BodyWeightEntry] {
        load([BodyWeightEntry].self, from: .bodyWeightEntries, fallback: [])
    }

    func saveBodyWeightEntries(_ value: [BodyWeightEntry]) throws {
        try save(value, to: .bodyWeightEntries)
    }

    func loadProfile() -> UserBodyProfile {
        load(UserBodyProfile.self, from: .userProfile, fallback: UserBodyProfile())
    }

    func saveProfile(_ value: UserBodyProfile) throws {
        try save(value, to: .userProfile)
    }

    func loadGoals() -> PersonalGoals {
        load(PersonalGoals.self, from: .personalGoals, fallback: PersonalGoals())
    }

    func saveGoals(_ value: PersonalGoals) throws {
        try save(value, to: .personalGoals)
    }

    func loadGoalChecklist() -> GoalChecklistStore {
        load(GoalChecklistStore.self, from: .goalChecklist, fallback: GoalChecklistStore())
    }

    func saveGoalChecklist(_ value: GoalChecklistStore) throws {
        try save(value, to: .goalChecklist)
    }

    // MARK: - Backup Export / Import (Atomic with Rollback)

    func exportBackupData(
        activityHistory: ActivityHistory,
        dailyStepGoal: Int,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    ) throws -> Data {
        let payload = AppBackupPayload(
            schemaVersion: AppBackupPayload.currentSchemaVersion,
            exportedAt: Date(),
            appVersion: appVersion,
            activityHistory: activityHistory,
            dailyStepGoal: dailyStepGoal,
            weeklySplit: loadWeeklySplit(),
            workoutSessions: loadWorkoutSessions(),
            workoutTemplates: loadWorkoutTemplates(),
            sleepEntries: loadSleepEntries(),
            mealEntries: loadMealEntries(),
            hydrationEntries: loadHydrationEntries(),
            bodyWeightEntries: loadBodyWeightEntries(),
            profile: loadProfile(),
            goals: loadGoals(),
            goalChecklist: loadGoalChecklist()
        )
        return try makeEncoder().encode(payload)
    }

    private enum FileSnapshot {
        case absent
        case data(Data)
    }

    func importBackupData(_ data: Data) throws -> AppBackupPayload {
        let payload: AppBackupPayload
        do {
            payload = try makeDecoder().decode(AppBackupPayload.self, from: data)
        } catch {
            throw LocalStoreError.corruptBackupData
        }

        guard payload.schemaVersion == AppBackupPayload.currentSchemaVersion else {
            throw LocalStoreError.unsupportedBackupVersion(payload.schemaVersion)
        }
        guard payload.activityHistory.version == 1 else {
            throw LocalStoreError.unsupportedBackupVersion(payload.activityHistory.version)
        }

        // Capture pre-import snapshot for atomic rollback.
        var snapshot: [URL: FileSnapshot] = [:]
        for fileURL in managedFileURLs {
            if fileManager.fileExists(atPath: fileURL.path) {
                snapshot[fileURL] = .data(try Data(contentsOf: fileURL))
            } else {
                snapshot[fileURL] = .absent
            }
        }

        do {
            try saveWeeklySplit(payload.weeklySplit)
            try saveWorkoutSessions(payload.workoutSessions)
            try saveWorkoutTemplates(payload.workoutTemplates)
            try saveSleepEntries(payload.sleepEntries)
            try saveMealEntries(payload.mealEntries)
            try saveHydrationEntries(payload.hydrationEntries)
            try saveBodyWeightEntries(payload.bodyWeightEntries)
            try saveProfile(payload.profile)
            try saveGoals(payload.goals)
            try saveGoalChecklist(payload.goalChecklist)

            try ensureDirectory(for: historyFileURL)
            let historyData = try JSONEncoder().encode(payload.activityHistory)
            do {
                try writer(historyFileURL, historyData)
            } catch {
                throw LocalStoreError.writeFailed(error.localizedDescription)
            }
        } catch {
            // Roll back all managed files to exact pre-import state.
            for (fileURL, originalState) in snapshot {
                switch originalState {
                case .data(let originalData):
                    try? ensureDirectory(for: fileURL)
                    try? originalData.write(to: fileURL, options: .atomic)
                case .absent:
                    if fileManager.fileExists(atPath: fileURL.path) {
                        try? fileManager.removeItem(at: fileURL)
                    }
                }
            }
            throw error
        }

        return payload
    }

    func clearAll() throws {
        for fileURL in managedFileURLs {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }
}
