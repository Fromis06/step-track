import SwiftUI
import Charts

struct ExerciseDetailView: View {
    let exercise: ExerciseRecord

    @EnvironmentObject private var fitness: FitnessStore
    @Environment(\.themePalette) private var palette
    @AppStorage(Copy.storageKey, store: ActivityStorage.defaults) private var language = "en"

    @State private var timeframe: DashboardTimeframe = .month
    @State private var showSplitSheet = false
    @State private var showLogSetSheet = false
    @State private var assignedWeekday: Weekday?
    @State private var loggedSetWasPR = false
    @State private var showLoggedConfirmation = false

    private var locale: Locale {
        _ = language
        return Copy.locale
    }

    private var progressPoints: [WeightProgressPoint] {
        fitness.weightProgression(for: exercise.id, timeframe: timeframe)
    }

    private var bestE1RM: Double? {
        let historyBest = fitness.bestE1RM(for: exercise.id) ?? 0
        let activeBest = fitness.activeSession?.exercises
            .filter { $0.exerciseID == exercise.id }
            .map(\.bestE1RM)
            .max() ?? 0
        let combined = max(historyBest, activeBest)
        return combined > 0 ? combined : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerCard
                actionButtonsRow
                feedbackBanner
                progressionCard
                instructionsCard
            }
            .padding(20)
        }
        .background(palette.bgCanvas)
        .contentMargins(.bottom, 86, for: .scrollContent)
        .navigationTitle(exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, locale)
        .sheet(isPresented: $showSplitSheet) {
            AddToSplitSheet(exercise: exercise) { weekday in
                let current = fitness.weeklySplit.schedule(for: weekday)
                let nextSplit: SplitType = current.split.isRest ? .custom : current.split
                let nextTitle = current.split.isRest ? "" : current.title
                var nextGroups = current.muscleGroups
                if !nextGroups.contains(exercise.bodyPart) {
                    nextGroups.append(exercise.bodyPart)
                }
                var nextIDs = current.exerciseIDs
                if !nextIDs.contains(exercise.id) {
                    nextIDs.append(exercise.id)
                }
                fitness.assignDay(
                    weekday,
                    split: nextSplit,
                    title: nextTitle,
                    muscleGroups: nextGroups,
                    exerciseIDs: nextIDs
                )
                assignedWeekday = weekday
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showLogSetSheet) {
            QuickLogSetSheet(exercise: exercise) { weightKg, reps, rpe in
                let priorBest = bestE1RM
                let isPR = PersonalRecordDetector.isPersonalRecord(
                    weightKg: weightKg,
                    reps: reps,
                    priorBestE1RM: priorBest
                )
                fitness.logSet(
                    exerciseID: exercise.id,
                    exerciseName: exercise.displayName,
                    weightKg: weightKg,
                    reps: reps,
                    rpe: rpe
                )
                loggedSetWasPR = isPR
                showLoggedConfirmation = true
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Header & Metadata

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(exercise.displayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(palette.textPrimary)

            VStack(spacing: 8) {
                metadataRow(label: Copy.text("Body Part"), value: Copy.text(exercise.bodyPart.localizationKey))
                metadataRow(label: Copy.text("Primary Muscle"), value: Copy.text(exercise.target.localizationKey))
                metadataRow(label: Copy.text("Equipment"), value: Copy.text(exercise.equipment.localizationKey))
            }

            if !exercise.secondaryMuscles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Copy.text("Secondary Muscles"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(exercise.secondaryMuscles, id: \.self) { muscle in
                                Text(Copy.text(muscle))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(palette.textPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(palette.bgCardElevated, in: Capsule())
                            }
                        }
                    }
                }
            }
        }
        .cardSurface(palette: palette)
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(palette.accentMuted, in: Capsule())
        }
    }

    // MARK: - Quick Actions

    private var actionButtonsRow: some View {
        HStack(spacing: 12) {
            Button {
                showSplitSheet = true
            } label: {
                HStack(spacing: 7) {
                    SvgIconView(.calendarDays, size: 16, color: palette.accent)
                    Text(Copy.text("Add to Split"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button {
                showLogSetSheet = true
            } label: {
                HStack(spacing: 7) {
                    SvgIconView(.plus, size: 16, color: .white)
                    Text(Copy.text("Log Set"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(palette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        if let assignedWeekday {
            HStack(spacing: 8) {
                SvgIconView(.checkCircle2, size: 16, color: palette.success)
                Text("\(Copy.text("Add to Split")): \(Copy.text(assignedWeekday.nameKey))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.success)
                Spacer()
            }
            .cardSurface(palette: palette, cornerRadius: 14, padding: 12)
        }

        if showLoggedConfirmation {
            HStack(spacing: 8) {
                SvgIconView(loggedSetWasPR ? .trophy : .checkCircle2, size: 16, color: loggedSetWasPR ? palette.warning : palette.success)
                Text(loggedSetWasPR ? Copy.text("Personal Record") : Copy.text("Completed"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(loggedSetWasPR ? palette.warning : palette.success)
                Spacer()
            }
            .cardSurface(palette: palette, cornerRadius: 14, padding: 12)
        }
    }

    // MARK: - Progression Chart

    private var progressionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(.trendingUp, size: 18, color: palette.accent)
                    Text(Copy.text("Progression"))
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                if let bestE1RM {
                    HStack(spacing: 4) {
                        SvgIconView(.trophy, size: 12, color: palette.accent)
                        Text("\(Copy.text("Best e1RM")) \(Copy.format("%@ kg", Copy.decimal(bestE1RM, digits: 1)))")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(palette.accent)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.accentMuted, in: Capsule())
                }
            }

            Picker(Copy.text("Period"), selection: $timeframe) {
                ForEach(DashboardTimeframe.allCases) { tf in
                    Text(Copy.text(tf.localizationKey)).tag(tf)
                }
            }
            .pickerStyle(.segmented)

            if progressPoints.isEmpty {
                VStack(spacing: 10) {
                    SvgIconView(.barChart2, size: 28, color: palette.textSecondary)
                    Text(Copy.text("No data yet"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                Chart(progressPoints) { point in
                    LineMark(
                        x: .value(Copy.text("Day"), point.date),
                        y: .value(Copy.text("Weight (kg)"), point.maxWeightKg)
                    )
                    .foregroundStyle(palette.accent)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value(Copy.text("Day"), point.date),
                        y: .value(Copy.text("Weight (kg)"), point.maxWeightKg)
                    )
                    .foregroundStyle(point.isPR ? palette.warning : palette.accent)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 180)

                if let latest = progressPoints.last {
                    HStack(spacing: 12) {
                        statChip(
                            label: Copy.text("Weight (kg)"),
                            value: Copy.format("%@ kg", Copy.decimal(latest.maxWeightKg, digits: 1))
                        )
                        statChip(
                            label: Copy.text("e1RM"),
                            value: Copy.format("%@ kg", Copy.decimal(latest.estimated1RM, digits: 1))
                        )
                        statChip(
                            label: Copy.text("Volume"),
                            value: Copy.format("%@ kg", Copy.decimal(latest.totalVolumeKg, digits: 0))
                        )
                    }
                }
            }
        }
        .cardSurface(palette: palette)
    }

    private func statChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(palette.textSecondary)
            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Instructions

    private var instructionsCard: some View {
        let steps = exercise.sanitizedInstructionSteps

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SvgIconView(.bookOpen, size: 18, color: palette.accent)
                Text(Copy.text("Instructions"))
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
            }

            if steps.isEmpty {
                Text(Copy.text("No data yet"))
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text(Copy.number(index + 1))
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(palette.accent, in: Circle())

                            Text(step)
                                .font(.subheadline)
                                .foregroundStyle(palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .cardSurface(palette: palette)
    }
}

// MARK: - Sheets

private struct AddToSplitSheet: View {
    let exercise: ExerciseRecord
    let onSelectWeekday: (Weekday) -> Void

    @EnvironmentObject private var fitness: FitnessStore
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Weekday.allCases) { weekday in
                    let schedule = fitness.weeklySplit.schedule(for: weekday)
                    let alreadyAdded = schedule.exerciseIDs.contains(exercise.id)
                    Button {
                        onSelectWeekday(weekday)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            SvgIconView(schedule.split.icon, size: 18, color: palette.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Copy.text(weekday.nameKey))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Text(Copy.text(schedule.title))
                                    .font(.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            if alreadyAdded {
                                SvgIconView(.checkCircle2, size: 18, color: palette.success)
                            } else {
                                SvgIconView(.plus, size: 16, color: palette.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle(Copy.text("Add to Split"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.text("Cancel")) { dismiss() }
                }
            }
        }
    }
}

private struct QuickLogSetSheet: View {
    let exercise: ExerciseRecord
    let onLog: (Double, Int, Double?) -> Void

    @EnvironmentObject private var fitness: FitnessStore
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var weightText = "20.0"
    @State private var reps = 10
    @State private var useRPE = false
    @State private var rpe = 8.0
    @State private var didSeed = false

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

    private var priorBestE1RM: Double? {
        let historyBest = fitness.bestE1RM(for: exercise.id) ?? 0
        let activeBest = fitness.activeSession?.exercises
            .filter { $0.exerciseID == exercise.id }
            .map(\.bestE1RM)
            .max() ?? 0
        let combined = max(historyBest, activeBest)
        return combined > 0 ? combined : nil
    }

    private var willBePR: Bool {
        guard let weight = parsedWeightKg, reps > 0 else { return false }
        return PersonalRecordDetector.isPersonalRecord(
            weightKg: weight,
            reps: reps,
            priorBestE1RM: priorBestE1RM
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Copy.text("Weight (kg)"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                    HStack(spacing: 8) {
                        TextField("0.0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .padding(12)
                            .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(Copy.text("kg"))
                            .font(.headline)
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                HStack(spacing: 8) {
                    stepChip(-2.5, label: "-2.5")
                    stepChip(2.5, label: "+2.5")
                    stepChip(5.0, label: "+5")
                    Spacer()
                    if willBePR {
                        HStack(spacing: 4) {
                            SvgIconView(.trophy, size: 13, color: palette.warning)
                            Text(Copy.text("PR"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.warning)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.warning.opacity(0.16), in: Capsule())
                    }
                }

                HStack {
                    Text(Copy.text("Reps"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Stepper(Copy.format("%@ reps", Copy.number(reps)), value: $reps, in: 1...200)
                        .labelsHidden()
                    Text(Copy.format("%@ reps", Copy.number(reps)))
                        .font(.headline)
                        .monospacedDigit()
                }
                .padding(12)
                .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Toggle(isOn: $useRPE) {
                    Text(useRPE ? "\(Copy.text("RPE")) \(Copy.decimal(rpe, digits: 1))" : Copy.text("RPE"))
                        .font(.subheadline.weight(.semibold))
                }
                if useRPE {
                    Slider(value: $rpe, in: 6.0...10.0, step: 0.5)
                }

                Spacer()

                Button {
                    guard let weight = parsedWeightKg, reps > 0 else { return }
                    onLog(weight, reps, useRPE ? rpe : nil)
                    dismiss()
                } label: {
                    Text(Copy.text("Save"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            parsedWeightKg != nil && reps > 0 ? palette.accent : palette.textSecondary.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .disabled(parsedWeightKg == nil || reps <= 0)
            }
            .padding(20)
            .background(palette.bgCanvas)
            .navigationTitle(Copy.text("Log Set"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.text("Cancel")) { dismiss() }
                }
            }
            .onAppear {
                guard !didSeed else { return }
                didSeed = true
                if let last = fitness.previousSets(for: exercise.id).last {
                    weightText = String(format: "%.1f", last.weightKg)
                    reps = max(1, last.reps)
                    if let prevRPE = last.rpe {
                        useRPE = true
                        rpe = prevRPE
                    }
                }
            }
        }
    }

    private func stepChip(_ delta: Double, label: String) -> some View {
        Button {
            let current = parsedWeightKg ?? 0
            weightText = String(format: "%.1f", min(2_000, max(0, current + delta)))
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(palette.accentMuted, in: Capsule())
        }
    }
}
