import SwiftUI
import Charts
import Combine
import WidgetKit

enum TrackStyle {
    static let green = Color(red: 0.17, green: 0.55, blue: 0.36)
    static let mint = Color(red: 0.70, green: 0.91, blue: 0.48)
}

struct DashboardView: View {
    @EnvironmentObject private var activity: ActivityStore
    @State private var showSettings = false
    @State private var period = 7
    @AppStorage("appLanguage", store: ActivityStorage.defaults) private var language = "vi"
    private let pulse = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var records: [ActivityDay] { Array(activity.snapshot.days.suffix(period)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    if !activity.enabled { connectionCard }
                    if let message = activity.message {
                        Label(Copy.text(message), systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading).card()
                    }
                    progressCard
                    metrics
                    historyCard
                    footer
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await activity.refresh() }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
            .environment(\.locale, Locale(identifier: language))
            .onReceive(pulse) { _ in Task { await activity.refresh() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                Task { await activity.refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in
                Task { await activity.refresh() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Copy.locale)))
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(Copy.text("Today"))
                    .font(.title2.weight(.bold)).tracking(-0.7)
            }
            Spacer(minLength: 10)
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3).frame(width: 46, height: 46)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .accessibilityLabel(Copy.text("Settings and goal"))
            .accessibilityIdentifier("settingsButton")
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(ActivityStore.motionOnly ? Copy.text("iPhone steps") : Copy.text("Connect to Health"), systemImage: "heart.fill")
                .font(.headline)
            Text(ActivityStore.motionOnly
                 ? Copy.text("Read steps from your iPhone.")
                 : Copy.text("Read your steps and distance."))
                .font(.subheadline).foregroundStyle(.secondary)
            Button { Task { await activity.connect() } } label: {
                HStack {
                    if activity.loading { ProgressView().tint(.white) }
                    Text(activity.loading ? Copy.text("Connecting…") : Copy.text("Connect")).fontWeight(.semibold)
                    Image(systemName: "arrow.up.right")
                }.frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent).disabled(activity.loading)
        }.card()
    }

    private var progressCard: some View {
        VStack(spacing: 20) {
            HStack {
                Label(Copy.text("TODAY"), systemImage: "figure.walk")
                    .font(.caption.weight(.bold)).tracking(2)
                Spacer()
                Text(Copy.format("%@%% of goal", Copy.number(Int(activity.progress * 100))))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            ZStack {
                Circle().stroke(.white.opacity(0.10), lineWidth: 17)
                Circle().trim(from: 0, to: activity.progress)
                    .stroke(AngularGradient(colors: [TrackStyle.green, TrackStyle.mint], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: 17, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Image(systemName: "figure.walk").font(.title).foregroundStyle(TrackStyle.mint)
                    Text(activity.enabled && activity.snapshot.updatedAt != .distantPast ? Copy.number(activity.todaySteps) : "—")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .contentTransition(.numericText())
                    Text(Copy.text("steps")).font(.subheadline).foregroundStyle(.white.opacity(0.65))
                }.padding(30)
            }
            .frame(width: 242, height: 242).padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.format("%@ steps today, goal %@", Copy.number(activity.todaySteps), Copy.number(activity.goal)))
            VStack(spacing: 6) {
                Text(activity.todaySteps >= activity.goal ? Copy.text("Goal reached") : Copy.format("Goal: %@ steps", Copy.number(activity.goal)))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }
        }
        .foregroundStyle(.white).padding(24).frame(maxWidth: .infinity)
        .background(Color(red: 0.065, green: 0.19, blue: 0.145), in: RoundedRectangle(cornerRadius: 30))
    }

    private var metrics: some View {
        HStack(spacing: 14) {
            metric(Copy.text("Distance"), symbol: "point.bottomleft.forward.to.point.topright.scurvepath",
                   value: activity.todayDistance.map { Copy.decimal($0 / 1000) } ?? "—",
                   unit: Copy.text("km today"))
            metric(Copy.text("Remaining"), symbol: "flag.checkered",
                   value: Copy.number(max(0, activity.goal - activity.todaySteps)), unit: Copy.text("steps to goal"))
        }
    }

    private func metric(_ title: String, symbol: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(TrackStyle.green).font(.title3)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.text("Activity")).font(.headline)
                }
                Spacer()
                Image(systemName: "chart.bar.xaxis").foregroundStyle(TrackStyle.green)
            }
            if !ActivityStore.motionOnly {
                Picker(Copy.text("Period"), selection: $period) {
                    Text(Copy.text("7 days")).tag(7)
                    Text(Copy.text("30 days")).tag(30)
                }.pickerStyle(.segmented)
            }
            if records.isEmpty {
                ContentUnavailableView(Copy.text("No data yet"), systemImage: "figure.walk",
                                       description: Text(""))
            } else {
                Chart(records) { record in
                    BarMark(x: .value(Copy.text("Day"), record.date, unit: .day), y: .value(Copy.text("Steps"), record.steps))
                        .cornerRadius(5)
                        .foregroundStyle(Calendar.current.isDateInToday(record.date) ? TrackStyle.green : TrackStyle.green.opacity(0.3))
                        .accessibilityLabel(record.date.formatted(.dateTime.day().month().locale(Copy.locale)))
                        .accessibilityValue(Copy.format("%@ steps", Copy.number(record.steps)))
                    RuleMark(y: .value(Copy.text("Goal"), activity.goal))
                        .foregroundStyle(TrackStyle.green.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: period == 7 ? 1 : 7)) {
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
                .frame(height: 170)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Copy.text("DAILY AVERAGE")).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(Copy.number(records.reduce(0) { $0 + $1.steps } / max(1, records.count)))
                            .font(.title2.weight(.bold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(Copy.text("GOAL DAYS")).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text("\(records.filter { $0.steps >= activity.goal }.count) / \(records.count)")
                            .font(.title2.weight(.bold)).foregroundStyle(TrackStyle.green)
                    }
                }
            }
        }.card()
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Label(activity.sourceName, systemImage: ActivityStore.motionOnly ? "iphone" : "heart.fill")
                .font(.caption.weight(.medium)).foregroundStyle(TrackStyle.green)
            if activity.loading {
                ProgressView(Copy.text("Updating…")).font(.caption)
            } else if activity.snapshot.updatedAt != .distantPast {
                Text(Copy.format("Updated %@", Copy.date(activity.snapshot.updatedAt)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if activity.enabled && !ActivityStore.motionOnly && activity.todaySteps == 0 {
                Text(Copy.text("No steps · check Health access"))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }.padding(.bottom, 12)
    }
}

private struct SettingsScreen: View {
    @EnvironmentObject private var activity: ActivityStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmDisconnect = false
    @AppStorage("appLanguage", store: ActivityStorage.defaults) private var language = "vi"

    var body: some View {
        NavigationStack {
            Form {
                Section(Copy.text("Language")) {
                    Picker(Copy.text("Language"), selection: $language) {
                        ForEach(AppLanguage.allCases) { item in
                            Text(item.name).tag(item.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("languagePicker")
                }
                Section(Copy.text("Daily goal")) {
                    Text(Copy.format("%@ steps", Copy.number(activity.goal))).font(.largeTitle.bold()).foregroundStyle(TrackStyle.green)
                    Stepper(Copy.text("Adjust by 500 steps"), value: $activity.goal, in: 500...50_000, step: 500)
                    HStack {
                        ForEach([6_000, 8_000, 10_000], id: \.self) { goal in
                            Button(Copy.number(goal)) { activity.goal = goal }
                                .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        }
                    }
                }
                Section(Copy.text("Data source")) {
                    Label(activity.sourceName, systemImage: "heart.text.square")
                    if !activity.enabled {
                        Button(Copy.text("Connect data")) { Task { await activity.connect() } }.disabled(activity.loading)
                    }
                    Text(ActivityStore.motionOnly
                         ? Copy.text("iPhone sensor · 7 days. Does not include Apple Watch or sync with Health.")
                         : Copy.text("Read-only. Manage access in Health → profile → Apps → Step Track."))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(Copy.text("Open Settings")) { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                }
                Section(Copy.text("Widgets")) {
                    Text(ActivityStore.motionOnly
                         ? Copy.text("Available in the Health build with valid App Groups signing.")
                         : Copy.text("Hold Home Screen → Edit → Add Widget → Step Track."))
                    if !ActivityStore.motionOnly && ActivityStorage.sharedDefaults == nil {
                        Label(Copy.text("Shared data unavailable. Check App Groups signing."), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Text(Copy.text("iOS controls refresh timing. Updates are not instant."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(Copy.text("Privacy")) {
                    Text(Copy.text("No account, ads, or health data uploads."))
                    if activity.enabled {
                        Button(Copy.text("Disconnect and clear saved data"), role: .destructive) { confirmDisconnect = true }
                    }
                }
                if !ActivityStore.motionOnly {
                    Section {
                        DisclosureGroup(Copy.text("Connection check")) {
                            let status = SigningStatus.current
                            LabeledContent("HealthKit", value: Copy.text(status.healthKitInProfile.map { $0 ? "In signing profile" : "Missing from signing profile" } ?? "Profile not readable"))
                            LabeledContent(Copy.text("Widgets"), value: Copy.text(status.widgetIncluded ? "Included in app" : "Removed from app"))
                            LabeledContent("App Group", value: Copy.text(status.sharedContainerAvailable ? "Accessible" : "Unavailable"))
                            if let error = activity.connectionDiagnostic {
                                Text(error).font(.caption).textSelection(.enabled)
                            }
                            ShareLink(item: diagnosticReport(status)) {
                                Label(Copy.text("Share diagnostics"), systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                Section("Step Track") {
                    Text(Copy.text("Based on Steps by Brittany Rima & contributors · MIT. Independent version."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(Copy.text("Settings"))
            .onChange(of: language) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(Copy.text("Done")) { dismiss() } } }
            .confirmationDialog(Copy.text("Disconnect and clear saved data? Your original Health data stays intact."), isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button(Copy.text("Disconnect and clear"), role: .destructive) { activity.disconnect() }
            }
        }
    }

    private func diagnosticReport(_ status: SigningStatus) -> String {
        [
            "Step Track \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")",
            "Bundle: \(Bundle.main.bundleIdentifier ?? "?")",
            "HealthKit in profile: \(status.healthKitInProfile.map { String($0) } ?? "unknown")",
            "Widget included: \(status.widgetIncluded)",
            "App Group accessible: \(status.sharedContainerAvailable)",
            "Connection error: \(activity.connectionDiagnostic ?? "none")"
        ].joined(separator: "\n")
    }
}

private extension View {
    func card() -> some View {
        padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}
