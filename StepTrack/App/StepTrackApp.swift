import SwiftUI

@main
struct StepTrackApp: App {
    @StateObject private var activity = ActivityStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(activity)
                .tint(TrackStyle.green)
                .environment(\.locale, Locale(identifier: "vi_VN"))
                .task { await activity.resume() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await activity.resume() } }
                }
        }
    }
}
