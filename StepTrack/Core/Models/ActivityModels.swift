import Foundation

enum HistoryCalendar {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .current
        value.firstWeekday = 2
        return value
    }

    static func key(for date: Date, calendar: Calendar = calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func date(for key: String, calendar: Calendar = calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func monthCells(containing date: Date, calendar: Calendar = calendar) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let offset = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        var cells = Array<Date?>(repeating: nil, count: offset)
        cells += range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }.map { Optional($0) }
        cells += Array<Date?>(repeating: nil, count: 42 - cells.count)
        return cells
    }
}

struct ActivityDay: Codable, Identifiable, Equatable, Hashable, Sendable {
    var date: Date
    var steps: Int
    var id: Date { date }
}

struct ActivitySnapshot: Codable, Equatable, Sendable {
    var updatedAt: Date
    var days: [ActivityDay]
    var meters: Double?
    var goal: Int

    func steps(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }?.steps ?? 0
    }

    func progress(on date: Date = Date(), calendar: Calendar = .current) -> Double {
        min(1, max(0, Double(steps(on: date, calendar: calendar)) / Double(max(1, goal))))
    }

    func reached25PercentGoal(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard goal > 0 else { return false }
        return Double(steps(on: date, calendar: calendar)) >= Double(goal) * 0.25
    }

    func reached50PercentGoal(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard goal > 0 else { return false }
        return Double(steps(on: date, calendar: calendar)) >= Double(goal) * 0.50
    }

    func reached75PercentGoal(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard goal > 0 else { return false }
        return Double(steps(on: date, calendar: calendar)) >= Double(goal) * 0.75
    }

    func reached100PercentGoal(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard goal > 0 else { return false }
        return steps(on: date, calendar: calendar) >= goal
    }

    func estimatedStrideUnits(on date: Date = Date(), calendar: Calendar = .current, stepsPerUnit: Int = 144) -> Int {
        guard stepsPerUnit > 0 else { return 0 }
        return max(0, steps(on: date, calendar: calendar)) / stepsPerUnit
    }

    static let empty = ActivitySnapshot(updatedAt: .distantPast, days: [], meters: nil, goal: 8_000)
}

struct HistoricalDay: Codable, Equatable, Identifiable, Sendable {
    let id: String // Stable local Gregorian date, independent of later time zone changes.
    var steps: Int
    var goal: Int?
    var complete: Bool
    var updatedAt: Date
    var isManual: Bool = false

    var reachedGoal: Bool { goal.map { steps >= $0 } ?? false }

    init(
        id: String,
        steps: Int,
        goal: Int?,
        complete: Bool,
        updatedAt: Date,
        isManual: Bool = false
    ) {
        self.id = id
        self.steps = steps
        self.goal = goal
        self.complete = complete
        self.updatedAt = updatedAt
        self.isManual = isManual
    }

    enum CodingKeys: String, CodingKey {
        case id, steps, goal, complete, updatedAt, isManual
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.steps = try container.decode(Int.self, forKey: .steps)
        self.goal = try container.decodeIfPresent(Int.self, forKey: .goal)
        self.complete = try container.decode(Bool.self, forKey: .complete)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.isManual = try container.decodeIfPresent(Bool.self, forKey: .isManual) ?? false
    }
}

struct GoalChange: Codable, Equatable, Sendable {
    var day: String
    var goal: Int
}

struct ActivityHistory: Codable, Equatable, Sendable {
    var version = 1
    var days: [String: HistoricalDay] = [:]
    var goals: [GoalChange] = []

    func goal(on day: String) -> Int? {
        goals.filter { $0.day <= day }.max { $0.day < $1.day }?.goal
    }

    mutating func changeGoal(_ goal: Int, on date: Date, calendar: Calendar = HistoryCalendar.calendar) {
        let key = HistoryCalendar.key(for: date, calendar: calendar)
        let clamped = max(500, min(50_000, goal))
        goals.removeAll { $0.day == key }
        goals.append(GoalChange(day: key, goal: clamped))
        goals.sort { $0.day < $1.day }
        // Only today's target can change. Historical targets are never rewritten.
        if var today = days[key] {
            today.goal = clamped
            days[key] = today
        }
    }

