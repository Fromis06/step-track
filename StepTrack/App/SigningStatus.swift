import Foundation

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
