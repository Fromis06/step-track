import SwiftUI

@main
struct StepTrackApp: App {
    @StateObject private var activity = ActivityStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLanguage", store: ActivityStorage.defaults) private var language = "vi"

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(activity)
                .tint(TrackStyle.green)
                .environment(\.locale, locale)
                .task { await activity.resume() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await activity.resume() } }
                }
        }
    }

    private var locale: Locale {
        // Reading the storage property makes SwiftUI update the view tree on language changes.
        _ = language
        return Copy.locale
    }
}
