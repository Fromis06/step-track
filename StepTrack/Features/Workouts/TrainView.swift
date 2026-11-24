import SwiftUI

private enum PendingWorkoutStart {
    case schedule(DaySchedule)
    case template(WorkoutTemplate)
}

struct TrainView: View {
    @EnvironmentObject private var fitness: FitnessStore
    @Environment(\.themePalette) private var palette
    @AppStorage(Copy.storageKey, store: ActivityStorage.defaults) private var language = "en"

    @State private var selectedWeekday: Weekday = Weekday.from(date: Date())
    @State private var showSessionCover = false
    @State private var editingSchedule: DaySchedule?
    @State private var showNewTemplateSheet = false
    @State private var pendingStart: PendingWorkoutStart?
    @State private var showReplaceSessionDialog = false
    @State private var expandedSessionIDs: Set<UUID> = []

    init() {}

    private var locale: Locale {
        _ = language
        return Copy.locale
    }

    private var todayWeekday: Weekday {
        Weekday.from(date: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if let message = fitness.persistenceMessage {
                        persistenceBanner(Copy.text(message))
                    }
                    if let active = fitness.activeSession {
                        activeSessionBanner(active)
                    }
                    todayWorkoutHeroCard
                    weeklySplitSection
                    templatesSection
                    sessionHistorySection
                }
                .padding(20)
            }
            .background(palette.bgCanvas)
            .contentMargins(.bottom, 86, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.locale, locale)
            .fullScreenCover(isPresented: $showSessionCover) {
                WorkoutSessionView()
            }
            .sheet(item: $editingSchedule) { schedule in
                DayScheduleEditorSheet(schedule: schedule) { split, title, groups, exerciseIDs in
                    fitness.assignDay(
                        schedule.weekday,
                        split: split,
                        title: title,
                        muscleGroups: groups,
                        exerciseIDs: exerciseIDs
                    )
                }
            }
            .sheet(isPresented: $showNewTemplateSheet) {
                NewTemplateSheet { name, split, exerciseIDs, defaultSets in
                    fitness.saveTemplate(
                        name: name,
                        split: split,
                        exerciseIDs: exerciseIDs,
                        defaultSetsPerExercise: defaultSets
                    )
                }
            }
            .confirmationDialog(
                Copy.text("Start Workout"),
                isPresented: $showReplaceSessionDialog,
                titleVisibility: .visible
            ) {
                Button(Copy.text("Resume Workout")) {
                    pendingStart = nil
                    showSessionCover = true
                }
                Button(Copy.text("Start Workout"), role: .destructive) {
                    if let pendingStart {
                        startPending(pendingStart)
                    }
                    pendingStart = nil
                    showSessionCover = true
                }
                Button(Copy.text("Cancel"), role: .cancel) {
                    pendingStart = nil
                }
            }
        }
    }

    private func requestStart(_ target: PendingWorkoutStart) {
        if fitness.activeSession == nil {
            startPending(target)
            showSessionCover = true
        } else {
            pendingStart = target
            showReplaceSessionDialog = true
        }
    }

    private func startPending(_ target: PendingWorkoutStart) {
        switch target {
        case .schedule(let schedule):
            fitness.startSession(from: schedule)
        case .template(let template):
            fitness.startSession(from: template)
        }
    }

    // MARK: - Header & Banners

    private var header: some View {
        HStack {
            Text(Copy.text("Train"))
                .font(.title2.weight(.bold))
                .tracking(-0.7)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
    }

    private func persistenceBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            SvgIconView(.alertCircle, size: 18, color: palette.warning)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(palette.warning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(palette: palette, cornerRadius: 18, padding: 14)
    }

    private func activeSessionBanner(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(.zap, size: 16, color: palette.accentOnHero)
                    Text(Copy.text(session.title))
                        .font(.headline)
                }
                Spacer()
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    let elapsed = max(0, Int(context.date.timeIntervalSince(session.startedAt)))
                    HStack(spacing: 5) {
                        SvgIconView(.clock, size: 13, color: palette.accentOnHero)
                        Text(formatDuration(seconds: elapsed))
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.14), in: Capsule())
                }
            }

            HStack {
                Text(Copy.format("%@ sets", Copy.number(session.completedSetsCount)))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Button {
                    showSessionCover = true
                } label: {
                    HStack(spacing: 6) {
                        SvgIconView(.play, size: 14, color: palette.bgHero)
                        Text(Copy.text("Resume Workout"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.bgHero)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(palette.accentOnHero, in: Capsule())
                }
            }
        }
        .heroSurface(palette: palette, cornerRadius: 22, padding: 18)
    }

    // MARK: - Today's Workout Hero

    private var todayWorkoutHeroCard: some View {
        let schedule = fitness.todayAssignment
        let hasActive = fitness.activeSession != nil

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(schedule.split.icon, size: 18, color: palette.accent)
                    Text(Copy.text("Today's Workout"))
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Text(Copy.text(schedule.split.titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(palette.accentMuted, in: Capsule())
            }

            Text(Copy.text(schedule.title))
                .font(.title3.weight(.bold))
                .foregroundStyle(palette.textPrimary)

            if !schedule.muscleGroups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(schedule.muscleGroups) { part in
                            Text(Copy.text(part.localizationKey))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(palette.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(palette.bgCardElevated, in: Capsule())
                        }
                    }
                }
            } else if schedule.split.isRest {
                Text(Copy.text("Rest Day"))
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
            }

            Button {
                if fitness.activeSession == nil {
                    fitness.startSession(from: schedule)
                }
                showSessionCover = true
            } label: {
                HStack(spacing: 8) {
                    SvgIconView(.play, size: 15, color: .white)
                    Text(hasActive ? Copy.text("Resume Workout") : Copy.text("Start Workout"))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(palette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .cardSurface(palette: palette)
    }

    // MARK: - 7-Day Weekly Split

    private var weeklySplitSection: some View {
        let selectedSchedule = fitness.weeklySplit.schedule(for: selectedWeekday)
        let library = ExerciseLibraryLoader.shared

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(.calendarDays, size: 18, color: palette.accent)
                    Text(Copy.text("Weekly Split"))
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Button {
                    editingSchedule = selectedSchedule
                } label: {
                    HStack(spacing: 5) {
                        SvgIconView(.pencil, size: 13, color: palette.accent)
                        Text(Copy.text("Edit Split"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(palette.accentMuted, in: Capsule())
                }
            }

            HStack(spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    let daySchedule = fitness.weeklySplit.schedule(for: day)
                    let isSelected = day == selectedWeekday
                    let isToday = day == todayWeekday

                    Button {
                        selectedWeekday = day
                    } label: {
                        VStack(spacing: 6) {
                            Text(Copy.text(day.shortKey))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(isSelected ? .white : (isToday ? palette.accent : palette.textSecondary))
                            SvgIconView(
                                daySchedule.split.icon,
                                size: 15,
                                color: isSelected ? .white : (daySchedule.split.isRest ? palette.textSecondary : palette.accent)
                            )
                            Text(Copy.text(daySchedule.split.titleKey))
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(isSelected ? .white.opacity(0.9) : palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 2)
                        .background(
                            isSelected ? palette.accent : palette.bgCardElevated,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(isToday && !isSelected ? palette.accent : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Copy.text(selectedWeekday.nameKey))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(Copy.text(selectedSchedule.title))
                            .font(.headline)
                            .foregroundStyle(palette.textPrimary)
                    }
                    Spacer()
                    Text(Copy.text(selectedSchedule.split.titleKey))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(palette.accentMuted, in: Capsule())
                }

                if !selectedSchedule.muscleGroups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(selectedSchedule.muscleGroups) { group in
                                Text(Copy.text(group.localizationKey))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(palette.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(palette.bgCardElevated, in: Capsule())
                            }
                        }
                    }
                }

                if selectedSchedule.exerciseIDs.isEmpty {
                    Text(selectedSchedule.split.isRest ? Copy.text("Rest Day") : Copy.text("No exercises found"))
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 6) {
                        ForEach(selectedSchedule.exerciseIDs, id: \.self) { exID in
                            let record = library.exercise(id: exID)
                            HStack(spacing: 8) {
                                SvgIconView(.dumbbell, size: 13, color: palette.accent)
                                Text(record?.displayName ?? exID)
                                    .font(.subheadline)
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                if let record {
                                    Text(Copy.text(record.target.localizationKey))
                                        .font(.caption2)
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        editingSchedule = selectedSchedule
                    } label: {
                        HStack(spacing: 6) {
                            SvgIconView(.pencil, size: 14, color: palette.accent)
                            Text(Copy.text("Edit Split"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.accent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button {
                        requestStart(.schedule(selectedSchedule))
                    } label: {
                        HStack(spacing: 6) {
                            SvgIconView(.play, size: 14, color: .white)
                            Text(Copy.text("Start Workout"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(palette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(14)
            .background(palette.bgCardElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .cardSurface(palette: palette)
    }

    // MARK: - Workout Templates

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(.layers, size: 18, color: palette.accent)
                    Text(Copy.text("Workout Templates"))
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Button {
                    showNewTemplateSheet = true
                } label: {
                    SvgIconView(.plus, size: 16, color: palette.accent)
                        .padding(8)
                        .background(palette.accentMuted, in: Circle())
                }
                .accessibilityLabel(Copy.text("Workout Templates"))
            }

            if fitness.templates.isEmpty {
                Text(Copy.text("No data yet"))
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 10) {
                    ForEach(fitness.templates) { template in
                        HStack(spacing: 12) {
                            SvgIconView(template.split.icon, size: 18, color: palette.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Copy.text(template.name))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(palette.textPrimary)
                                HStack(spacing: 8) {
                                    Text(Copy.text(template.split.titleKey))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(palette.accent)
                                    Text("\(Copy.number(template.exerciseIDs.count)) \(Copy.text("Exercises"))")
                                        .font(.caption2)
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                            Spacer()
                            Button {
                                requestStart(.template(template))
                            } label: {
                                Text(Copy.text("Start Workout"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(palette.accent, in: Capsule())
                            }
                            Button {
                                fitness.deleteTemplate(id: template.id)
                            } label: {
                                SvgIconView(.trash2, size: 15, color: palette.textSecondary)
                            }
                            .accessibilityLabel(Copy.text("Delete"))
                        }
                        .padding(12)
                        .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .cardSurface(palette: palette)
    }

    // MARK: - Session History

    private var sessionHistorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(.dumbbell, size: 18, color: palette.accent)
                    Text(Copy.text("Session History"))
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Text(Copy.number(fitness.sessions.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }

            if fitness.sessions.isEmpty {
                VStack(spacing: 10) {
                    SvgIconView(.dumbbell, size: 30, color: palette.textSecondary)
                    Text(Copy.text("No Workouts"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                VStack(spacing: 12) {
                    ForEach(fitness.sessions) { session in
                        sessionHistoryCard(session)
                    }
                }
            }
        }
        .cardSurface(palette: palette)
    }

    private func sessionHistoryCard(_ session: WorkoutSession) -> some View {
        let isExpanded = expandedSessionIDs.contains(session.id)

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if isExpanded {
                    expandedSessionIDs.remove(session.id)
                } else {
                    expandedSessionIDs.insert(session.id)
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    SvgIconView(session.split.icon, size: 18, color: palette.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(Copy.text(session.title))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(palette.textPrimary)
                            if session.personalRecordCount > 0 {
                                HStack(spacing: 3) {
                                    SvgIconView(.trophy, size: 11, color: palette.warning)
                                    Text("\(Copy.number(session.personalRecordCount)) \(Copy.text("PR"))")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(palette.warning)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.warning.opacity(0.16), in: Capsule())
                            }
                        }

                        Text(Copy.date(session.date))
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)

                        HStack(spacing: 10) {
                            Text(Copy.format("%@ sets", Copy.number(session.completedSetsCount)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text(Copy.format("%@ kg", Copy.decimal(session.totalVolumeKg, digits: 0)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(palette.accent)
                            if session.durationSeconds > 0 {
                                Text(formatDuration(seconds: Int(session.durationSeconds)))
                                    .font(.caption2.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    }

                    Spacer()

                    SvgIconView(isExpanded ? .chevronUp : .chevronDown, size: 16, color: palette.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(session.exercises) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.exerciseName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.textPrimary)
                            ForEach(entry.completedSets) { setLog in
                                HStack(spacing: 8) {
                                    Text("\(Copy.text("Set")) \(Copy.number(setLog.setNumber))")
                                        .font(.caption2)
                                        .foregroundStyle(palette.textSecondary)
                                    Text(Copy.format("%@ kg", Copy.decimal(setLog.weightKg, digits: 1)))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(palette.textPrimary)
                                    Text("x \(Copy.format("%@ reps", Copy.number(setLog.reps)))")
                                        .font(.caption2)
                                        .foregroundStyle(palette.textSecondary)
                                    if setLog.isPersonalRecord {
                                        SvgIconView(.trophy, size: 11, color: palette.warning)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            fitness.deleteSession(id: session.id)
                        } label: {
                            HStack(spacing: 5) {
                                SvgIconView(.trash2, size: 13, color: palette.danger)
                                Text(Copy.text("Delete"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.danger)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(palette.danger.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatDuration(seconds: Int) -> String {
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

// MARK: - Day Schedule Editor Sheet

private struct DayScheduleEditorSheet: View {
    let schedule: DaySchedule
    let onSave: (SplitType, String, [BodyPart], [String]) -> Void

    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var split: SplitType
    @State private var title: String
    @State private var selectedMuscles: [BodyPart]
    @State private var exerciseIDs: [String]
    @State private var showExercisePicker = false

    init(
        schedule: DaySchedule,
        onSave: @escaping (SplitType, String, [BodyPart], [String]) -> Void
    ) {
        self.schedule = schedule
        self.onSave = onSave
        _split = State(initialValue: schedule.split)
        _title = State(initialValue: schedule.title)
        _selectedMuscles = State(initialValue: schedule.muscleGroups)
        _exerciseIDs = State(initialValue: schedule.exerciseIDs)
    }

    var body: some View {
        let library = ExerciseLibraryLoader.shared

        NavigationStack {
            Form {
                Section(Copy.text("Weekly Split")) {
                    Picker(Copy.text("Weekly Split"), selection: $split) {
                        ForEach(SplitType.allCases) { item in
                            Text(Copy.text(item.titleKey)).tag(item)
                        }
                    }
                    .onChange(of: split) { oldSplit, newSplit in
                        selectedMuscles = newSplit.defaultMuscleGroups
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty || trimmed == oldSplit.titleKey {
                            title = newSplit.titleKey
                        }
                    }

                    TextField(Copy.text("Custom"), text: $title)
                }

                Section(Copy.text("Body Part")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(BodyPart.allCases) { part in
                            let isSelected = selectedMuscles.contains(part)
                            Button {
                                if isSelected {
                                    selectedMuscles.removeAll { $0 == part }
                                } else {
                                    selectedMuscles.append(part)
                                }
                            } label: {
                                Text(Copy.text(part.localizationKey))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isSelected ? .white : palette.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(
                                        isSelected ? palette.accent : palette.bgCardElevated,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(Copy.text("Exercises")) {
                    ForEach(Array(exerciseIDs.enumerated()), id: \.offset) { index, exID in
                        HStack(spacing: 10) {
                            Text(library.exercise(id: exID)?.displayName ?? exID)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            if index > 0 {
                                Button {
                                    guard exerciseIDs.indices.contains(index),
                                          exerciseIDs.indices.contains(index - 1) else { return }
                                    exerciseIDs.swapAt(index, index - 1)
                                } label: {
                                    SvgIconView(.chevronUp, size: 15, color: palette.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                            if index < exerciseIDs.count - 1 {
                                Button {
                                    guard exerciseIDs.indices.contains(index),
                                          exerciseIDs.indices.contains(index + 1) else { return }
                                    exerciseIDs.swapAt(index, index + 1)
                                } label: {
                                    SvgIconView(.chevronDown, size: 15, color: palette.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                            Button(role: .destructive) {
                                guard exerciseIDs.indices.contains(index) else { return }
                                exerciseIDs.remove(at: index)
                            } label: {
                                SvgIconView(.trash2, size: 15, color: palette.danger)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        showExercisePicker = true
                    } label: {
                        HStack(spacing: 8) {
                            SvgIconView(.plus, size: 16, color: palette.accent)
                            Text(Copy.text("Add Exercise"))
                                .foregroundStyle(palette.accent)
                        }
                    }
                }
            }
            .navigationTitle(Copy.text(schedule.weekday.nameKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.text("Save")) {
                        onSave(split, title, selectedMuscles, exerciseIDs)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerSheet(excludedIDs: Set(exerciseIDs)) { exercise in
                    if !exerciseIDs.contains(exercise.id) {
                        exerciseIDs.append(exercise.id)
                    }
                }
            }
        }
    }
}

// MARK: - New Template Sheet

private struct NewTemplateSheet: View {
    let onSave: (String, SplitType, [String], Int) -> Void

    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var split: SplitType = .push
    @State private var defaultSets = 3
    @State private var exerciseIDs: [String] = []
    @State private var showExercisePicker = false

    var body: some View {
        let library = ExerciseLibraryLoader.shared

        NavigationStack {
            Form {
                Section(Copy.text("Workout Templates")) {
                    TextField(Copy.text("Custom"), text: $name)

                    Picker(Copy.text("Weekly Split"), selection: $split) {
                        ForEach(SplitType.allCases) { item in
                            Text(Copy.text(item.titleKey)).tag(item)
                        }
                    }

                    Stepper(
                        Copy.format("%@ sets", Copy.number(defaultSets)),
                        value: $defaultSets,
                        in: 1...12
                    )
                }

                Section(Copy.text("Exercises")) {
                    ForEach(Array(exerciseIDs.enumerated()), id: \.offset) { index, exID in
                        HStack {
                            Text(library.exercise(id: exID)?.displayName ?? exID)
                                .font(.subheadline)
                            Spacer()
                            Button(role: .destructive) {
                                guard exerciseIDs.indices.contains(index) else { return }
                                exerciseIDs.remove(at: index)
                            } label: {
                                SvgIconView(.trash2, size: 15, color: palette.danger)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        showExercisePicker = true
                    } label: {
                        HStack(spacing: 8) {
                            SvgIconView(.plus, size: 16, color: palette.accent)
                            Text(Copy.text("Add Exercise"))
                                .foregroundStyle(palette.accent)
                        }
                    }
                }
            }
            .navigationTitle(Copy.text("Workout Templates"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.text("Save")) {
                        onSave(name, split, exerciseIDs, defaultSets)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerSheet(excludedIDs: Set(exerciseIDs)) { exercise in
                    if !exerciseIDs.contains(exercise.id) {
                        exerciseIDs.append(exercise.id)
                    }
                }
            }
        }
    }
}
