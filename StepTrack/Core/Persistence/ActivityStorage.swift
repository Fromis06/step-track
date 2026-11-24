import Foundation

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
