import XCTest
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
@testable import StepTrack

final class ThemeAndL10nTests: XCTestCase {
    private var savedLanguage: Any?
    private var suiteName: String!
    private var ephemeralDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedLanguage = ActivityStorage.defaults.object(forKey: Copy.storageKey)
        suiteName = "ThemeAndL10nTests-\(UUID().uuidString)"
        ephemeralDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        if let savedLanguage {
            ActivityStorage.defaults.set(savedLanguage, forKey: Copy.storageKey)
        } else {
            ActivityStorage.defaults.removeObject(forKey: Copy.storageKey)
        }
        ephemeralDefaults.removePersistentDomain(forName: suiteName)
        ephemeralDefaults = nil
        super.tearDown()
    }

    func testAllThemesAndAppearancesResolveDistinctPalettesAndFallbacks() {
        XCTAssertEqual(AppTheme.allCases.count, 4)
        XCTAssertEqual(AppAppearance.allCases.count, 3)

        XCTAssertEqual(AppTheme.resolve(nil), .emerald)
        XCTAssertEqual(AppTheme.resolve("unknown-theme"), .emerald)
        XCTAssertEqual(AppTheme.resolve("crimson"), .crimson)

        XCTAssertEqual(AppAppearance.resolve(nil), .system)
        XCTAssertEqual(AppAppearance.resolve("sepia"), .system)
        XCTAssertEqual(AppAppearance.resolve("dark"), .dark)

        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)

        var lightPalettes: [ThemePalette] = []
        var darkPalettes: [ThemePalette] = []

        for theme in AppTheme.allCases {
            let light = theme.palette(for: .light)
            let dark = theme.palette(for: .dark)
            XCTAssertNotEqual(light, dark)
            XCTAssertNotEqual(light.textPrimary, light.bgCanvas)
            XCTAssertNotEqual(dark.textPrimary, dark.bgCanvas)
            XCTAssertNotEqual(light.accent, light.bgCard)
            XCTAssertNotEqual(dark.accent, dark.bgCard)

            #if canImport(UIKit)
            assertMinimumContrast(foreground: light.textPrimary, background: light.bgCanvas, minDelta: 0.45)
            assertMinimumContrast(foreground: dark.textPrimary, background: dark.bgCanvas, minDelta: 0.45)
            assertMinimumContrast(foreground: light.accent, background: light.bgCard, minDelta: 0.15)
            assertMinimumContrast(foreground: dark.accent, background: dark.bgCard, minDelta: 0.15)
            #endif

            lightPalettes.append(light)
            darkPalettes.append(dark)
        }

        // Verify all 4 themes have distinct palettes in both Light and Dark modes.
        for i in 0..<AppTheme.allCases.count {
            for j in (i + 1)..<AppTheme.allCases.count {
                XCTAssertNotEqual(lightPalettes[i], lightPalettes[j])
                XCTAssertNotEqual(darkPalettes[i], darkPalettes[j])
            }
        }
    }

    #if canImport(UIKit)
    private func assertMinimumContrast(foreground: Color, background: Color, minDelta: Double) {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        XCTAssertTrue(UIColor(foreground).getRed(&fr, green: &fg, blue: &fb, alpha: &fa))
        XCTAssertTrue(UIColor(background).getRed(&br, green: &bg, blue: &bb, alpha: &ba))
        let fgLum = 0.2126 * Double(fr) + 0.7152 * Double(fg) + 0.0722 * Double(fb)
        let bgLum = 0.2126 * Double(br) + 0.7152 * Double(bg) + 0.0722 * Double(bb)
        XCTAssertGreaterThan(abs(fgLum - bgLum), minDelta)
    }
    #endif

    @MainActor
    func testThemeManagerPersistenceWithEphemeralDefaults() {
        let initial = ThemeManager(defaults: ephemeralDefaults)
        XCTAssertEqual(initial.theme, .emerald)
        XCTAssertEqual(initial.appearance, .system)
        XCTAssertNil(initial.preferredColorScheme)

        initial.theme = .ocean
        initial.appearance = .dark
        XCTAssertEqual(initial.preferredColorScheme, .dark)
        XCTAssertEqual(ephemeralDefaults.string(forKey: ThemeManager.themeKey), "ocean")
        XCTAssertEqual(ephemeralDefaults.string(forKey: ThemeManager.appearanceKey), "dark")

        let reloaded = ThemeManager(defaults: ephemeralDefaults)
        XCTAssertEqual(reloaded.theme, .ocean)
        XCTAssertEqual(reloaded.appearance, .dark)
        XCTAssertEqual(reloaded.palette(for: .dark), AppTheme.ocean.palette(for: .dark))

        // Invalid persisted raw values fall back safely.
        ephemeralDefaults.set("invalid_theme", forKey: ThemeManager.themeKey)
        ephemeralDefaults.set("invalid_mode", forKey: ThemeManager.appearanceKey)
        let recovered = ThemeManager(defaults: ephemeralDefaults)
        XCTAssertEqual(recovered.theme, .emerald)
        XCTAssertEqual(recovered.appearance, .system)
    }

    func testAllLanguagesAndTranslationsCompleteness() throws {
        XCTAssertEqual(AppLanguage.allCases.count, 4)
        XCTAssertEqual(AppLanguage.en.name, "English")
        XCTAssertEqual(AppLanguage.vi.name, "Ti\u{1EBF}ng Vi\u{1EC7}t")
        XCTAssertEqual(AppLanguage.ja.name, "\u{65E5}\u{672C}\u{8A9E}")
        XCTAssertEqual(AppLanguage.es.name, "Espa\u{00F1}ol")

        XCTAssertEqual(AppLanguage.en.locale.identifier, "en_US")
        XCTAssertEqual(AppLanguage.vi.locale.identifier, "vi_VN")
        XCTAssertEqual(AppLanguage.ja.locale.identifier, "ja_JP")
        XCTAssertEqual(AppLanguage.es.locale.identifier, "es_ES")

        XCTAssertEqual(AppLanguage.resolve(nil), .en)
        XCTAssertEqual(AppLanguage.resolve("fr"), .en)
        XCTAssertEqual(AppLanguage.resolve("vi"), .vi)

        let table = Copy.translations
        XCTAssertGreaterThanOrEqual(table.count, 373)

        for (key, entry) in table {
            for lang in AppLanguage.allCases {
                let value = entry[lang.rawValue]
                XCTAssertNotNil(value, "Missing \(lang.rawValue) for key '\(key)'")
                XCTAssertFalse((value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty \(lang.rawValue) for key '\(key)'")
            }
        }

        // Verify all 40 secondary_muscles from exercises.json are present in Translations.json.
        let loader = try ExerciseLibraryLoader(bundle: .main)
        let secondaryMuscles = Set(loader.exercises.flatMap(\.secondaryMuscles))
        XCTAssertEqual(secondaryMuscles.count, 40)
        for muscle in secondaryMuscles {
            XCTAssertNotNil(table[muscle], "Missing translation key for secondary muscle '\(muscle)'")
        }

        // Verify all 15 format keys format safely across all 4 languages.
        let singleArgFormatKeys = [
            "%@%% of goal",
            "Goal: %@ steps",
            "%@ steps",
            "Updated %@",
            "At %@",
            "/ %@ steps",
            "Goal: %@",
            "%@ km",
            "%@ kcal",
            "%@ kg",
            "%@ ml",
            "%@ sets",
            "%@ reps"
        ]
        for lang in AppLanguage.allCases {
            for key in singleArgFormatKeys {
                let formatted = Copy.format(key, language: lang, "42")
                XCTAssertTrue(formatted.contains("42"), "Format key '\(key)' failed for \(lang.rawValue)")
                XCTAssertFalse(formatted.contains("%@"))
            }
            let twoArgSteps = Copy.format("%@ steps today, goal %@", language: lang, "7,500", "10,000")
            XCTAssertTrue(twoArgSteps.contains("7,500"))
            XCTAssertTrue(twoArgSteps.contains("10,000"))

            let twoArgSleep = Copy.format("%@ h %@ m", language: lang, "7", "30")
            XCTAssertTrue(twoArgSleep.contains("7"))
            XCTAssertTrue(twoArgSleep.contains("30"))
        }
    }

    func testCopyTextFormatNumberDecimalDateAndUnknownFallback() {
        ActivityStorage.defaults.set("ja", forKey: Copy.storageKey)
        XCTAssertEqual(Copy.language, .ja)
        XCTAssertEqual(Copy.locale.identifier, "ja_JP")
        XCTAssertEqual(Copy.text("Today"), Copy.text("Today", language: .ja))
        XCTAssertEqual(Copy.format("%@ kg", "82.5"), Copy.format("%@ kg", language: .ja, "82.5"))

        XCTAssertEqual(Copy.text("nonexistent.translation.key", language: .vi), "nonexistent.translation.key")

        for lang in AppLanguage.allCases {
            XCTAssertFalse(Copy.number(0, language: lang).isEmpty)
            XCTAssertFalse(Copy.number(10_000, language: lang).isEmpty)
            XCTAssertFalse(Copy.decimal(82.5, digits: 1, language: lang).isEmpty)
            XCTAssertFalse(Copy.decimal(82.5, digits: -2, language: lang).isEmpty)
            let sampleDate = Date(timeIntervalSince1970: 1_760_000_000)
            XCTAssertFalse(Copy.date(sampleDate, timeOnly: false, language: lang).isEmpty)
            XCTAssertFalse(Copy.date(sampleDate, timeOnly: true, language: lang).isEmpty)
        }
    }

    func testSvgIconRegistryCountAndViewInit() {
        XCTAssertEqual(AppIcon.allCases.count, 59)
        let uniqueRawValues = Set(AppIcon.allCases.map(\.rawValue))
        XCTAssertEqual(uniqueRawValues.count, 59)

        for icon in AppIcon.allCases {
            XCTAssertFalse(icon.rawValue.isEmpty)
            XCTAssertEqual(icon.id, icon.rawValue)
            #if canImport(UIKit)
            XCTAssertNotNil(UIImage(named: icon.rawValue), "Missing SVG imageset for icon '\(icon.rawValue)'")
            #endif
            let viewA = SvgIconView(icon: icon, size: 18, color: .accentColor)
            let viewB = SvgIconView(icon)
            XCTAssertEqual(viewA.icon, icon)
            XCTAssertEqual(viewA.size, 18)
            XCTAssertEqual(viewB.size, 20)
        }
    }
}
