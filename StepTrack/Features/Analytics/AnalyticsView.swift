import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject private var activity: ActivityStore
    @EnvironmentObject private var fitness: FitnessStore
    @Environment(\.themePalette) private var palette
    @AppStorage(Copy.storageKey, store: ActivityStorage.defaults) private var language = "en"

    @State private var timeframe: DashboardTimeframe = .month
    @State private var anchor = Date()
    @State private var selectedDay = HistoryCalendar.key(for: Date())
    @State private var selectedExerciseID = ""
    @State private var strengthMetric: StrengthChartMetric = .weightKg

    private enum StrengthChartMetric: String, CaseIterable, Identifiable {
        case weightKg
        case e1RM
        var id: String { rawValue }
        var localizationKey: String {
            switch self {
            case .weightKg: "Weight (kg)"
            case .e1RM: "Estimated 1RM"
            }
        }
    }

    private struct LoggedExerciseOption: Identifiable, Hashable {
        let id: String
        let name: String
    }

    private struct MonthlyStepBucket: Identifiable {
        let id: String
        let date: Date
        let steps: Int
    }

    private struct MonthlySleepBucket: Identifiable {
        let id: String
        let date: Date
        let hours: Double
    }

    private struct CalorieSeriesPoint: Identifiable {
        let id: String
        let date: Date
        let series: String
        let calories: Int
    }

    private var calendar: Calendar { HistoryCalendar.calendar }
    private var year: Int { calendar.component(.year, from: anchor) }
    private var month: Int { calendar.component(.month, from: anchor) }

    private var locale: Locale {
        _ = language
        return Copy.locale
    }

    private var referenceDate: Date {
        let now = Date()
        switch timeframe {
        case .week:
            if let interval = calendar.dateInterval(of: .weekOfYear, for: anchor) {
                let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? anchor
                return min(end, now)
            }
            return min(anchor, now)
        case .month:
            if let interval = calendar.dateInterval(of: .month, for: anchor) {
                let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? anchor
                return min(end, now)
            }
            return min(anchor, now)
        case .year:
            if let interval = calendar.dateInterval(of: .year, for: anchor) {
                let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? anchor
                return min(end, now)
            }
            return min(anchor, now)
        }
    }

    private var months: [Date] {
        (1...12).compactMap { calendar.date(from: DateComponents(year: year, month: $0, day: 1)) }
    }

    private var periodTitle: String {
        switch timeframe {
        case .week:
            let range = timeframe.dateRange(endingAt: referenceDate, calendar: calendar)
            let startText = range.start.formatted(.dateTime.day().month(.abbreviated).locale(locale))
            let endText = range.end.formatted(.dateTime.day().month(.abbreviated).locale(locale))
            return "\(startText) - \(endText)"
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year().locale(locale))
        case .year:
            return String(year)
        }
    }

    private var canGoForward: Bool {
        let granularity: Calendar.Component = switch timeframe {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        return calendar.compare(anchor, to: Date(), toGranularity: granularity) == .orderedAscending
    }

    private var displayTotalSteps: Int {
        switch timeframe {
        case .week:
            let range = timeframe.dateRange(endingAt: referenceDate, calendar: calendar)
            let days = max(1, (calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 0) + 1)
            return (0..<days).reduce(0) { acc, offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: range.start) else { return acc }
                return acc + (activity.history.days[HistoryCalendar.key(for: day)]?.steps ?? 0)
            }
        case .month:
            return activity.history.records(year: year, month: month).reduce(0) { $0 + $1.steps }
        case .year:
            return activity.history.records(year: year, month: nil).reduce(0) { $0 + $1.steps }
        }
    }

    private var loggedExercises: [LoggedExerciseOption] {
        var map: [String: String] = [:]
        for session in fitness.sessions {
            for ex in session.exercises where !ex.completedSets.isEmpty {
                if map[ex.exerciseID] == nil {
                    map[ex.exerciseID] = ex.exerciseName
                }
            }
        }
        return map
            .map { LoggedExerciseOption(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var activeExerciseID: String {
        if !selectedExerciseID.isEmpty && loggedExercises.contains(where: { $0.id == selectedExerciseID }) {
            return selectedExerciseID
        }
        return loggedExercises.first?.id ?? ""
    }

    var body: some View {
        let summary = fitness.dashboardSummary(
            timeframe: timeframe,
            referenceDate: referenceDate,
            activityHistory: activity.history
        )
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Picker(Copy.text("Period"), selection: $timeframe) {
                        ForEach(DashboardTimeframe.allCases) { item in
                            Text(Copy.text(item.localizationKey)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("statsPeriodPicker")

                    periodHeaderCard
                    goalsSummaryCard(summary: summary)
                    stepsTrendCard(summary: summary)
                    strengthProgressionCard(summary: summary)
                    sleepTrendCard(summary: summary)
                    caloriesTrendCard(summary: summary)
                    if !summary.weightTrend.isEmpty {
                        weightTrendCard(summary: summary)
                    }
                    calendarCard
                    if timeframe != .year {
                        dayDetail
                    }
                    if let message = activity.historyMessage {
                        Text(Copy.text(message))
                            .font(.caption)
                            .foregroundStyle(palette.warning)
                    }
                }
                .padding(20)
            }
            .background(palette.bgCanvas)
            .contentMargins(.bottom, 96, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await activity.refresh() }
            .environment(\.locale, locale)
            .onAppear {
                if selectedExerciseID.isEmpty, let first = loggedExercises.first {
                    selectedExerciseID = first.id
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(Copy.text("Stats"))
                .font(.title2.weight(.bold))
                .tracking(-0.6)
            Spacer(minLength: 52)
        }
    }

    private var periodHeaderCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(periodTitle)
                    .font(.headline)
                    .accessibilityIdentifier("statisticsHeading")
                HStack(spacing: 6) {
                    Button { move(-1) } label: {
                        SvgIconView(icon: .chevronLeft, size: 16, color: palette.textPrimary)
                            .frame(width: 38, height: 32)
                    }
                    .disabled(year <= 2000 && (timeframe == .year || month == 1))
                    .accessibilityLabel(Copy.text("Previous period"))
                    .accessibilityIdentifier("previousPeriod")

                    Button { move(1) } label: {
                        SvgIconView(icon: .chevronRight, size: 16, color: palette.textPrimary)
                            .frame(width: 38, height: 32)
                    }
                    .disabled(!canGoForward)
                    .accessibilityLabel(Copy.text("Next period"))
                    .accessibilityIdentifier("nextPeriod")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Copy.text("Total steps"))
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                Text(Copy.number(displayTotalSteps))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(palette.accent)
                    .accessibilityIdentifier("periodTotal")
            }
        }
        .cardSurface(palette: palette)
    }

    // MARK: - Goals Summary

    private func goalsSummaryCard(summary: AnalyticsSummary) -> some View {
        let ratePercent = Int((summary.goalsCompletionRate * 100).rounded())
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(icon: .target, size: 18, color: palette.accentOnHero)
                    Text(Copy.text("Goals"))
                        .font(.headline)
                }
                Spacer()
                Text(Copy.format("%@%% of goal", Copy.number(ratePercent)))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.14), in: Capsule())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(palette.accentOnHero)
                        .frame(width: ratePercent > 0 ? max(8, geo.size.width * summary.goalsCompletionRate) : 0)
                }
            }
            .frame(height: 8)

            HStack(spacing: 10) {
                heroKPI(title: Copy.text("Goal Days"), value: "\(Copy.number(summary.goalDaysCount))/\(Copy.number(summary.totalDaysCount))")
                heroKPI(title: Copy.text("Sessions"), value: Copy.number(summary.workoutsCompleted))
                heroKPI(title: Copy.text("Personal Record"), value: Copy.number(summary.personalRecordsCount))
                heroKPI(title: Copy.text("Sleep"), value: "\(Copy.decimal(summary.averageSleepHours, digits: 1)) \(Copy.text("h"))")
            }
        }
        .heroSurface(palette: palette)
    }

    private func heroKPI(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Steps Trend Chart

    private func stepsTrendCard(summary: AnalyticsSummary) -> some View {
        let monthlyBuckets = aggregateMonthlySteps(summary.stepTrend)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(icon: .footprints, size: 18, color: palette.accent)
                    Text(Copy.text("Steps"))
                        .font(.headline)
                }
                Spacer()
                Text(Copy.format("%@ steps", Copy.number(summary.averageSteps)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }

            if timeframe == .year {
                Chart(monthlyBuckets) { bucket in
                    BarMark(
                        x: .value(Copy.text("Month"), bucket.date, unit: .month),
                        y: .value(Copy.text("Steps"), bucket.steps)
                    )
                    .foregroundStyle(palette.accent)
                    .cornerRadius(4)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 165)
            } else {
                Chart {
                    ForEach(summary.stepTrend) { point in
                        BarMark(
                            x: .value(Copy.text("Day"), point.date, unit: .day),
                            y: .value(Copy.text("Steps"), point.steps)
                        )
                        .foregroundStyle(point.reachedGoal ? palette.accent : palette.accent.opacity(0.35))
                        .cornerRadius(4)
                    }
                    RuleMark(y: .value(Copy.text("Goal"), activity.dailyGoal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(palette.textSecondary)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 165)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.text("DAILY AVERAGE"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(Copy.number(summary.averageSteps))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Copy.text("Total steps"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(Copy.number(summary.totalSteps))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.accent)
                }
            }
        }
        .cardSurface(palette: palette)
    }

    private func aggregateMonthlySteps(_ points: [StepTrendPoint]) -> [MonthlyStepBucket] {
        var buckets: [Date: Int] = [:]
        for point in points {
            let comps = calendar.dateComponents([.year, .month], from: point.date)
            if let monthStart = calendar.date(from: comps) {
                buckets[monthStart, default: 0] += point.steps
            }
        }
        return buckets.keys.sorted().map { date in
            MonthlyStepBucket(id: HistoryCalendar.key(for: date), date: date, steps: buckets[date] ?? 0)
        }
    }

    // MARK: - Strength & Exercise Weight Progression

    private func strengthProgressionCard(summary: AnalyticsSummary) -> some View {
        let exerciseID = activeExerciseID
        let points = exerciseID.isEmpty
            ? []
            : fitness.weightProgression(for: exerciseID, timeframe: timeframe, referenceDate: referenceDate)
        let bestE1RM = exerciseID.isEmpty ? nil : fitness.bestE1RM(for: exerciseID)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(icon: .dumbbell, size: 18, color: palette.accent)
                    Text(Copy.text("Strength"))
                        .font(.headline)
                }
                Spacer()
                if summary.personalRecordsCount > 0 {
                    HStack(spacing: 4) {
                        SvgIconView(icon: .trophy, size: 13, color: palette.warning)
                        Text(Copy.number(summary.personalRecordsCount))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.warning)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.warning.opacity(0.14), in: Capsule())
                }
            }

            if loggedExercises.isEmpty {
                Text(Copy.text("No Workouts"))
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                HStack(spacing: 10) {
                    Picker(Copy.text("Select Exercise"), selection: $selectedExerciseID) {
                        ForEach(loggedExercises) { ex in
                            Text(ex.name).tag(ex.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Spacer(minLength: 0)

                    Picker(Copy.text("Metric"), selection: $strengthMetric) {
                        ForEach(StrengthChartMetric.allCases) { metric in
                            Text(Copy.text(metric.localizationKey)).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if points.isEmpty {
                    Text(Copy.text("No data yet"))
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    Chart(points) { point in
                        let value = strengthMetric == .weightKg ? point.maxWeightKg : point.estimated1RM
                        LineMark(
                            x: .value(Copy.text("Day"), point.date),
                            y: .value(Copy.text("Weight"), value)
                        )
                        .foregroundStyle(palette.accent)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value(Copy.text("Day"), point.date),
                            y: .value(Copy.text("Weight"), value)
                        )
                        .foregroundStyle(point.isPR ? palette.warning : palette.accent)
                        .symbolSize(point.isPR ? 70 : 35)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 165)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Copy.text("Total Volume"))
                            .font(.caption2)
                            .foregroundStyle(palette.textSecondary)
                        Text(Copy.format("%@ kg", Copy.number(Int(summary.totalVolumeKg.rounded()))))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                    Spacer()
                    if let bestE1RM {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Copy.text("Best e1RM"))
                                .font(.caption2)
                                .foregroundStyle(palette.textSecondary)
                            Text(Copy.format("%@ kg", Copy.decimal(bestE1RM, digits: 1)))
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(palette.accent)
                        }
                    }
                }
            }
        }
        .cardSurface(palette: palette)
    }

    // MARK: - Sleep Trend Chart

    private func sleepTrendCard(summary: AnalyticsSummary) -> some View {
        let monthlyBuckets = aggregateMonthlySleep(summary.sleepTrend)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(icon: .moon, size: 18, color: palette.accent)
                    Text(Copy.text("Sleep"))
                        .font(.headline)
                }
                Spacer()
                Text("\(Copy.text("Average")): \(Copy.decimal(summary.averageSleepHours, digits: 1)) \(Copy.text("h"))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }

            if summary.sleepTrend.allSatisfy({ $0.hours == 0 }) {
                Text(Copy.text("No sleep logged"))
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else if timeframe == .year {
                Chart {
                    ForEach(monthlyBuckets) { bucket in
                        BarMark(
                            x: .value(Copy.text("Month"), bucket.date, unit: .month),
                            y: .value(Copy.text("Sleep"), bucket.hours)
                        )
                        .foregroundStyle(bucket.hours >= fitness.goals.dailySleepHours ? palette.success : palette.accent)
                        .cornerRadius(4)
                    }
                    RuleMark(y: .value(Copy.text("Sleep Target"), fitness.goals.dailySleepHours))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(palette.textSecondary)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 150)
            } else {
                Chart {
                    ForEach(summary.sleepTrend) { point in
                        BarMark(
                            x: .value(Copy.text("Day"), point.date, unit: .day),
                            y: .value(Copy.text("Sleep"), point.hours)
                        )
                        .foregroundStyle(point.hours >= point.targetHours ? palette.success : palette.accent)
                        .cornerRadius(4)
                    }
                    RuleMark(y: .value(Copy.text("Sleep Target"), fitness.goals.dailySleepHours))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(palette.textSecondary)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 150)
            }
        }
        .cardSurface(palette: palette)
    }

    private func aggregateMonthlySleep(_ points: [SleepTrendPoint]) -> [MonthlySleepBucket] {
        var totals: [Date: (sum: Double, count: Int)] = [:]
        for point in points where point.hours > 0 {
            let comps = calendar.dateComponents([.year, .month], from: point.date)
            if let monthStart = calendar.date(from: comps) {
                let current = totals[monthStart] ?? (0, 0)
                totals[monthStart] = (current.sum + point.hours, current.count + 1)
            }
        }
        return totals.keys.sorted().map { date in
            let item = totals[date] ?? (0, 1)
            return MonthlySleepBucket(
                id: HistoryCalendar.key(for: date),
                date: date,
                hours: item.sum / Double(max(1, item.count))
            )
        }
    }

    // MARK: - Calories In vs Out

    private func caloriesTrendCard(summary: AnalyticsSummary) -> some View {
        let seriesData = buildCalorieSeries(summary.calorieTrend)
        let inLabel = Copy.text("Calories In")
        let outLabel = Copy.text("Calories Out")

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(icon: .flame, size: 18, color: palette.accent)
                    Text(Copy.text("Calorie Balance"))
                        .font(.headline)
                }
                Spacer()
            }

            Chart(seriesData) { item in
                LineMark(
                    x: .value(Copy.text("Day"), item.date),
                    y: .value(Copy.text("Calories"), item.calories)
                )
                .foregroundStyle(by: .value(Copy.text("Calories"), item.series))
                .interpolationMethod(.catmullRom)
            }
            .chartForegroundStyleScale([
                inLabel: palette.accent,
                outLabel: palette.warning
            ])
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 165)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.text("Calories In"))
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                    Text(Copy.format("%@ kcal", Copy.number(summary.averageCaloriesIn)))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.accent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Copy.text("Calories Out"))
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                    Text(Copy.format("%@ kcal", Copy.number(summary.averageCaloriesOut)))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.warning)
                }
            }
        }
        .cardSurface(palette: palette)
    }

    private func buildCalorieSeries(_ points: [CalorieTrendPoint]) -> [CalorieSeriesPoint] {
        let inLabel = Copy.text("Calories In")
        let outLabel = Copy.text("Calories Out")

        if timeframe == .year {
            var monthly: [Date: (inSum: Int, outSum: Int, count: Int)] = [:]
            for point in points {
                let comps = calendar.dateComponents([.year, .month], from: point.date)
                if let monthStart = calendar.date(from: comps) {
                    let cur = monthly[monthStart] ?? (0, 0, 0)
                    monthly[monthStart] = (cur.inSum + point.caloriesIn, cur.outSum + point.caloriesOut, cur.count + 1)
                }
            }
            var result: [CalorieSeriesPoint] = []
            for date in monthly.keys.sorted() {
                let item = monthly[date] ?? (0, 0, 1)
                let key = HistoryCalendar.key(for: date)
                result.append(CalorieSeriesPoint(id: "in-\(key)", date: date, series: inLabel, calories: item.inSum / max(1, item.count)))
                result.append(CalorieSeriesPoint(id: "out-\(key)", date: date, series: outLabel, calories: item.outSum / max(1, item.count)))
            }
            return result
        }

        var result: [CalorieSeriesPoint] = []
        for point in points {
            result.append(CalorieSeriesPoint(id: "in-\(point.id)", date: point.date, series: inLabel, calories: point.caloriesIn))
            result.append(CalorieSeriesPoint(id: "out-\(point.id)", date: point.date, series: outLabel, calories: point.caloriesOut))
        }
        return result
    }

    // MARK: - Weight Trend

    private func weightTrendCard(summary: AnalyticsSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(icon: .scale, size: 18, color: palette.accent)
                    Text(Copy.text("Weight Trend"))
                        .font(.headline)
                }
                Spacer()
                if let latest = summary.latestWeightKg {
                    Text(Copy.format("%@ kg", Copy.decimal(latest, digits: 1)))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                }
            }

            if summary.weightTrend.count >= 2 {
                Chart(summary.weightTrend) { point in
                    LineMark(
                        x: .value(Copy.text("Day"), point.date),
                        y: .value(Copy.text("Weight"), point.weightKg)
                    )
                    .foregroundStyle(palette.accent)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value(Copy.text("Day"), point.date),
                        y: .value(Copy.text("Weight"), point.weightKg)
                    )
                    .foregroundStyle(palette.accent)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 145)
            }
        }
        .cardSurface(palette: palette)
    }

    // MARK: - Month & Year Activity Grid

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if timeframe == .year {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                    ForEach(months, id: \.self) { date in
                        Button {
                            anchor = date
                            selectedDay = HistoryCalendar.key(for: date)
                            timeframe = .month
                        } label: {
                            MiniMonthView(month: date, history: activity.history, palette: palette, locale: locale)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(date.formatted(.dateTime.month(.wide).year().locale(locale)))
                        .accessibilityIdentifier("month-\(calendar.component(.month, from: date))")
                    }
                }
                .accessibilityIdentifier("yearGrid")
            } else {
                MonthActivityGrid(month: anchor, history: activity.history, selected: selectedDay, palette: palette, locale: locale) { date in
                    selectedDay = HistoryCalendar.key(for: date)
                }
            }

            HStack(spacing: 14) {
                legend("No data", fill: Color.clear, outlined: true)
                legend("Below goal", fill: palette.textSecondary.opacity(0.28))
                legend("Goal reached", fill: palette.accent)
            }
            .font(.system(size: 10))
            .foregroundStyle(palette.textSecondary)
        }
        .cardSurface(palette: palette)
    }

    private var dayDetail: some View {
        let day = activity.history.days[selectedDay]
        let date = HistoryCalendar.date(for: selectedDay) ?? anchor
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(date.formatted(.dateTime.day().month(.wide).year().locale(locale)))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if day?.reachedGoal == true {
                    SvgIconView(icon: .checkCircle2, size: 18, color: palette.success)
                        .accessibilityLabel(Copy.text("Goal reached"))
                }
            }
            if let day {
                HStack(alignment: .firstTextBaseline) {
                    Text(Copy.format("%@ steps", Copy.number(day.steps)))
                        .font(.title2.bold())
                    Spacer()
                    Text(day.goal.map { Copy.format("Goal: %@", Copy.number($0)) } ?? Copy.text("Goal not recorded"))
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityIdentifier("selectedDayGoal")
                }
                if !day.complete && selectedDay != HistoryCalendar.key(for: Date()) {
                    Text(Copy.text("Partial day"))
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            } else {
                Text(Copy.text("No data yet"))
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(palette: palette)
        .accessibilityIdentifier("selectedDayDetail")
    }

    private func legend(_ title: String, fill: Color, outlined: Bool = false) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(fill)
                .frame(width: 10, height: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(palette.borderSubtle.opacity(outlined ? 1 : 0), lineWidth: 1)
                )
            Text(Copy.text(title))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func move(_ direction: Int) {
        let component: Calendar.Component = switch timeframe {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        guard let next = calendar.date(byAdding: component, value: direction, to: anchor) else { return }
        anchor = next
        if let start = calendar.dateInterval(of: .month, for: next)?.start {
            selectedDay = HistoryCalendar.key(for: start)
        }
    }
}

private struct MonthActivityGrid: View {
    let month: Date
    let history: ActivityHistory
    let selected: String
    let palette: ThemePalette
    let locale: Locale
    let select: (Date) -> Void

    private var weekdays: [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        let labels = formatter.shortStandaloneWeekdaySymbols ?? []
        return labels.isEmpty ? [] : Array(labels.dropFirst()) + [labels[0]]
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(HistoryCalendar.monthCells(containing: month).enumerated()), id: \.offset) { _, date in
                    if let date {
                        let key = HistoryCalendar.key(for: date)
                        let day = history.days[key]
                        let future = key > HistoryCalendar.key(for: Date())
                        Button { select(date) } label: {
                            ActivityCell(day: day, future: future, palette: palette)
                                .overlay {
                                    Text(String(HistoryCalendar.calendar.component(.day, from: date)))
                                        .font(.system(.caption, design: .rounded, weight: .medium))
                                        .foregroundStyle(
                                            day?.reachedGoal == true
                                                ? .white
                                                : palette.textPrimary.opacity(future ? 0.25 : 0.8)
                                        )
                                }
                                .overlay {
                                    if key == selected {
                                        RoundedRectangle(cornerRadius: 7)
                                            .strokeBorder(palette.accent, lineWidth: 2)
                                            .padding(-2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(future)
                        .accessibilityIdentifier("day-\(key)")
                        .accessibilityLabel(date.formatted(.dateTime.day().month(.wide).locale(locale)))
                        .accessibilityValue(
                            day.map {
                                Copy.format("%@ steps", Copy.number($0.steps)) + ", " + Copy.text($0.reachedGoal ? "Goal reached" : ($0.goal == nil ? "Goal not recorded" : "Below goal"))
                            } ?? Copy.text("No data")
                        )
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

private struct MiniMonthView: View {
    let month: Date
    let history: ActivityHistory
    let palette: ThemePalette
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(month.formatted(.dateTime.month(.abbreviated).locale(locale)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                ForEach(Array(HistoryCalendar.monthCells(containing: month).enumerated()), id: \.offset) { _, date in
                    if let date {
                        let key = HistoryCalendar.key(for: date)
                        ActivityCell(
                            day: history.days[key],
                            future: key > HistoryCalendar.key(for: Date()),
                            palette: palette,
                            radius: 2
                        )
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .frame(maxWidth: 88)
        }
        .accessibilityElement(children: .ignore)
    }
}

private struct ActivityCell: View {
    let day: HistoricalDay?
    let future: Bool
    let palette: ThemePalette
    var radius: CGFloat = 7

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(day.map { $0.reachedGoal ? palette.accent : palette.textSecondary.opacity(0.28) } ?? palette.bgCardElevated)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(palette.borderSubtle.opacity(day == nil && !future ? 1 : 0), lineWidth: 0.75)
            )
            .opacity(future ? 0.3 : 1)
            .aspectRatio(1, contentMode: .fit)
    }
}
