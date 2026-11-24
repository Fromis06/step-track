import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case en
    case vi
    case ja
    case es

    var id: String { rawValue }

    var name: String {
        switch self {
        case .en: "English"
        case .vi: "Tiếng Việt"
        case .ja: "日本語"
        case .es: "Español"
        }
    }

    var locale: Locale {
        switch self {
        case .en: Locale(identifier: "en_US")
        case .vi: Locale(identifier: "vi_VN")
        case .ja: Locale(identifier: "ja_JP")
        case .es: Locale(identifier: "es_ES")
        }
    }

    static func resolve(_ rawValue: String?) -> AppLanguage {
        guard let rawValue, let matched = AppLanguage(rawValue: rawValue) else {
            return .en
        }
        return matched
    }
}

private final class LocalizationBundleToken {}

enum Copy {
    static let storageKey = "appLanguage"

    static var language: AppLanguage {
        AppLanguage.resolve(ActivityStorage.defaults.string(forKey: storageKey))
    }

    static var locale: Locale {
        language.locale
    }

    static let translations: [String: [String: String]] = {
        let bundles: [Bundle] = [.main, Bundle(for: LocalizationBundleToken.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: "Translations", withExtension: "json")
                ?? bundle.url(forResource: "Translations", withExtension: "json", subdirectory: "Localization"),
               let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
                return decoded
            }
        }
        return [:]
    }()

    static func text(_ key: String) -> String {
        text(key, language: language)
    }

    static func text(_ key: String, language: AppLanguage) -> String {
        guard let entry = translations[key] else { return key }
        return entry[language.rawValue] ?? entry[AppLanguage.en.rawValue] ?? key
    }

    static func format(_ key: String, _ values: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: values)
    }

    static func format(_ key: String, language: AppLanguage, _ values: CVarArg...) -> String {
        String(format: text(key, language: language), locale: language.locale, arguments: values)
    }

    static func number(_ value: Int, language: AppLanguage = Copy.language) -> String {
        value.formatted(.number.locale(language.locale))
    }

    static func decimal(_ value: Double, digits: Int = 2, language: AppLanguage = Copy.language) -> String {
        let clamped = max(0, digits)
        return value.formatted(.number.precision(.fractionLength(clamped)).locale(language.locale))
    }

    static func date(_ value: Date, timeOnly: Bool = false, language: AppLanguage = Copy.language) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = timeOnly ? .none : .short
        formatter.timeStyle = .short
        return formatter.string(from: value)
    }
}
