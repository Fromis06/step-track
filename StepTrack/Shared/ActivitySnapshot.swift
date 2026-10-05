import Foundation

struct ActivityDay: Codable, Identifiable, Equatable {
    var date: Date
    var steps: Int
    var id: Date { date }
}

struct ActivitySnapshot: Codable, Equatable {
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

    static let empty = ActivitySnapshot(updatedAt: .distantPast, days: [], meters: nil, goal: 8_000)
}

enum ActivityStorage {
    static var groupID: String {
        guard let configured = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String else { return "" }
        let allowed = ProvisioningProfile.entitlements?["com.apple.security.application-groups"] as? [String] ?? []
        return ProvisioningProfile.sharedGroup(configured: configured, allowed: allowed)
    }

    // A missing app group must never silently look like a connected widget.
    static var sharedDefaults: UserDefaults? {
        guard !groupID.isEmpty,
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil else { return nil }
        return UserDefaults(suiteName: groupID)
    }

    static var defaults: UserDefaults { sharedDefaults ?? .standard }
    static var goal: Int {
        get {
            let saved = defaults.integer(forKey: "dailyGoal")
            return saved > 0 ? saved : 8_000
        }
        set { defaults.set(max(500, min(50_000, newValue)), forKey: "dailyGoal") }
    }

    static func load() -> ActivitySnapshot {
        guard let data = defaults.data(forKey: "activitySnapshot"),
              let value = try? JSONDecoder().decode(ActivitySnapshot.self, from: data) else { return .empty }
        return value
    }

    static func save(_ value: ActivitySnapshot) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: "activitySnapshot")
    }

    static func clear() { defaults.removeObject(forKey: "activitySnapshot") }
}
