import Foundation

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
