import SwiftUI
import Combine

private enum AppTab: String, CaseIterable, Identifiable {
    case today
    case train
    case body
    case health
    case stats

    var id: String { rawValue }

    var icon: AppIcon {
        switch self {
        case .today: .home
        case .train: .dumbbell
        case .body: .personStanding
        case .health: .heartPulse
        case .stats: .barChart3
        }
    }

    var labelKey: String {
        switch self {
        case .today: "Today"
        case .train: "Train"
        case .body: "Body"
        case .health: "Health"
        case .stats: "Stats"
        }
    }
}

struct AppShell: View {
    @EnvironmentObject private var activity: ActivityStore
    @EnvironmentObject private var fitness: FitnessStore
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.themePalette) private var palette
    @AppStorage(Copy.storageKey, store: ActivityStorage.defaults) private var language = "en"

    @State private var selected: AppTab = .today
    @State private var showingSettings = false

    private let pulse = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var locale: Locale {
        _ = language
        return Copy.locale
    }

    var body: some View {
        TabView(selection: $selected) {
            TodayView()
                .tag(AppTab.today)
                .toolbar(.hidden, for: .tabBar)
            TrainView()
                .tag(AppTab.train)
                .toolbar(.hidden, for: .tabBar)
            BodyLibraryView()
                .tag(AppTab.body)
                .toolbar(.hidden, for: .tabBar)
            HealthView()
                .tag(AppTab.health)
                .toolbar(.hidden, for: .tabBar)
            AnalyticsView()
                .tag(AppTab.stats)
                .toolbar(.hidden, for: .tabBar)
        }
        .overlay(alignment: .topTrailing) {
            settingsTrigger
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomOverlay
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(activity)
                .environmentObject(fitness)
                .environmentObject(themeManager)
                .environment(\.themePalette, palette)
                .environment(\.locale, locale)
                .tint(palette.accent)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .environment(\.locale, locale)
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

    private var settingsTrigger: some View {
        Button {
            showingSettings = true
        } label: {
            SvgIconView(icon: .settings, size: 19, color: palette.textPrimary)
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(palette.borderSubtle, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .padding(.trailing, 20)
        .accessibilityLabel(Copy.text("Settings"))
        .accessibilityIdentifier("open-settings")
    }

    private var bottomOverlay: some View {
        VStack(spacing: 8) {
            if fitness.isRestTimerRunning {
                restTimerPill
            }
            navigationBar
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    private var restTimerPill: some View {
        HStack(spacing: 10) {
            SvgIconView(icon: .timer, size: 16, color: palette.accentOnHero)

            VStack(alignment: .leading, spacing: 1) {
                Text(Copy.text("Rest Timer"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(formattedRestCountdown(fitness.restRemainingSeconds))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 4)

            Button {
                fitness.adjustRestTimer(delta: -15)
            } label: {
                HStack(spacing: 2) {
                    SvgIconView(icon: .minus, size: 12, color: .white)
                    Text("15s")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                fitness.adjustRestTimer(delta: 15)
            } label: {
                HStack(spacing: 2) {
                    SvgIconView(icon: .plus, size: 12, color: .white)
                    Text("15s")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                fitness.stopRestTimer()
            } label: {
                HStack(spacing: 4) {
                    SvgIconView(icon: .x, size: 12, color: palette.bgHero)
                    Text(Copy.text("Skip"))
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(palette.bgHero)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(palette.accentOnHero, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(palette.bgHero, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .padding(.horizontal, 20)
        .accessibilityIdentifier("globalRestTimerPill")
    }

    private var navigationBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selected == tab
                Button {
                    selected = tab
                } label: {
                    VStack(spacing: 3) {
                        SvgIconView(
                            icon: tab.icon,
                            size: 19,
                            color: isSelected ? .white : palette.textSecondary
                        )
                        Text(Copy.text(tab.labelKey))
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .white : palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background {
                        if isSelected {
                            Capsule().fill(palette.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Copy.text(tab.labelKey))
                .accessibilityIdentifier("tab-\(tab.rawValue)")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.borderSubtle, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 16)
    }

    private func formattedRestCountdown(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let mins = clamped / 60
        let secs = clamped % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
