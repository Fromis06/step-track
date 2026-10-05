import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var activity: ActivityStore
    @Environment(\.openURL) private var openURL
    @State private var confirmDisconnect = false
    @AppStorage("appLanguage", store: ActivityStorage.defaults) private var language = "vi"

    var body: some View {
        NavigationStack {
            Form {
                Section(Copy.text("Language")) {
                    Picker(Copy.text("Language"), selection: $language) {
                        ForEach(AppLanguage.allCases) { item in Text(item.name).tag(item.rawValue) }
                    }
                    .pickerStyle(.menu).accessibilityIdentifier("languagePicker")
                }
                Section(Copy.text("Daily goal")) {
                    Text(Copy.format("%@ steps", Copy.number(activity.goal)))
                        .font(.largeTitle.bold()).foregroundStyle(TrackStyle.green)
                        .accessibilityIdentifier("dailyGoalValue")
                    Stepper(Copy.text("Adjust by 500 steps"), value: Binding(get: { activity.goal }, set: { activity.setGoal($0) }),
                            in: 500...50_000, step: 500)
                    HStack {
                        ForEach([5_000, 8_000, 10_000], id: \.self) { target in
                            Button(Copy.number(target)) { activity.setGoal(target) }
                                .buttonStyle(.bordered).frame(maxWidth: .infinity)
                                .accessibilityIdentifier("goal-\(target)")
                        }
                    }
                    Text(Copy.text("Changes apply to today and future days."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(Copy.text("Data source")) {
                    Label(activity.sourceName, systemImage: "iphone")
                    if !activity.enabled {
                        Button(Copy.text("Connect data")) { Task { await activity.connect() } }.disabled(activity.loading)
                    }
                    Button(Copy.text("Open Settings")) { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                }
                Section(Copy.text("History")) {
                    LabeledContent(Copy.text("Saved days"), value: Copy.number(activity.history.days.count))
                    Text(Copy.text("History stays on this iPhone. Open the app every few days to avoid gaps."))
                        .font(.footnote).foregroundStyle(.secondary)
                    if let message = activity.historyMessage {
                        Text(Copy.text(message)).font(.footnote).foregroundStyle(.orange)
                    }
                    Button(Copy.text("Disconnect and clear saved data"), role: .destructive) { confirmDisconnect = true }
                }
                Section("Step Track") {
                    Text(Copy.text("Based on Steps by Brittany Rima & contributors · MIT. Independent version."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(Copy.text("Settings"))
            .contentMargins(.bottom, 86, for: .scrollContent)
            .confirmationDialog(Copy.text("Clear all saved history and disconnect?"), isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button(Copy.text("Disconnect and clear"), role: .destructive) { activity.disconnect() }
            }
        }
    }
}
