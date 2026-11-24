import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var localizationKey: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static func resolve(_ rawValue: String?) -> AppAppearance {
        guard let rawValue, let matched = AppAppearance(rawValue: rawValue) else {
            return .system
        }
        return matched
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case emerald
    case obsidian
    case ocean
    case crimson

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .emerald: "Emerald"
        case .obsidian: "Obsidian"
        case .ocean: "Ocean"
        case .crimson: "Crimson"
        }
    }

    static func resolve(_ rawValue: String?) -> AppTheme {
        guard let rawValue, let matched = AppTheme(rawValue: rawValue) else {
            return .emerald
        }
        return matched
    }

    func palette(for colorScheme: ColorScheme) -> ThemePalette {
        let isDark = colorScheme == .dark

        let bgCanvas = isDark ? Color(hex: 0x0B0D10) : Color(hex: 0xF4F6F5)
        let bgCard = isDark ? Color(hex: 0x15181E) : Color(hex: 0xFFFFFF)
        let bgCardElevated = isDark ? Color(hex: 0x1E232B) : Color(hex: 0xF0F2F5)
        let textPrimary = isDark ? Color(hex: 0xF5F7FA) : Color(hex: 0x111418)
        let textSecondary = isDark ? Color(hex: 0x9BA3B0) : Color(hex: 0x5F6672)
        let borderSubtle = isDark ? Color(hex: 0xFFFFFF, alpha: 0.10) : Color(hex: 0x111418, alpha: 0.08)

        let accent: Color
        let bgHero: Color
        let accentOnHero: Color
        let success: Color
        let warning: Color
        let danger: Color

        switch self {
        case .emerald:
            accent = isDark ? Color(hex: 0x4CD08A) : Color(hex: 0x2B8C5C)
            bgHero = Color(hex: 0x113125)
            accentOnHero = Color(hex: 0xB3E87A)
            success = Color(hex: 0x2B8C5C)
            warning = Color(hex: 0xD9822B)
            danger = Color(hex: 0xD64545)
        case .obsidian:
            accent = isDark ? Color(hex: 0xE5A93C) : Color(hex: 0x272B33)
            bgHero = Color(hex: 0x16181D)
            accentOnHero = Color(hex: 0xE5A93C)
            success = Color(hex: 0x38A169)
            warning = Color(hex: 0xE5A93C)
            danger = Color(hex: 0xE05252)
        case .ocean:
            accent = isDark ? Color(hex: 0x5BC0EB) : Color(hex: 0x1D6FA5)
            bgHero = Color(hex: 0x0F273D)
            accentOnHero = Color(hex: 0x7DE2FC)
            success = Color(hex: 0x2A9D8F)
            warning = Color(hex: 0xE9A825)
            danger = Color(hex: 0xD64545)
        case .crimson:
            accent = isDark ? Color(hex: 0xF26A78) : Color(hex: 0xC83E4D)
            bgHero = Color(hex: 0x2E1218)
            accentOnHero = Color(hex: 0xF4A261)
            success = Color(hex: 0x2B8C5C)
            warning = Color(hex: 0xF4A261)
            danger = Color(hex: 0xC83E4D)
        }

        return ThemePalette(
            bgCanvas: bgCanvas,
            bgCard: bgCard,
            bgCardElevated: bgCardElevated,
            bgHero: bgHero,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accent: accent,
            accentMuted: accent.opacity(isDark ? 0.18 : 0.14),
            accentOnHero: accentOnHero,
            borderSubtle: borderSubtle,
            success: success,
            warning: warning,
            danger: danger
        )
    }
}

struct ThemePalette: Equatable, Sendable {
    let bgCanvas: Color
    let bgCard: Color
    let bgCardElevated: Color
    let bgHero: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let accentMuted: Color
    let accentOnHero: Color
    let borderSubtle: Color
    let success: Color
    let warning: Color
    let danger: Color
}

@MainActor
final class ThemeManager: ObservableObject {
    nonisolated static let appearanceKey = "appAppearance"
    nonisolated static let themeKey = "appTheme"

    @Published var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    @Published var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Self.themeKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = ActivityStorage.defaults) {
        self.defaults = defaults
        self.appearance = AppAppearance.resolve(defaults.string(forKey: Self.appearanceKey))
        self.theme = AppTheme.resolve(defaults.string(forKey: Self.themeKey))
    }

    var preferredColorScheme: ColorScheme? {
        appearance.colorScheme
    }

    func palette(for colorScheme: ColorScheme) -> ThemePalette {
        theme.palette(for: colorScheme)
    }
}

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue: ThemePalette = AppTheme.emerald.palette(for: .light)
}

extension EnvironmentValues {
    var themePalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

extension View {
    func cardSurface(
        palette: ThemePalette,
        cornerRadius: CGFloat = 24,
        padding: CGFloat = 20
    ) -> some View {
        self
            .padding(padding)
            .background(
                palette.bgCard,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(palette.borderSubtle, lineWidth: 1)
            )
    }

    func heroSurface(
        palette: ThemePalette,
        cornerRadius: CGFloat = 30,
        padding: CGFloat = 24
    ) -> some View {
        self
            .foregroundStyle(.white)
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(
                palette.bgHero,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
