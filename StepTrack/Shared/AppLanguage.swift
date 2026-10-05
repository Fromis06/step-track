import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case vi, en, ja
    var id: String { rawValue }
    var name: String {
        switch self {
        case .vi: "Tiếng Việt"
        case .en: "English"
        case .ja: "日本語"
        }
    }
}

enum Copy {
    static var language: AppLanguage {
        AppLanguage(rawValue: ActivityStorage.defaults.string(forKey: "appLanguage") ?? "vi") ?? .vi
    }
    static var locale: Locale {
        switch language {
        case .vi: Locale(identifier: "vi_VN")
        case .en: Locale(identifier: "en_US")
        case .ja: Locale(identifier: "ja_JP")
        }
    }
    private static let translations: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "Translations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let translations = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return translations
    }()
    static func text(_ key: String) -> String {
        language == .en ? key : translations[key]?[language.rawValue] ?? key
    }
    static func format(_ key: String, _ values: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: values)
    }
    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }
    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }
    static func date(_ value: Date, timeOnly: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = timeOnly ? .none : .short
        formatter.timeStyle = .short
        return formatter.string(from: value)
    }
}
