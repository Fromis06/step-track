import Foundation
@preconcurrency import UserNotifications

enum ProvisioningProfile {
    static let entitlements: [String: Any]? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decodeEntitlements(in: data)
    }()

    // Diagnostic metadata, not signature validation or an authorization decision.
    static func decodeEntitlements(in data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        return dictionary["Entitlements"] as? [String: Any]
    }

    static func sharedGroup(configured: String, allowed: [String]) -> String {
        if allowed.contains(configured) { return configured }
        // This app has one shared container. Re-signers may rename it with a team suffix.
        // Never pick arbitrarily when a profile grants more than one group.
        if allowed.count == 1, let group = allowed.first, group.hasPrefix("group.") { return group }
        return configured
    }
}

/// Local diagnostics only. A provisioning profile is not proof of effective signed entitlements.
struct SigningStatus {
    let healthKitInProfile: Bool?
    let widgetIncluded: Bool
    let sharedContainerAvailable: Bool

    static var current: SigningStatus {
        let entitlements = ProvisioningProfile.entitlements
        let plugins = Bundle.main.builtInPlugInsURL.flatMap {
            try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
        } ?? []
        let hasWidget = plugins.contains { url in
            guard url.pathExtension == "appex", let bundle = Bundle(url: url),
                  let info = bundle.infoDictionary?["NSExtension"] as? [String: Any] else { return false }
            return info["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension"
        }
        return SigningStatus(
            healthKitInProfile: entitlements.map { $0["com.apple.developer.healthkit"] as? Bool ?? false },
            widgetIncluded: hasWidget,
            sharedContainerAvailable: ActivityStorage.sharedDefaults != nil)
    }

    static func profileEntitlements(in data: Data) -> [String: Any]? {
        ProvisioningProfile.decodeEntitlements(in: data)
    }
}

protocol NotificationScheduling: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
}

extension NotificationScheduling {
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removeAllPendingNotificationRequests()
    }
}

extension UNUserNotificationCenter: NotificationScheduling {}

struct DailyReminderScheduler {
    static let reminderIdentifier = "daily-notification"

    func scheduleDailyReminder(
        hour: Int = 9,
        minute: Int = 0,
        using center: any NotificationScheduling = UNUserNotificationCenter.current()
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Step Track"
        content.body = "Daily activity reminder"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.reminderIdentifier,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }
}
