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

struct HistoricalDay: Codable, Equatable, Identifiable {
    let id: String // Stable local Gregorian date, independent of later time zone changes.
    var steps: Int
    var goal: Int?
    var complete: Bool
    var updatedAt: Date
    var reachedGoal: Bool { goal.map { steps >= $0 } ?? false }
}

struct GoalChange: Codable, Equatable {
    var day: String
    var goal: Int
}

struct ActivityHistory: Codable, Equatable {
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
            // Replace a daily total, never add it. A later full-day query can finish yesterday.
            let target = key == today ? goal(on: key) : existing?.goal ?? goal(on: key)
            days[key] = HistoricalDay(id: key, steps: max(0, sample.steps), goal: target,
                                      complete: key < today, updatedAt: now)
        }
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

enum HistoryStorage {
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StepTrack", isDirectory: true)
            .appendingPathComponent("activity-history.json")
    }

    static func load(from url: URL = fileURL) throws -> ActivityHistory? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try JSONDecoder().decode(ActivityHistory.self, from: Data(contentsOf: url))
        guard value.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return value
    }

    static func save(_ history: ActivityHistory, to url: URL = fileURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(history).write(to: url, options: .atomic)
    }

    static func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
    }
}
