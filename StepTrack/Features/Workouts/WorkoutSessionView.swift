import SwiftUI

struct WorkoutSessionView: View {
    @EnvironmentObject private var fitness: FitnessStore
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Copy.storageKey, store: ActivityStorage.defaults) private var language = "en"

    @State private var extraExerciseIDs: [String] = []
    @State private var showExercisePicker = false
    @State private var showDiscardConfirm = false
    @State private var showEmptyFinishConfirm = false

    init() {}

    private var locale: Locale {
        _ = language
        return Copy.locale
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = fitness.activeSession {
                    activeSessionContent(session)
                } else {
                    emptyLauncher
                }
            }
            .background(palette.bgCanvas)
            .environment(\.locale, locale)
            .sheet(isPresented: $showExercisePicker) {
                let existingIDs = Set(
                    (fitness.activeSession?.exercises.map(\.exerciseID) ?? []) + extraExerciseIDs
                )
                ExercisePickerSheet(excludedIDs: existingIDs) { exercise in
                    if !existingIDs.contains(exercise.id) {
                        extraExerciseIDs.append(exercise.id)
                    }
                }
            }
        }
    }

    private var emptyLauncher: some View {
        VStack(spacing: 18) {
            Spacer()
            SvgIconView(.dumbbell, size: 42, color: palette.accent)
            Text(Copy.text("No Workouts"))
                .font(.title3.weight(.bold))
                .foregroundStyle(palette.textPrimary)

            Button {
                fitness.startSession(from: fitness.todayAssignment)
            } label: {
                HStack(spacing: 8) {
                    SvgIconView(.play, size: 16, color: .white)
                    Text(Copy.text("Start Workout"))
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(palette.accent, in: Capsule())
            }

            Button(Copy.text("Close")) {
                dismiss()
            }
            .foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func activeSessionContent(_ session: WorkoutSession) -> some View {
        let stagedExercises = mergedExerciseItems(for: session)

        return ScrollView {
            VStack(spacing: 16) {
                sessionHeaderCard(session)
                restTimerCard
                ForEach(stagedExercises) { item in
                    ExerciseLoggerCard(
                        exerciseID: item.exerciseID,
                        exerciseName: item.exerciseName,
                        entry: item.entry
                    )
                }
                addExerciseFooter
            }
            .padding(16)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    showDiscardConfirm = true
                } label: {
                    HStack(spacing: 5) {
                        SvgIconView(.trash2, size: 15, color: palette.danger)
                        Text(Copy.text("Discard Workout"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(palette.danger)
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    if session.completedSetsCount == 0 {
                        showEmptyFinishConfirm = true
                    } else {
                        fitness.finishActiveSession()
                        fitness.stopRestTimer()
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 5) {
                        SvgIconView(.checkCircle2, size: 15, color: palette.accent)
                        Text(Copy.text("Finish Workout"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.accent)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            Copy.text("Discard Workout"),
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button(Copy.text("Discard Workout"), role: .destructive) {
                fitness.discardActiveSession()
                fitness.stopRestTimer()
                dismiss()
            }
            Button(Copy.text("Cancel"), role: .cancel) {}
        }
        .confirmationDialog(
            Copy.text("Empty Session"),
            isPresented: $showEmptyFinishConfirm,
            titleVisibility: .visible
        ) {
            Button(Copy.text("Finish Workout"), role: .destructive) {
                fitness.finishActiveSession()
                fitness.stopRestTimer()
                dismiss()
            }
            Button(Copy.text("Cancel"), role: .cancel) {}
        }
    }

    private func sessionHeaderCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    SvgIconView(session.split.icon, size: 18, color: palette.accentOnHero)
                    Text(Copy.text(session.title))
                        .font(.title3.weight(.bold))
                }
                Spacer()
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    let elapsed = max(0, Int(context.date.timeIntervalSince(session.startedAt)))
                    HStack(spacing: 6) {
                        SvgIconView(.clock, size: 14, color: palette.accentOnHero)
                        Text(Self.formatDuration(seconds: elapsed))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.14), in: Capsule())
                }
            }

            HStack(spacing: 10) {
                summaryPill(
                    icon: .layers,
                    text: Copy.format("%@ sets", Copy.number(session.completedSetsCount))
                )
                summaryPill(
                    icon: .dumbbell,
                    text: Copy.format("%@ kg", Copy.decimal(session.totalVolumeKg, digits: 0))
                )
                summaryPill(
                    icon: .trophy,
                    text: "\(Copy.number(session.personalRecordCount)) \(Copy.text("PR"))"
                )
            }
        }
        .heroSurface(palette: palette, cornerRadius: 24, padding: 18)
    }

    private func summaryPill(icon: AppIcon, text: String) -> some View {
        HStack(spacing: 5) {
            SvgIconView(icon, size: 13, color: palette.accentOnHero)
            Text(text)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.12), in: Capsule())
    }

    // MARK: - Integrated Rest Timer

    private var restTimerCard: some View {
        let progress: Double = {
            guard fitness.restTotalSeconds > 0 else { return 0 }
            return min(1.0, max(0.0, Double(fitness.restRemainingSeconds) / Double(fitness.restTotalSeconds)))
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(.timer, size: 18, color: palette.accent)
                    Text(Copy.text("Rest Timer"))
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                HStack(spacing: 6) {
                    restPresetButton(seconds: 60)
                    restPresetButton(seconds: 90)
                    restPresetButton(seconds: 120)
                }
            }

            if fitness.isRestTimerRunning || fitness.restRemainingSeconds > 0 {
                HStack(spacing: 12) {
                    Text(Self.formatDuration(seconds: fitness.restRemainingSeconds))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.accent)

                    Spacer()

                    Button {
                        fitness.adjustRestTimer(delta: -15)
                    } label: {
                        Text("-\(Copy.number(15))")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(palette.bgCardElevated, in: Capsule())
                    }

                    Button {
                        fitness.adjustRestTimer(delta: 15)
                    } label: {
                        Text("+\(Copy.number(15))")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(palette.bgCardElevated, in: Capsule())
                    }

                    Button {
                        fitness.stopRestTimer()
                    } label: {
                        Text(Copy.text("Skip"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.danger)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(palette.danger.opacity(0.14), in: Capsule())
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(palette.bgCardElevated)
                            .frame(height: 6)
                        Capsule()
                            .fill(palette.accent)
                            .frame(width: geo.size.width * progress, height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .cardSurface(palette: palette, cornerRadius: 20, padding: 16)
    }

    private func restPresetButton(seconds: Int) -> some View {
        Button {
            fitness.startRestTimer(seconds: seconds)
        } label: {
            Text(Self.formatDuration(seconds: seconds))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(palette.accentMuted, in: Capsule())
        }
    }

    // MARK: - Footer

    private var addExerciseFooter: some View {
        Button {
            showExercisePicker = true
        } label: {
            HStack(spacing: 8) {
                SvgIconView(.plus, size: 17, color: .white)
                Text(Copy.text("Add Exercise"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(palette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.bottom, 20)
    }

    // MARK: - Helpers

    private struct StagedExerciseItem: Identifiable {
        let exerciseID: String
        let exerciseName: String
        let entry: ExerciseSessionEntry?
        var id: String { exerciseID }
    }

    private func mergedExerciseItems(for session: WorkoutSession) -> [StagedExerciseItem] {
        var items = session.exercises.map { entry in
            StagedExerciseItem(
                exerciseID: entry.exerciseID,
                exerciseName: entry.exerciseName,
                entry: entry
            )
        }
        let loggedIDs = Set(session.exercises.map(\.exerciseID))
        let library = ExerciseLibraryLoader.shared
        for extraID in extraExerciseIDs where !loggedIDs.contains(extraID) {
            let name = library.exercise(id: extraID)?.displayName ?? extraID
            items.append(
                StagedExerciseItem(
                    exerciseID: extraID,
                    exerciseName: name,
                    entry: nil
                )
            )
        }
        return items
    }

    static func formatDuration(seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3_600
        let mins = (safe % 3_600) / 60
        let secs = safe % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Exercise Logger Card

private struct ExerciseLoggerCard: View {
    let exerciseID: String
    let exerciseName: String
    let entry: ExerciseSessionEntry?

    @EnvironmentObject private var fitness: FitnessStore
    @Environment(\.themePalette) private var palette

    @State private var weightText = "20.0"
    @State private var reps = 10
    @State private var useRPE = false
    @State private var rpeValue = 8.0
    @State private var didSeedInputs = false

    private var previousSets: [ExerciseSetLog] {
        fitness.previousSets(for: exerciseID)
    }

    private var bestE1RM: Double? {
        let historyBest = fitness.bestE1RM(for: exerciseID) ?? 0
        let currentBest = entry?.bestE1RM ?? 0
        let combined = max(historyBest, currentBest)
        return combined > 0 ? combined : nil
    }

    private var parsedWeightKg: Double? {
        let normalized = weightText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized),
              value.isFinite,
              value >= 0,
              value <= 2_000 else {
            return nil
        }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            if let entry, !entry.sets.isEmpty {
                loggedSetsSection(entry)
            }
            addSetComposer
        }
        .cardSurface(palette: palette, cornerRadius: 20, padding: 16)
        .onAppear {
            seedInitialValuesIfNeeded()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(exerciseName)
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if let best = bestE1RM {
                    HStack(spacing: 4) {
                        SvgIconView(.trophy, size: 12, color: palette.accent)
                        Text("\(Copy.text("Best e1RM")) \(Copy.format("%@ kg", Copy.decimal(best, digits: 1)))")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(palette.accent)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.accentMuted, in: Capsule())
                }
            }

            if !previousSets.isEmpty {
                HStack(spacing: 8) {
                    Text(Copy.text("Previous"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)

                    if let lastPrev = previousSets.last {
                        Text("\(Copy.format("%@ kg", Copy.decimal(lastPrev.weightKg, digits: 1))) x \(Copy.format("%@ reps", Copy.number(lastPrev.reps)))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(palette.textSecondary)
                    }

                    Spacer()

                    Button {
                        repeatLastSet()
                    } label: {
                        HStack(spacing: 4) {
                            SvgIconView(.refreshCw, size: 12, color: palette.accent)
                            Text(Copy.text("Repeat Last"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.accent)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(palette.accentMuted, in: Capsule())
                    }
                }
            }
        }
    }

    private func loggedSetsSection(_ entry: ExerciseSessionEntry) -> some View {
        VStack(spacing: 8) {
            ForEach(entry.sets) { setLog in
                HStack(spacing: 10) {
                    Button {
                        fitness.toggleSetCompletion(exerciseEntryID: entry.id, setID: setLog.id)
                    } label: {
                        SvgIconView(
                            setLog.isCompleted ? .checkCircle2 : .circle,
                            size: 20,
                            color: setLog.isCompleted ? palette.success : palette.textSecondary
                        )
                    }

                    Text("\(Copy.text("Set")) \(Copy.number(setLog.setNumber))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 46, alignment: .leading)

                    Text(Copy.format("%@ kg", Copy.decimal(setLog.weightKg, digits: 1)))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)

                    Text("x \(Copy.format("%@ reps", Copy.number(setLog.reps)))")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)

                    if let rpe = setLog.rpe {
                        Text("\(Copy.text("RPE")) \(Copy.decimal(rpe, digits: 1))")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(palette.bgCardElevated, in: Capsule())
                    }

                    Spacer()

                    if setLog.isPersonalRecord {
                        HStack(spacing: 3) {
                            SvgIconView(.trophy, size: 12, color: palette.warning)
                            Text(Copy.text("PR"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(palette.warning)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(palette.warning.opacity(0.16), in: Capsule())
                    } else if setLog.estimated1RM > 0 {
                        Text("\(Copy.text("e1RM")) \(Copy.decimal(setLog.estimated1RM, digits: 1))")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(palette.textSecondary)
                    }

                    Button {
                        fitness.deleteSet(exerciseEntryID: entry.id, setID: setLog.id)
                    } label: {
                        SvgIconView(.trash2, size: 15, color: palette.textSecondary)
                    }
                    .accessibilityLabel(Copy.text("Delete"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var addSetComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.text("Weight (kg)"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                    HStack(spacing: 6) {
                        TextField("0.0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(Copy.text("kg"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.text("Reps"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                    HStack(spacing: 6) {
                        Button {
                            reps = max(1, reps - 1)
                        } label: {
                            SvgIconView(.minus, size: 14, color: palette.textPrimary)
                                .padding(8)
                                .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        Text(Copy.number(reps))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .frame(minWidth: 28)
                        Button {
                            reps = min(200, reps + 1)
                        } label: {
                            SvgIconView(.plus, size: 14, color: palette.textPrimary)
                                .padding(8)
                                .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                weightStepChip(delta: -2.5, label: "-2.5")
                weightStepChip(delta: 2.5, label: "+2.5")
                weightStepChip(delta: 5.0, label: "+5")

                Spacer()

                Button {
                    useRPE.toggle()
                } label: {
                    Text(useRPE ? "\(Copy.text("RPE")) \(Copy.decimal(rpeValue, digits: 1))" : Copy.text("RPE"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(useRPE ? .white : palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            useRPE ? palette.accent : palette.bgCardElevated,
                            in: Capsule()
                        )
                }
            }

            if useRPE {
                HStack(spacing: 10) {
                    Text(Copy.text("RPE"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                    Slider(value: $rpeValue, in: 6.0...10.0, step: 0.5)
                    Text(Copy.decimal(rpeValue, digits: 1))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.accent)
                }
            }

            Button {
                guard let weight = parsedWeightKg, reps > 0 else { return }
                fitness.logSet(
                    exerciseID: exerciseID,
                    exerciseName: exerciseName,
                    weightKg: weight,
                    reps: reps,
                    rpe: useRPE ? rpeValue : nil
                )
            } label: {
                HStack(spacing: 6) {
                    SvgIconView(.plus, size: 15, color: .white)
                    Text(Copy.text("Add Set"))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    parsedWeightKg != nil && reps > 0 ? palette.accent : palette.textSecondary.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .disabled(parsedWeightKg == nil || reps <= 0)
        }
    }

    private func weightStepChip(delta: Double, label: String) -> some View {
        Button {
            let current = parsedWeightKg ?? 0
            let next = min(2_000, max(0, current + delta))
            weightText = String(format: "%.1f", next)
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(palette.accentMuted, in: Capsule())
        }
    }

    private func seedInitialValuesIfNeeded() {
        guard !didSeedInputs else { return }
        didSeedInputs = true
        if let lastInSession = entry?.sets.last {
            weightText = String(format: "%.1f", lastInSession.weightKg)
            reps = max(1, lastInSession.reps)
            if let rpe = lastInSession.rpe {
                useRPE = true
                rpeValue = rpe
            }
        } else if let lastPrev = previousSets.last {
            weightText = String(format: "%.1f", lastPrev.weightKg)
            reps = max(1, lastPrev.reps)
            if let rpe = lastPrev.rpe {
                useRPE = true
                rpeValue = rpe
            }
        }
    }

    private func repeatLastSet() {
        guard !previousSets.isEmpty else { return }
        let idx = min(entry?.sets.count ?? 0, previousSets.count - 1)
        let target = previousSets[idx]
        weightText = String(format: "%.1f", target.weightKg)
        reps = max(1, target.reps)
        if let rpe = target.rpe {
            useRPE = true
            rpeValue = rpe
        }
        fitness.logSet(
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            weightKg: target.weightKg,
            reps: max(1, target.reps),
            rpe: target.rpe
        )
    }
}
