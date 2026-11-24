import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var activity: ActivityStore
    @EnvironmentObject private var fitness: FitnessStore
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Copy.storageKey, store: ActivityStorage.defaults) private var language = "en"

    @State private var confirmReset = false
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument = BackupJSONDocument()
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var locale: Locale {
        _ = language
        return Copy.locale
    }

    private var effectiveScheme: ColorScheme {
        themeManager.preferredColorScheme ?? colorScheme
    }

    private var signingStatus: SigningStatus {
        SigningStatus.current
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceAndLanguageSection
                bodyProfileSection
                dailyGoalSection
                stepSourceAndSigningSection
                backupAndResetSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(palette.bgCanvas)
            .navigationTitle(Copy.text("Settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.text("Done")) {
                        dismiss()
                    }
                }
            }
            .environment(\.locale, locale)
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "StepTrack-Backup"
            ) { result in
                switch result {
                case .success:
                    setStatus(Copy.text("Backup exported"), isError: false)
                case .failure(let error):
                    if let message = localizedErrorMessage(for: error, fallbackKey: "Export failed") {
                        setStatus(message, isError: true)
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer {
                        if scoped { url.stopAccessingSecurityScopedResource() }
                    }
                    do {
                        let data = try Data(contentsOf: url)
                        try fitness.importBackupData(data, activityStore: activity)
                        setStatus(Copy.text("Backup imported"), isError: false)
                    } catch {
                        if let message = localizedErrorMessage(for: error, fallbackKey: "Could not read backup file") {
                            setStatus(message, isError: true)
                        }
                    }
                case .failure(let error):
                    if let message = localizedErrorMessage(for: error, fallbackKey: "Import failed") {
                        setStatus(message, isError: true)
                    }
                }
            }
            .confirmationDialog(Copy.text("Reset local data?"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(Copy.text("Reset"), role: .destructive) {
                    do {
                        try fitness.resetAllData(activityStore: activity)
                        setStatus(Copy.text("Reset complete"), isError: false)
                    } catch {
                        if let message = localizedErrorMessage(for: error, fallbackKey: "Could not save local data") {
                            setStatus(message, isError: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var appearanceAndLanguageSection: some View {
        Section(Copy.text("Appearance")) {
            Picker(Copy.text("Appearance"), selection: $themeManager.appearance) {
                ForEach(AppAppearance.allCases) { mode in
                    Text(Copy.text(mode.localizationKey)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("appearancePicker")

            Picker(Copy.text("Theme"), selection: $themeManager.theme) {
                ForEach(AppTheme.allCases) { item in
                    Text(Copy.text(item.localizationKey)).tag(item)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("themePicker")

            HStack(spacing: 12) {
                ForEach(AppTheme.allCases) { item in
                    let swatchColor = item.palette(for: effectiveScheme).accent
                    Button {
                        themeManager.theme = item
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(swatchColor)
                                .frame(width: 14, height: 14)
                                .overlay {
                                    if themeManager.theme == item {
                                        Circle().strokeBorder(palette.textPrimary, lineWidth: 1.5)
                                    }
                                }
                            Text(Copy.text(item.localizationKey))
                                .font(.caption2.weight(themeManager.theme == item ? .bold : .regular))
                                .foregroundStyle(themeManager.theme == item ? palette.textPrimary : palette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            themeManager.theme == item ? palette.accentMuted : palette.bgCardElevated,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker(Copy.text("Language"), selection: $language) {
                ForEach(AppLanguage.allCases) { item in
                    Text(item.name).tag(item.rawValue)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("languagePicker")
        }
    }

    private var bodyProfileSection: some View {
        let profile = fitness.profile
        return Section(Copy.text("Body Profile")) {
            Stepper(
                value: Binding(
                    get: { fitness.profile.heightCm },
                    set: { newValue in
                        var updated = fitness.profile
                        updated.heightCm = min(250, max(100, newValue))
                        fitness.updateProfile(updated)
                    }
                ),
                in: 100...250,
                step: 1
            ) {
                LabeledContent(
                    Copy.text("Height"),
                    value: "\(Copy.number(Int(profile.heightCm.rounded()))) \(Copy.text("cm"))"
                )
            }

            Stepper(
                value: Binding(
                    get: { fitness.profile.weightKg },
                    set: { newValue in
                        var updated = fitness.profile
                        updated.weightKg = min(400, max(20, newValue))
                        fitness.updateProfile(updated)
                    }
                ),
                in: 20...400,
                step: 0.5
            ) {
                LabeledContent(
                    Copy.text("Weight"),
                    value: Copy.format("%@ kg", Copy.decimal(profile.weightKg, digits: 1))
                )
            }

            Stepper(
                value: Binding(
                    get: { fitness.profile.age },
                    set: { newValue in
                        var updated = fitness.profile
                        updated.age = min(120, max(12, newValue))
                        fitness.updateProfile(updated)
                    }
                ),
                in: 12...120,
                step: 1
            ) {
                LabeledContent(Copy.text("Age"), value: Copy.number(profile.age))
            }

            Picker(
                Copy.text("Sex"),
                selection: Binding(
                    get: { fitness.profile.sex },
                    set: { newValue in
                        var updated = fitness.profile
                        updated.sex = newValue
                        fitness.updateProfile(updated)
                    }
                )
            ) {
                ForEach(BiologicalSex.allCases) { sex in
                    Text(Copy.text(sex.localizationKey)).tag(sex)
                }
            }

            Picker(
                Copy.text("Activity Level"),
                selection: Binding(
                    get: { fitness.profile.activityLevel },
                    set: { newValue in
                        var updated = fitness.profile
                        updated.activityLevel = newValue
                        fitness.updateProfile(updated)
                    }
                )
            ) {
                ForEach(ActivityLevel.allCases) { level in
                    Text(Copy.text(level.localizationKey)).tag(level)
                }
            }

            LabeledContent(
                Copy.text("BMR"),
                value: Copy.format("%@ kcal", Copy.number(Int(profile.bmr.rounded())))
            )
            LabeledContent(
                Copy.text("TDEE"),
                value: Copy.format("%@ kcal", Copy.number(Int(profile.tdee.rounded())))
            )
        }
    }

    private var dailyGoalSection: some View {
        Section(Copy.text("Daily goal")) {
            Text(Copy.format("%@ steps", Copy.number(activity.goal)))
                .font(.largeTitle.bold())
                .foregroundStyle(palette.accent)
                .accessibilityIdentifier("dailyGoalValue")

            Stepper(
                Copy.text("Step increment"),
                value: Binding(
                    get: { activity.goal },
                    set: { applyDailyStepGoal($0) }
                ),
                in: 500...50_000,
                step: 500
            )

            HStack {
                ForEach([5_000, 8_000, 10_000], id: \.self) { target in
                    Button(Copy.number(target)) {
                        applyDailyStepGoal(target)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("goal-\(target)")
                }
            }
        }
    }

    private var stepSourceAndSigningSection: some View {
        Section(Copy.text("Data source")) {
            HStack(spacing: 10) {
                SvgIconView(
                    icon: activity.isUsingManualFallback ? .pencil : (ActivityStore.motionOnly ? .smartphone : .heart),
                    size: 18,
                    color: palette.accent
                )
                Text(activity.sourceName)
                Spacer()
                Text(Copy.text(activity.enabled ? (activity.isUsingManualFallback ? "Manual entry" : "Active") : "Local only"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(activity.enabled ? palette.success : palette.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(palette.bgCardElevated, in: Capsule())
            }

            if ActivityStore.motionOnly || activity.isUsingManualFallback {
                LabeledContent(Copy.text("Fallback"), value: Copy.text("Manual entry"))
            }

            if !activity.enabled {
                Button(Copy.text("Connect data")) {
                    Task { await activity.connect() }
                }
                .disabled(activity.loading)
            }

            if let message = activity.message {
                Text(Copy.text(message))
                    .font(.footnote)
                    .foregroundStyle(palette.warning)
            }

            Button(Copy.text("Open Settings")) {
                #if canImport(UIKit)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
                #endif
            }

            LabeledContent(Copy.text("Signing Status")) {
                Text(Copy.text(ActivityStore.motionOnly ? "Local only" : "Connection check"))
                    .foregroundStyle(palette.textSecondary)
            }

            LabeledContent(Copy.text("HealthKit"), value: Copy.text(healthKitStatusKey))
            LabeledContent(
                Copy.text("Widget"),
                value: Copy.text(signingStatus.widgetIncluded ? "Included in app" : "Removed from app")
            )
            LabeledContent(
                Copy.text("Shared Container"),
                value: Copy.text(signingStatus.sharedContainerAvailable ? "Accessible" : "Unavailable")
            )
        }
    }

    private var backupAndResetSection: some View {
        Section(Copy.text("Backup")) {
            Button {
                do {
                    let data = try fitness.exportBackupData(activityStore: activity)
                    exportDocument = BackupJSONDocument(data: data)
                    showExporter = true
                } catch {
                    if let message = localizedErrorMessage(for: error, fallbackKey: "Export failed") {
                        setStatus(message, isError: true)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    SvgIconView(icon: .download, size: 17, color: palette.accent)
                    Text(Copy.text("Export Backup"))
                }
            }

            Button {
                showImporter = true
            } label: {
                HStack(spacing: 8) {
                    SvgIconView(icon: .upload, size: 17, color: palette.accent)
                    Text(Copy.text("Import Backup"))
                }
            }

            if let statusMessage {
                HStack(spacing: 8) {
                    SvgIconView(
                        icon: statusIsError ? .alertCircle : .checkCircle2,
                        size: 16,
                        color: statusIsError ? palette.danger : palette.success
                    )
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(statusIsError ? palette.danger : palette.success)
                }
            }

            if let historyMessage = activity.historyMessage {
                Text(Copy.text(historyMessage))
                    .font(.footnote)
                    .foregroundStyle(palette.warning)
            }

            Button(role: .destructive) {
                confirmReset = true
            } label: {
                HStack(spacing: 8) {
                    SvgIconView(icon: .trash2, size: 17, color: palette.danger)
                    Text(Copy.text("Reset local data"))
                }
            }
        }
    }

    private var aboutSection: some View {
        Section(Copy.text("About")) {
            LabeledContent(Copy.text("Saved days"), value: Copy.number(activity.history.days.count))
            LabeledContent(Copy.text("Step Track"), value: Copy.text("MIT License"))
        }
    }

    // MARK: - Helpers

    private var healthKitStatusKey: String {
        switch signingStatus.healthKitInProfile {
        case .some(true):
            return "In signing profile"
        case .some(false):
            return "Missing from signing profile"
        case .none:
            return "Profile not readable"
        }
    }

    private func applyDailyStepGoal(_ target: Int) {
        let clamped = max(500, min(50_000, target))
        activity.setGoal(clamped)
        var updated = fitness.goals
        updated.dailySteps = clamped
        fitness.updateGoals(updated)
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    private func localizedErrorMessage(for error: Error, fallbackKey: String) -> String? {
        if error is CancellationError { return nil }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return nil
        }
        if let storeError = error as? LocalStoreError {
            switch storeError {
            case .corruptBackupData:
                return Copy.text("Invalid backup file")
            case .unsupportedBackupVersion:
                return Copy.text("Unsupported backup version")
            case .writeFailed:
                return Copy.text("Could not save local data")
            }
        }
        return Copy.text(fallbackKey)
    }
}

private struct BackupJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