    mutating func merge(_ samples: [ActivityDay], observedAt now: Date,
                        calendar: Calendar = HistoryCalendar.calendar) {
        let today = HistoryCalendar.key(for: now, calendar: calendar)
        for sample in samples {
            let key = HistoryCalendar.key(for: sample.date, calendar: calendar)
            guard key <= today else { continue }
            let existing = days[key]
            if let existing, existing.isManual, sample.steps <= 0 {
                continue
            }
            // Replace a daily total, never add it. A later full-day query can finish yesterday.
            let target = key == today ? goal(on: key) : existing?.goal ?? goal(on: key)
            days[key] = HistoricalDay(
                id: key,
                steps: max(0, sample.steps),
                goal: target,
                complete: key < today,
                updatedAt: now,
                isManual: false
            )
        }
    }

    mutating func setManualSteps(
        _ steps: Int,
        on date: Date,
        observedAt now: Date = Date(),
        calendar: Calendar = HistoryCalendar.calendar
    ) {
        let clamped = max(0, min(200_000, steps))
        let key = HistoryCalendar.key(for: date, calendar: calendar)
        let today = HistoryCalendar.key(for: now, calendar: calendar)
        guard key <= today else { return }
        let existing = days[key]
        let target = key == today ? goal(on: key) : existing?.goal ?? goal(on: key)
        days[key] = HistoricalDay(
            id: key,
            steps: clamped,
            goal: target,
            complete: key < today,
            updatedAt: now,
            isManual: true
        )
    }

    func recentDays(
        count: Int,
        endingAt now: Date = Date(),
        calendar: Calendar = HistoryCalendar.calendar
    ) -> [ActivityDay] {
        guard count > 0 else { return [] }
        let todayStart = calendar.startOfDay(for: now)
        return (-(count - 1)...0).compactMap { offset in
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: todayStart) else { return nil }
            let key = HistoryCalendar.key(for: dayDate, calendar: calendar)
            return ActivityDay(date: dayDate, steps: days[key]?.steps ?? 0)
        }
    }

    static func estimatedCalories(forSteps steps: Int, bodyWeightKg: Double = 70) -> Int {
        Int((Double(max(0, steps)) * 0.04 * max(30, bodyWeightKg) / 70.0).rounded())
    }

    func records(year: Int, month: Int? = nil) -> [HistoricalDay] {
        let prefix = month.map { String(format: "%04d-%02d-", year, $0) } ?? String(format: "%04d-", year)
        return days.values.filter { $0.id.hasPrefix(prefix) }.sorted { $0.id < $1.id }
    }

    static func migrating(_ snapshot: ActivitySnapshot, goal: Int, now: Date,
                          calendar: Calendar = HistoryCalendar.calendar) -> ActivityHistory {
        var history = ActivityHistory()
        // Earlier app versions did not record historical targets. Leave these unknown.
        history.changeGoal(goal, on: now, calendar: calendar)
        history.merge(snapshot.days, observedAt: snapshot.updatedAt, calendar: calendar)
        return history
    }
}

struct PersonalGoalItem: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var targetDate: Date
    var isComplete: Bool

    init(id: UUID = UUID(), title: String, targetDate: Date = Date(), isComplete: Bool = false) {
        self.id = id
        self.title = title
        self.targetDate = targetDate
        self.isComplete = isComplete
    }
}

struct GoalChecklistStore: Codable, Equatable, Sendable {
    private(set) var items: [PersonalGoalItem] = []

    var incompleteGoals: [PersonalGoalItem] { items.filter { !$0.isComplete } }
    var completeGoals: [PersonalGoalItem] { items.filter(\.isComplete) }

    mutating func addGoal(title: String, targetDate: Date = Date(), isComplete: Bool = false) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(PersonalGoalItem(title: trimmed, targetDate: targetDate, isComplete: isComplete))
    }

    mutating func toggleCompletion(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isComplete.toggle()
    }

    mutating func deleteGoals(at offsets: IndexSet, isComplete: Bool) {
        let matchingIDs = (isComplete ? completeGoals : incompleteGoals).enumerated()
            .filter { offsets.contains($0.offset) }
            .map(\.element.id)
        items.removeAll { matchingIDs.contains($0.id) }
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> GoalChecklistStore {
        guard FileManager.default.fileExists(atPath: url.path) else { return GoalChecklistStore() }
        return try JSONDecoder().decode(GoalChecklistStore.self, from: Data(contentsOf: url))
    }
}

enum AppAttribution {
    static let appName = "Step Track"
    static let upstreamAuthor = "Brittany Rima"
    static let license = "MIT"
}
