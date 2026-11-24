import SwiftUI

@main
struct StepTrackApp: App {
    @StateObject private var activity: ActivityStore
    @StateObject private var fitness: FitnessStore
    @StateObject private var themeManager: ThemeManager

    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        Self.applyDebugLaunchArguments(args)

        if args.contains("--ui-fixture") {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("StepTrackFixture-\(UUID().uuidString)", isDirectory: true)
            let activityStore = ActivityStore()
            let fitnessStore = FitnessStore(localStore: LocalStore(directory: tempDir), isFixture: true)
            FixtureData.seed(fitness: fitnessStore, activity: activityStore)
            try? FileManager.default.removeItem(at: tempDir)
            _activity = StateObject(wrappedValue: activityStore)
            _fitness = StateObject(wrappedValue: fitnessStore)
            _themeManager = StateObject(wrappedValue: ThemeManager())
            return
        }
        #endif

        _activity = StateObject(wrappedValue: ActivityStore())
        _fitness = StateObject(wrappedValue: FitnessStore())
        _themeManager = StateObject(wrappedValue: ThemeManager())
    }

    var body: some Scene {
        WindowGroup {
            StepTrackRootView()
                .environmentObject(activity)
                .environmentObject(fitness)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
    }

    #if DEBUG
    private static func applyDebugLaunchArguments(_ args: [String]) {
        if let rawLanguage = argumentValue(named: "--language", in: args),
           let parsedLanguage = AppLanguage(rawValue: rawLanguage) {
            ActivityStorage.defaults.set(parsedLanguage.rawValue, forKey: Copy.storageKey)
        }
        if let rawTheme = argumentValue(named: "--theme", in: args),
           let parsedTheme = AppTheme(rawValue: rawTheme) {
            ActivityStorage.defaults.set(parsedTheme.rawValue, forKey: ThemeManager.themeKey)
        }
        if let rawAppearance = argumentValue(named: "--appearance", in: args),
           let parsedAppearance = AppAppearance(rawValue: rawAppearance) {
            ActivityStorage.defaults.set(parsedAppearance.rawValue, forKey: ThemeManager.appearanceKey)
        }
    }

    private static func argumentValue(named flag: String, in args: [String]) -> String? {
        let prefix = "\(flag)="
        for (index, arg) in args.enumerated() {
            if arg.hasPrefix(prefix) {
                return String(arg.dropFirst(prefix.count))
            }
            if arg == flag, index + 1 < args.count {
                return args[index + 1]
            }
        }
        return nil
    }
    #endif
}

private struct StepTrackRootView: View {
    @EnvironmentObject private var activity: ActivityStore
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(Copy.storageKey, store: ActivityStorage.defaults) private var language = "en"

    var body: some View {
        let effectiveScheme = themeManager.preferredColorScheme ?? colorScheme
        let palette = themeManager.palette(for: effectiveScheme)

        AppShell()
            .environment(\.themePalette, palette)
            .tint(palette.accent)
            .environment(\.locale, locale)
            .task { await activity.resume() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await activity.resume() } }
            }
    }

    private var locale: Locale {
        _ = language
        return Copy.locale
    }
}
