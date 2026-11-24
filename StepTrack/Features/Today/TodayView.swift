import SwiftUI
import Charts

struct TodayView: View {
    @EnvironmentObject private var activity: ActivityStore
    @EnvironmentObject private var fitness: FitnessStore
    @Environment(\.themePalette) private var palette
    @AppStorage(Copy.storageKey, store: ActivityStorage.defaults) private var language = "en"

    private let onOpenSettings: (() -> Void)?
    private let onOpenWorkout: (() -> Void)?

    @State private var showManualStepsSheet = false
    @State private var showSleepSheet = false
    @State private var showWorkoutCover = false

    @State private var manualStepsInput = 0
    @State private var sleepBedTime = Calendar.current.date(byAdding: .hour, value: -8, to: Date()) ?? Date()
    @State private var sleepWakeTime = Date()
    @State private var sleepQuality = 4

    init(onOpenSettings: (() -> Void)? = nil, onOpenWorkout: (() -> Void)? = nil) {
        self.onOpenSettings = onOpenSettings
        self.onOpenWorkout = onOpenWorkout
    }

    private var locale: Locale {
        _ = language
        return Copy.locale
    }

    private var weekDays: [ActivityDay] {
        activity.recentHistoryDays(7)
    }

    private var balance: CalorieBalance {
        fitness.calorieBalance(on: Date(), steps: activity.stepsToday)
    }

