import SwiftUI
import Combine

private enum AppTab: String, CaseIterable {
    case home, statistics, settings
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .statistics: "calendar"
        case .settings: "gearshape.fill"
        }
    }
    var label: String {
        switch self {
        case .home: "Home"
        case .statistics: "Statistics"
        case .settings: "Settings"
        }
    }
}

struct AppShell: View {
    @EnvironmentObject private var activity: ActivityStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLanguage", store: ActivityStorage.defaults) private var language = "vi"
    @State private var selected: AppTab = .home
    private let pulse = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $selected) {
            DashboardView().tag(AppTab.home).toolbar(.hidden, for: .tabBar)
            StatisticsScreen().tag(AppTab.statistics).toolbar(.hidden, for: .tabBar)
            SettingsScreen().tag(AppTab.settings).toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar }
        .environment(\.locale, Locale(identifier: language))
        .onReceive(pulse) { _ in
            if scenePhase == .active { Task { await activity.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await activity.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in
            Task { await activity.refresh() }
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button { selected = tab } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 21, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .foregroundStyle(selected == tab ? .white : Color.secondary)
                        .background {
                            if selected == tab { Capsule().fill(TrackStyle.green) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Copy.text(tab.label))
                .accessibilityIdentifier("tab-\(tab.rawValue)")
                .accessibilityAddTraits(selected == tab ? [.isSelected] : [])
            }
        }
        .padding(7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .frame(maxWidth: 290)
        .padding(.horizontal, 32).padding(.top, 8).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}