    private var workoutsThisWeek: Int {
        let calendar = HistoryCalendar.calendar
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())) ?? Date()
        return fitness.sessions.filter { $0.date >= start }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    statusBanners
                    if !activity.enabled {
                        connectionCard
                    }
                    stepsHeroCard
                    metricsRow
                    todaySplitCard
                    calorieBalanceCard
                    sleepHydrationRow
                    dailyGoalsCard
                    historyChartCard
                    footer
                }
                .padding(20)
            }
            .background(palette.bgCanvas)
            .contentMargins(.bottom, 86, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await activity.refresh() }
            .environment(\.locale, locale)
            .sheet(isPresented: $showManualStepsSheet) {
                ManualStepsSheet(
                    steps: $manualStepsInput,
                    onSave: { target in
                        activity.addManualSteps(target)
                    }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showSleepSheet) {
                QuickSleepSheet(
                    bedTime: $sleepBedTime,
                    wakeTime: $sleepWakeTime,
                    quality: $sleepQuality,
                    onSave: { bed, wake, qual in
                        fitness.logSleep(bedTime: bed, wakeTime: wake, quality: qual)
                    }
                )
                .presentationDetents([.medium])
            }
            .fullScreenCover(isPresented: $showWorkoutCover) {
                WorkoutSessionView()
            }
        }
    }

    // MARK: - Header & Banners

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Copy.locale)))
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                Text(Copy.text("Today"))
                    .font(.title2.weight(.bold))
                    .tracking(-0.7)
                    .foregroundStyle(palette.textPrimary)
            }
            if let onOpenSettings {
                Spacer(minLength: 10)
                Button(action: onOpenSettings) {
                    SvgIconView(.settings, size: 20, color: palette.textPrimary)
                        .padding(10)
                        .background(palette.bgCard, in: Circle())
                        .overlay(Circle().strokeBorder(palette.borderSubtle, lineWidth: 1))
                }
                .accessibilityIdentifier("open-settings")
                .accessibilityLabel(Copy.text("Settings"))
            } else {
                Spacer(minLength: 52)
            }
        }
    }

    @ViewBuilder
    private var statusBanners: some View {
        if let message = activity.message {
            bannerRow(text: Copy.text(message))
        }
        if let historyMessage = activity.historyMessage {
            bannerRow(text: Copy.text(historyMessage))
        }
        if let persistenceMessage = fitness.persistenceMessage {
            bannerRow(text: Copy.text(persistenceMessage))
        }
    }

    private func bannerRow(text: String) -> some View {
        HStack(spacing: 10) {
            SvgIconView(.alertCircle, size: 18, color: palette.warning)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(palette.warning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(palette: palette, cornerRadius: 18, padding: 14)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SvgIconView(
                    ActivityStore.motionOnly ? .footprints : .heart,
                    size: 18,
                    color: palette.accent
                )
                Text(ActivityStore.motionOnly ? Copy.text("iPhone steps") : Copy.text("Connect to Health"))
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
            }
            HStack(spacing: 10) {
                Button {
                    Task { await activity.connect() }
                } label: {
                    HStack(spacing: 6) {
                        if activity.loading {
                            ProgressView().tint(.white)
                        }
                        Text(activity.loading ? Copy.text("Connecting…") : Copy.text("Connect"))
                            .fontWeight(.semibold)
                        SvgIconView(.arrowUpRight, size: 16, color: .white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(activity.loading)

                Button {
                    manualStepsInput = activity.stepsToday
                    showManualStepsSheet = true
                } label: {
                    HStack(spacing: 6) {
                        SvgIconView(.pencil, size: 15, color: palette.accent)
                        Text(Copy.text("Manual Steps"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .cardSurface(palette: palette)
    }

    // MARK: - Steps Hero Ring

    private var stepsHeroCard: some View {
        VStack(spacing: 18) {
            HStack {
                HStack(spacing: 6) {
                    SvgIconView(.footprints, size: 14, color: palette.accentOnHero)
                    Text(Copy.text("TODAY"))
                        .font(.caption.weight(.bold))
                        .tracking(2)
                }
                Spacer()
                HStack(spacing: 6) {
                    sourceBadge
                    Text(Copy.format("%@%% of goal", Copy.number(Int(activity.progress * 100))))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.14), in: Capsule())
                }
            }

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 17)
                Circle()
                    .trim(from: 0, to: activity.progress)
                    .stroke(
                        AngularGradient(
                            colors: [palette.accent, palette.accentOnHero],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 17, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    SvgIconView(.footprints, size: 26, color: palette.accentOnHero)
                    Text(hasStepReading ? Copy.number(activity.stepsToday) : "—")
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text(Copy.text("steps"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(28)
            }
            .frame(width: 230, height: 230)
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Copy.format(
                    "%@ steps today, goal %@",
                    Copy.number(activity.stepsToday),
                    Copy.number(activity.dailyGoal)
                )
            )

            HStack {
                Text(
                    activity.stepsToday >= activity.dailyGoal
                        ? Copy.text("Goal reached")
                        : Copy.format("Goal: %@ steps", Copy.number(activity.dailyGoal))
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))

                Spacer()

                Button {
                    manualStepsInput = activity.stepsToday
                    showManualStepsSheet = true
                } label: {
                    HStack(spacing: 5) {
                        SvgIconView(.pencil, size: 13, color: palette.accentOnHero)
                        Text(Copy.text("Add Steps"))
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.14), in: Capsule())
                }
            }
        }
        .heroSurface(palette: palette)
    }

    private var hasStepReading: Bool {
        activity.enabled && (activity.snapshot.updatedAt != .distantPast || activity.stepsToday > 0)
    }

    private var sourceBadge: some View {
        HStack(spacing: 4) {
            SvgIconView(
                activity.isUsingManualFallback ? .pencil : (ActivityStore.motionOnly ? .smartphone : .heart),
                size: 11,
                color: activity.isUsingManualFallback ? palette.warning : palette.accentOnHero
            )
            Text(activity.sourceName)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.12), in: Capsule())
    }

    // MARK: - Metrics Row

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricTile(
                title: Copy.text("Distance"),
                icon: .route,
                value: hasStepReading ? Copy.decimal(activity.distanceMetersToday / 1000.0) : "—",
                unit: Copy.text("km")
            )
            metricTile(
                title: Copy.text("Remaining"),
                icon: .target,
                value: Copy.number(max(0, activity.dailyGoal - activity.stepsToday)),
                unit: Copy.text("steps")
            )
            metricTile(
                title: Copy.text("Active Burn"),
                icon: .flame,
                value: Copy.number(balance.stepBurnCalories + balance.workoutBurnCalories),
                unit: Copy.text("kcal")
            )
        }
    }

    private func metricTile(title: String, icon: AppIcon, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SvgIconView(icon, size: 18, color: palette.accent)
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .foregroundStyle(palette.textPrimary)
            Text(unit)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(palette: palette, cornerRadius: 20, padding: 14)
    }

    // MARK: - Today's Scheduled Split Card

    private var todaySplitCard: some View {
        let schedule = fitness.todayAssignment
        let hasActive = fitness.activeSession != nil

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(.calendarDays, size: 18, color: palette.accent)
                    Text(Copy.text("Today's Workout"))
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                HStack(spacing: 5) {
                    SvgIconView(schedule.split.icon, size: 13, color: palette.accent)
                    Text(Copy.text(schedule.split.titleKey))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(palette.accentMuted, in: Capsule())
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Copy.text(schedule.title))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(palette.textPrimary)

                    if !schedule.muscleGroups.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(schedule.muscleGroups) { group in
                                    Text(Copy.text(group.localizationKey))
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

                    if !schedule.exerciseIDs.isEmpty {
                        HStack(spacing: 5) {
                            SvgIconView(.dumbbell, size: 13, color: palette.textSecondary)
                            Text("\(Copy.number(schedule.exerciseIDs.count)) \(Copy.text("Exercises"))")
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
                Spacer(minLength: 8)
            }

            Button {
                if fitness.activeSession == nil {
                    fitness.startSession(from: schedule)
                }
                if let onOpenWorkout {
                    onOpenWorkout()
                } else {
                    showWorkoutCover = true
                }
            } label: {
                HStack(spacing: 8) {
                    SvgIconView(.play, size: 16, color: .white)
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

    // MARK: - Calorie Balance Card

    private var calorieBalanceCard: some View {
        let statusKey: String
        let statusColor: Color
        if balance.netBalance < -100 {
            statusKey = "Deficit"
            statusColor = palette.success
        } else if balance.netBalance > 100 {
            statusKey = "Surplus"
            statusColor = palette.warning
        } else {
            statusKey = "Maintenance"
            statusColor = palette.accent
        }

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(.flame, size: 18, color: palette.accent)
                    Text(Copy.text("Calorie Balance"))
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Text(Copy.text(statusKey))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.14), in: Capsule())
            }

            HStack(spacing: 10) {
                calorieMetricColumn(
                    label: Copy.text("Calories In"),
                    value: Copy.format("%@ kcal", Copy.number(balance.caloriesIn)),
                    color: palette.textPrimary
                )
                calorieMetricColumn(
                    label: Copy.text("Calories Out"),
                    value: Copy.format("%@ kcal", Copy.number(balance.caloriesOut)),
                    color: palette.textPrimary
                )
                calorieMetricColumn(
                    label: Copy.text("Net Balance"),
                    value: Copy.format("%@ kcal", signedNumber(balance.netBalance)),
                    color: statusColor
                )
            }

            Divider()

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    SvgIconView(.footprints, size: 14, color: palette.textSecondary)
                    Text(Copy.text("Step Burn"))
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                    Text(Copy.format("%@ kcal", Copy.number(balance.stepBurnCalories)))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                HStack(spacing: 6) {
                    SvgIconView(.dumbbell, size: 14, color: palette.textSecondary)
                    Text(Copy.text("Workout Burn"))
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                    Text(Copy.format("%@ kcal", Copy.number(balance.workoutBurnCalories)))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .cardSurface(palette: palette)
    }

    private func calorieMetricColumn(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func signedNumber(_ value: Int) -> String {
        value > 0 ? "+\(Copy.number(value))" : Copy.number(value)
    }

    // MARK: - Sleep & Hydration Quick-Log

    private var sleepHydrationRow: some View {
        let sleepHours = fitness.sleepHours(on: Date())
        let sleepMinutes = Int((sleepHours * 60.0).rounded())
        let hoursPart = sleepMinutes / 60
        let minsPart = sleepMinutes % 60
        let targetSleepMinutes = Int((fitness.goals.dailySleepHours * 60.0).rounded())
        let waterMl = fitness.hydrationMl(on: Date())

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    SvgIconView(.moon, size: 16, color: palette.accent)
                    Text(Copy.text("Sleep"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                }

                Text(Copy.format("%@ h %@ m", Copy.number(hoursPart), Copy.number(minsPart)))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)

                Text(
                    Copy.format(
                        "Goal: %@",
                        Copy.format(
                            "%@ h %@ m",
                            Copy.number(targetSleepMinutes / 60),
                            Copy.number(targetSleepMinutes % 60)
                        )
                    )
                )
                .font(.caption)
                .foregroundStyle(palette.textSecondary)

                Spacer(minLength: 4)

                Button {
                    sleepBedTime = Calendar.current.date(byAdding: .hour, value: -8, to: Date()) ?? Date()
                    sleepWakeTime = Date()
                    showSleepSheet = true
                } label: {
                    HStack(spacing: 5) {
                        SvgIconView(.plus, size: 13, color: palette.accent)
                        Text(Copy.text("Log Sleep"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
            .cardSurface(palette: palette, cornerRadius: 20, padding: 14)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    SvgIconView(.droplets, size: 16, color: palette.accent)
                    Text(Copy.text("Hydration"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                }

                Text(Copy.format("%@ ml", Copy.number(waterMl)))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)

                Text(Copy.format("Goal: %@", Copy.format("%@ ml", Copy.number(fitness.goals.dailyHydrationMl))))
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    Button {
                        fitness.logHydration(ml: 250)
                    } label: {
                        Text("+\(Copy.format("%@ ml", Copy.number(250)))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Button {
                        fitness.logHydration(ml: 500)
                    } label: {
                        Text("+\(Copy.format("%@ ml", Copy.number(500)))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
            .cardSurface(palette: palette, cornerRadius: 20, padding: 14)
        }
    }

    // MARK: - Daily Goals Summary

    private var dailyGoalsCard: some View {
        let sleepHours = fitness.sleepHours(on: Date())
        let waterMl = fitness.hydrationMl(on: Date())
        let incompleteChecklist = fitness.goalChecklist.incompleteGoals

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(.target, size: 18, color: palette.accent)
                    Text(Copy.text("Personal Goals"))
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Text(Copy.text("Goals"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }

            goalProgressRow(
                label: Copy.text("Daily Steps"),
                valueText: "\(Copy.number(activity.stepsToday)) / \(Copy.number(activity.dailyGoal))",
                progress: Double(activity.stepsToday) / Double(max(1, activity.dailyGoal))
            )

            goalProgressRow(
                label: Copy.text("Weekly Workouts"),
                valueText: "\(Copy.number(workoutsThisWeek)) / \(Copy.number(fitness.goals.weeklyWorkoutsTarget))",
                progress: Double(workoutsThisWeek) / Double(max(1, fitness.goals.weeklyWorkoutsTarget))
            )

            goalProgressRow(
                label: Copy.text("Sleep Target"),
                valueText: "\(Copy.decimal(sleepHours, digits: 1)) / \(Copy.decimal(fitness.goals.dailySleepHours, digits: 1)) \(Copy.text("h"))",
                progress: sleepHours / max(0.1, fitness.goals.dailySleepHours)
            )

            goalProgressRow(
                label: Copy.text("Hydration Target"),
                valueText: "\(Copy.number(waterMl)) / \(Copy.format("%@ ml", Copy.number(fitness.goals.dailyHydrationMl)))",
                progress: Double(waterMl) / Double(max(1, fitness.goals.dailyHydrationMl))
            )

            if !incompleteChecklist.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(incompleteChecklist.prefix(5)) { item in
                        Button {
                            fitness.toggleChecklistGoal(id: item.id)
                        } label: {
                            HStack(spacing: 10) {
                                SvgIconView(
                                    item.isComplete ? .checkCircle2 : .circle,
                                    size: 18,
                                    color: item.isComplete ? palette.success : palette.textSecondary
                                )
                                Text(item.title)
                                    .font(.subheadline)
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .cardSurface(palette: palette)
    }

    private func goalProgressRow(label: String, valueText: String, progress: Double) -> some View {
        let clamped = min(1.0, max(0.0, progress))
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text(valueText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.bgCardElevated)
                        .frame(height: 7)
                    Capsule()
                        .fill(clamped >= 1.0 ? palette.success : palette.accent)
                        .frame(width: geo.size.width * clamped, height: 7)
                }
            }
            .frame(height: 7)
        }
    }

    // MARK: - 7-Day Step Chart

    private var historyChartCard: some View {
        let records = weekDays
        let average = records.isEmpty ? 0 : records.reduce(0) { $0 + $1.steps } / records.count
        let goalDays = records.filter {
            activity.history.days[HistoryCalendar.key(for: $0.date)]?.reachedGoal == true
        }.count

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(Copy.text("Activity"))
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                HStack(spacing: 6) {
                    Text(Copy.text("7 days"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                    SvgIconView(.barChart2, size: 18, color: palette.accent)
                }
            }

            if records.allSatisfy({ $0.steps == 0 }) && !activity.enabled {
                VStack(spacing: 10) {
                    SvgIconView(.footprints, size: 32, color: palette.textSecondary)
                    Text(Copy.text("No data yet"))
                        .font(.headline)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                Chart(records) { record in
                    BarMark(
                        x: .value(Copy.text("Day"), record.date, unit: .day),
                        y: .value(Copy.text("Steps"), record.steps)
                    )
                    .cornerRadius(5)
                    .foregroundStyle(
                        Calendar.current.isDateInToday(record.date) ? palette.accent : palette.accent.opacity(0.32)
                    )
                    .accessibilityLabel(record.date.formatted(.dateTime.day().month().locale(Copy.locale)))
                    .accessibilityValue(Copy.format("%@ steps", Copy.number(record.steps)))
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 1)) {
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .frame(height: 165)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Copy.text("DAILY AVERAGE"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(Copy.number(average))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(Copy.text("GOAL DAYS"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("\(Copy.number(goalDays)) / \(Copy.number(records.count))")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(palette.accent)
                    }
                }
            }
        }
        .cardSurface(palette: palette)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                SvgIconView(
                    activity.isUsingManualFallback ? .pencil : (ActivityStore.motionOnly ? .smartphone : .heart),
                    size: 14,
                    color: palette.accent
                )
                Text(activity.sourceName)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(palette.accent)

            if activity.loading {
                ProgressView(Copy.text("Updating…"))
                    .font(.caption)
            } else if activity.snapshot.updatedAt != .distantPast {
                Text(Copy.format("Updated %@", Copy.date(activity.snapshot.updatedAt)))
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.bottom, 12)
    }
}

// MARK: - Sheets

private struct ManualStepsSheet: View {
    @Binding var steps: Int
    let onSave: (Int) -> Void

    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text(Copy.number(steps))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.accent)
                    Text(Copy.text("steps"))
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, 8)

                TextField(Copy.text("Steps"), value: $steps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.semibold))
                    .padding(12)
                    .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: steps) { _, newValue in
                        steps = max(0, min(200_000, newValue))
                    }

                HStack(spacing: 10) {
                    incrementButton(1_000)
                    incrementButton(2_500)
                    Button {
                        steps = 0
                    } label: {
                        Text(Copy.text("Reset"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                Spacer()

                Button {
                    onSave(max(0, min(200_000, steps)))
                    dismiss()
                } label: {
                    Text(Copy.text("Save"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(palette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(20)
            .background(palette.bgCanvas)
            .navigationTitle(Copy.text("Manual Steps"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.text("Cancel")) { dismiss() }
                }
            }
        }
    }

    private func incrementButton(_ delta: Int) -> some View {
        Button {
            steps = min(200_000, max(0, steps + delta))
        } label: {
            Text("+\(Copy.number(delta))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct QuickSleepSheet: View {
    @Binding var bedTime: Date
    @Binding var wakeTime: Date
    @Binding var quality: Int
    let onSave: (Date, Date, Int) -> Void

    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(Copy.text("Bedtime"), selection: $bedTime, displayedComponents: [.date, .hourAndMinute])
                    DatePicker(Copy.text("Wake Time"), selection: $wakeTime, displayedComponents: [.date, .hourAndMinute])
                }

                Section(Copy.text("Sleep Quality")) {
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { level in
                            Button {
                                quality = level
                            } label: {
                                Text(Copy.number(level))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(quality == level ? .white : palette.textPrimary)
                                    .background(
                                        quality == level ? palette.accent : palette.bgCardElevated,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(Copy.text("Log Sleep"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.text("Save")) {
                        onSave(bedTime, wakeTime, quality)
                        dismiss()
                    }
                }
            }
        }
    }
}
