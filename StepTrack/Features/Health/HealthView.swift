import SwiftUI
import Charts

struct HealthView: View {
    @EnvironmentObject private var fitness: FitnessStore
    @EnvironmentObject private var activity: ActivityStore
    @Environment(\.themePalette) private var palette
    @AppStorage(Copy.storageKey, store: ActivityStorage.defaults) private var language = "en"

    @State private var showAddMeal = false
    @State private var showLogSleep = false
    @State private var showLogWeight = false
    @State private var showEditGoals = false
    @State private var newChecklistTitle = ""

    private var locale: Locale {
        _ = language
        return Copy.locale
    }

    private var today: Date { Date() }

    private var calendar: Calendar { HistoryCalendar.calendar }

    private var todayMeals: [MealEntry] {
        fitness.mealEntries.filter { calendar.isDate($0.date, inSameDayAs: today) }
    }

    private var favoriteMeals: [MealEntry] {
        var seen: Set<String> = []
        var result: [MealEntry] = []
        for meal in fitness.mealEntries where meal.isFavorite {
            let signature = "\(meal.name.lowercased())|\(meal.category.rawValue)|\(meal.calories)"
            if seen.insert(signature).inserted {
                result.append(meal)
            }
        }
        return result
    }

    private var todaySleepEntries: [SleepEntry] {
        fitness.sleepEntries.filter { calendar.isDate($0.date, inSameDayAs: today) }
    }

    private var todayHydrationEntries: [HydrationEntry] {
        fitness.hydrationEntries.filter { calendar.isDate($0.date, inSameDayAs: today) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if let persistenceMessage = fitness.persistenceMessage {
                        HStack(spacing: 8) {
                            SvgIconView(icon: .alertCircle, size: 18, color: palette.warning)
                            Text(Copy.text(persistenceMessage))
                                .font(.subheadline)
                                .foregroundStyle(palette.warning)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface(palette: palette)
                    }
                    calorieBalanceCard
                    mealsCard
                    sleepCard
                    hydrationCard
                    bodyWeightCard
                    personalGoalsCard
                }
                .padding(20)
            }
            .background(palette.bgCanvas)
            .contentMargins(.bottom, 96, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.locale, locale)
            .sheet(isPresented: $showAddMeal) {
                AddMealSheet { name, category, calories, macros, isFavorite in
                    fitness.logMeal(
                        date: Date(),
                        name: name,
                        category: category,
                        calories: calories,
                        macros: macros,
                        isFavorite: isFavorite
                    )
                }
                .environment(\.themePalette, palette)
                .environment(\.locale, locale)
            }
            .sheet(isPresented: $showLogSleep) {
                LogSleepSheet { date, bedTime, wakeTime, quality, note in
                    fitness.logSleep(
                        date: date,
                        bedTime: bedTime,
                        wakeTime: wakeTime,
                        quality: quality,
                        note: note
                    )
                }
                .environment(\.themePalette, palette)
                .environment(\.locale, locale)
            }
            .sheet(isPresented: $showLogWeight) {
                LogBodyWeightSheet(
                    initialWeight: fitness.bodyWeightEntries.first?.weightKg ?? fitness.profile.weightKg
                ) { weightKg, date in
                    fitness.logBodyWeight(kg: weightKg, on: date)
                }
                .environment(\.themePalette, palette)
                .environment(\.locale, locale)
            }
            .sheet(isPresented: $showEditGoals) {
                EditPersonalGoalsSheet(goals: fitness.goals) { updated in
                    fitness.updateGoals(updated)
                    activity.setGoal(updated.dailySteps)
                }
                .environment(\.themePalette, palette)
                .environment(\.locale, locale)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(today.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)))
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                Text(Copy.text("Health"))
                    .font(.title2.weight(.bold))
                    .tracking(-0.6)
            }
            Spacer(minLength: 52)
        }
    }

    // MARK: - Calorie Balance

    private var calorieBalanceCard: some View {
        let balance = fitness.calorieBalance(on: today, steps: activity.stepsToday)
        let statusKey: String = {
            if abs(balance.netBalance) <= 100 { return "Maintenance" }
            return balance.netBalance < 0 ? "Deficit" : "Surplus"
        }()
        let statusColor: Color = {
            if abs(balance.netBalance) <= 100 { return palette.accentOnHero }
            return balance.netBalance < 0 ? palette.success : palette.warning
        }()
        let maxCalories = max(1, max(balance.caloriesIn, balance.caloriesOut))
        let inFraction = min(1.0, Double(balance.caloriesIn) / Double(maxCalories))
        let outFraction = min(1.0, Double(balance.caloriesOut) / Double(maxCalories))
        let signedNet = balance.netBalance > 0
            ? "+\(Copy.number(balance.netBalance))"
            : Copy.number(balance.netBalance)

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(icon: .flame, size: 18, color: palette.accentOnHero)
                    Text(Copy.text("Calorie Balance"))
                        .font(.headline)
                }
                Spacer()
                Text(Copy.text(statusKey))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.22), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 12) {
                balanceMetric(title: Copy.text("Calories In"), value: Copy.number(balance.caloriesIn), unit: Copy.text("kcal"))
                balanceMetric(title: Copy.text("Calories Out"), value: Copy.number(balance.caloriesOut), unit: Copy.text("kcal"))
                balanceMetric(title: Copy.text("Net Balance"), value: signedNet, unit: Copy.text("kcal"))
            }

            VStack(spacing: 8) {
                calorieComparisonBar(
                    label: Copy.text("Calories In"),
                    fraction: inFraction,
                    color: palette.accentOnHero,
                    valueText: Copy.format("%@ kcal", Copy.number(balance.caloriesIn))
                )
                calorieComparisonBar(
                    label: Copy.text("Calories Out"),
                    fraction: outFraction,
                    color: palette.warning,
                    valueText: Copy.format("%@ kcal", Copy.number(balance.caloriesOut))
                )
            }

            HStack(spacing: 8) {
                burnComponentChip(title: Copy.text("BMR"), calories: balance.bmrCalories)
                burnComponentChip(title: Copy.text("NEAT"), calories: balance.neatCalories)
                burnComponentChip(title: Copy.text("Step Burn"), calories: balance.stepBurnCalories)
                burnComponentChip(title: Copy.text("Workout Burn"), calories: balance.workoutBurnCalories)
            }

            HStack(spacing: 10) {
                macroBarItem(
                    title: Copy.text("Protein"),
                    grams: balance.macrosConsumed.proteinG,
                    target: fitness.goals.dailyProteinG,
                    color: palette.accentOnHero
                )
                macroBarItem(
                    title: Copy.text("Carbs"),
                    grams: balance.macrosConsumed.carbsG,
                    target: fitness.goals.dailyCarbsG,
                    color: palette.success
                )
                macroBarItem(
                    title: Copy.text("Fat"),
                    grams: balance.macrosConsumed.fatG,
                    target: fitness.goals.dailyFatG,
                    color: palette.warning
                )
            }
        }
        .heroSurface(palette: palette)
    }

    private func balanceMetric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calorieComparisonBar(label: String, fraction: Double, color: Color, valueText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(valueText)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
        }
    }

    private func burnComponentChip(title: String, calories: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(Copy.number(calories))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func macroBarItem(title: String, grams: Double, target: Int, color: Color) -> some View {
        let progress = min(1.0, grams / Double(max(1, target)))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(Copy.format("%@ g", Copy.number(Int(grams.rounded()))))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(color)
                        .frame(width: grams > 0 ? max(4, geo.size.width * progress) : 0)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Meals & Macros

    private var mealsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(icon: .utensils, size: 18, color: palette.accent)
                    Text(Copy.text("Meals"))
                        .font(.headline)
                }
                Spacer()
                Button {
                    showAddMeal = true
                } label: {
                    HStack(spacing: 5) {
                        SvgIconView(icon: .plus, size: 14, color: .white)
                        Text(Copy.text("Add Meal"))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if !favoriteMeals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Copy.text("Favorites"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(favoriteMeals) { meal in
                                Button {
                                    fitness.logMeal(
                                        date: Date(),
                                        name: meal.name,
                                        category: meal.category,
                                        calories: meal.calories,
                                        macros: meal.macros,
                                        isFavorite: true
                                    )
                                } label: {
                                    HStack(spacing: 6) {
                                        SvgIconView(icon: meal.category.icon, size: 13, color: palette.accent)
                                        Text(meal.name)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(palette.textPrimary)
                                            .lineLimit(1)
                                        Text(Copy.format("%@ kcal", Copy.number(meal.calories)))
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(palette.accent)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(palette.bgCardElevated, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Copy.text("Re-log"))
                            }
                        }
                    }
                }
            }

            if todayMeals.isEmpty {
                Text(Copy.text("No meals logged"))
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(todayMeals) { meal in
                        mealRow(meal)
                    }
                }
            }
        }
        .cardSurface(palette: palette)
    }

    private func mealRow(_ meal: MealEntry) -> some View {
        HStack(spacing: 12) {
            SvgIconView(icon: meal.category.icon, size: 18, color: palette.accent)
                .frame(width: 34, height: 34)
                .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                HStack(spacing: 6) {
                    Text(Copy.text(meal.category.localizationKey))
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Text(Copy.format("%@ kcal", Copy.number(meal.calories)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if meal.macros.proteinG > 0 {
                        macroBadge(Copy.text("Protein"), grams: meal.macros.proteinG)
                    }
                    if meal.macros.carbsG > 0 {
                        macroBadge(Copy.text("Carbs"), grams: meal.macros.carbsG)
                    }
                    if meal.macros.fatG > 0 {
                        macroBadge(Copy.text("Fat"), grams: meal.macros.fatG)
                    }
                }
            }

            Spacer(minLength: 4)

            Button {
                fitness.toggleMealFavorite(id: meal.id)
            } label: {
                SvgIconView(
                    icon: .heart,
                    size: 16,
                    color: meal.isFavorite ? palette.danger : palette.textSecondary
                )
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.text("Favorites"))

            Button {
                fitness.deleteMeal(id: meal.id)
            } label: {
                SvgIconView(icon: .trash2, size: 15, color: palette.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.text("Delete"))
        }
        .padding(10)
        .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func macroBadge(_ label: String, grams: Double) -> some View {
        HStack(spacing: 2) {
            Text(String(label.prefix(1)))
                .font(.caption2.weight(.bold))
                .foregroundStyle(palette.textSecondary)
            Text(Copy.number(Int(grams.rounded())))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(palette.textSecondary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(palette.bgCard, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Sleep

    private var sleepCard: some View {
        let latestSleep = todaySleepEntries.first ?? fitness.sleepEntries.first
        let totalMinutes = latestSleep?.durationMinutes ?? 0
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let targetMinutes = max(1, Int((fitness.goals.dailySleepHours * 60.0).rounded()))
        let progress = min(1.0, Double(totalMinutes) / Double(targetMinutes))

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(icon: .moon, size: 18, color: palette.accent)
                    Text(Copy.text("Sleep"))
                        .font(.headline)
                }
                Spacer()
                Button {
                    showLogSleep = true
                } label: {
                    HStack(spacing: 5) {
                        SvgIconView(icon: .plus, size: 14, color: .white)
                        Text(Copy.text("Log Sleep"))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if let latest = latestSleep {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Copy.format("%@ h %@ m", Copy.number(hours), Copy.number(minutes)))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text(Copy.format("Goal: %@", Copy.format("%@ h %@ m", Copy.number(targetMinutes / 60), Copy.number(targetMinutes % 60))))
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    qualityRatingRow(rating: latest.quality)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.bgCardElevated)
                        Capsule()
                            .fill(progress >= 1.0 ? palette.success : palette.accent)
                            .frame(width: max(6, geo.size.width * progress))
                    }
                }
                .frame(height: 8)

                VStack(spacing: 8) {
                    ForEach(Array(fitness.sleepEntries.prefix(5))) { entry in
                        sleepRow(entry)
                    }
                }
            } else {
                Text(Copy.text("No sleep logged"))
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .cardSurface(palette: palette)
    }

    private func qualityRatingRow(rating: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { idx in
                SvgIconView(
                    icon: .sparkles,
                    size: 14,
                    color: idx <= rating ? palette.accent : palette.textSecondary.opacity(0.28)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.text("Sleep Quality"))
        .accessibilityValue(Copy.number(rating))
    }

    private func sleepRow(_ entry: SleepEntry) -> some View {
        let hrs = entry.durationMinutes / 60
        let mins = entry.durationMinutes % 60
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.date.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                HStack(spacing: 6) {
                    Text(Copy.date(entry.bedTime, timeOnly: true))
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                    Text("-")
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                    Text(Copy.date(entry.wakeTime, timeOnly: true))
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                }
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Copy.format("%@ h %@ m", Copy.number(hrs), Copy.number(mins)))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                qualityRatingRow(rating: entry.quality)
            }
            Button {
                fitness.deleteSleep(id: entry.id)
            } label: {
                SvgIconView(icon: .trash2, size: 15, color: palette.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.text("Delete"))
        }
        .padding(10)
        .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Hydration

    private var hydrationCard: some View {
        let todayMl = fitness.hydrationMl(on: today)
        let targetMl = max(1, fitness.goals.dailyHydrationMl)
        let progress = min(1.0, Double(todayMl) / Double(targetMl))

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(icon: .droplets, size: 18, color: palette.accent)
                    Text(Copy.text("Hydration"))
                        .font(.headline)
                }
                Spacer()
                Text(Copy.format("%@ ml", Copy.number(todayMl)))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(palette.accent)
                Text("/")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                Text(Copy.format("%@ ml", Copy.number(targetMl)))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardElevated)
                    Capsule()
                        .fill(progress >= 1.0 ? palette.success : palette.accent)
                        .frame(width: todayMl > 0 ? max(6, geo.size.width * progress) : 0)
                }
            }
            .frame(height: 10)

            HStack(spacing: 10) {
                Button {
                    fitness.logHydration(ml: 250)
                } label: {
                    HStack(spacing: 6) {
                        SvgIconView(icon: .plus, size: 14, color: .white)
                        Text(Copy.format("%@ ml", Copy.number(250)))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(palette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    fitness.logHydration(ml: 500)
                } label: {
                    HStack(spacing: 6) {
                        SvgIconView(icon: .plus, size: 14, color: palette.accent)
                        Text(Copy.format("%@ ml", Copy.number(500)))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                if let latest = todayHydrationEntries.first {
                    Button {
                        fitness.deleteHydration(id: latest.id)
                    } label: {
                        HStack(spacing: 4) {
                            SvgIconView(icon: .rotateCcw, size: 14, color: palette.textSecondary)
                            Text(Copy.text("Undo"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(palette.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardSurface(palette: palette)
    }

    // MARK: - Body Weight

    private var bodyWeightCard: some View {
        let entries = fitness.bodyWeightEntries
        let latest = entries.first
        let previous = entries.dropFirst().first
        let currentKg = latest?.weightKg ?? fitness.profile.weightKg
        let deltaKg: Double? = {
            guard let latest, let previous else { return nil }
            return latest.weightKg - previous.weightKg
        }()
        let chartEntries = Array(entries.prefix(14).reversed())

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(icon: .scale, size: 18, color: palette.accent)
                    Text(Copy.text("Body Weight"))
                        .font(.headline)
                }
                Spacer()
                Button {
                    showLogWeight = true
                } label: {
                    HStack(spacing: 5) {
                        SvgIconView(icon: .plus, size: 14, color: .white)
                        Text(Copy.text("Log Weight"))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Copy.format("%@ kg", Copy.decimal(currentKg, digits: 1)))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                if let deltaKg {
                    HStack(spacing: 4) {
                        SvgIconView(
                            icon: deltaKg <= 0 ? .trendingDown : .trendingUp,
                            size: 14,
                            color: palette.accent
                        )
                        let sign = deltaKg > 0 ? "+" : ""
                        Text("\(sign)\(Copy.decimal(deltaKg, digits: 1)) \(Copy.text("kg"))")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                if let targetKg = fitness.goals.targetWeightKg {
                    Text(Copy.format("Goal: %@", Copy.format("%@ kg", Copy.decimal(targetKg, digits: 1))))
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            if chartEntries.count >= 2 {
                Chart(chartEntries) { entry in
                    LineMark(
                        x: .value(Copy.text("Day"), entry.date),
                        y: .value(Copy.text("Weight"), entry.weightKg)
                    )
                    .foregroundStyle(palette.accent)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value(Copy.text("Day"), entry.date),
                        y: .value(Copy.text("Weight"), entry.weightKg)
                    )
                    .foregroundStyle(palette.accent)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 140)
            }

            if entries.isEmpty {
                Text(Copy.text("No weight logged"))
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(entries.prefix(4))) { entry in
                        HStack {
                            Text(entry.date.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            Text(Copy.format("%@ kg", Copy.decimal(entry.weightKg, digits: 1)))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            Button {
                                fitness.deleteBodyWeight(id: entry.id)
                            } label: {
                                SvgIconView(icon: .trash2, size: 14, color: palette.textSecondary)
                                    .frame(width: 26, height: 26)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Copy.text("Delete"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .cardSurface(palette: palette)
    }

    // MARK: - Personal Goals & Checklist

    private var personalGoalsCard: some View {
        let g = fitness.goals
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    SvgIconView(icon: .target, size: 18, color: palette.accent)
                    Text(Copy.text("Personal Goals"))
                        .font(.headline)
                }
                Spacer()
                Button {
                    showEditGoals = true
                } label: {
                    HStack(spacing: 5) {
                        SvgIconView(icon: .pencil, size: 13, color: palette.accent)
                        Text(Copy.text("Edit"))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.accentMuted, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                goalTile(title: Copy.text("Daily Steps"), value: Copy.number(g.dailySteps))
                goalTile(title: Copy.text("Sleep Target"), value: "\(Copy.decimal(g.dailySleepHours, digits: 1)) \(Copy.text("h"))")
                goalTile(title: Copy.text("Daily Calories"), value: Copy.format("%@ kcal", Copy.number(g.dailyCalorieTarget)))
                goalTile(title: Copy.text("Weekly Workouts"), value: Copy.number(g.weeklyWorkoutsTarget))
                goalTile(title: Copy.text("Daily Hydration"), value: Copy.format("%@ ml", Copy.number(g.dailyHydrationMl)))
                goalTile(
                    title: Copy.text("Target Weight"),
                    value: g.targetWeightKg.map { Copy.format("%@ kg", Copy.decimal($0, digits: 1)) } ?? "-"
                )
            }

            Divider().overlay(palette.borderSubtle)

            VStack(alignment: .leading, spacing: 10) {
                Text(Copy.text("Goal Checklist"))
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    TextField(Copy.text("Goal Title"), text: $newChecklistTitle)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button {
                        let trimmed = newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        fitness.addChecklistGoal(title: trimmed)
                        newChecklistTitle = ""
                    } label: {
                        SvgIconView(icon: .plus, size: 16, color: .white)
                            .frame(width: 34, height: 34)
                            .background(palette.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Copy.text("Add Goal"))
                }

                ForEach(Array(fitness.goalChecklist.incompleteGoals.enumerated()), id: \.element.id) { idx, item in
                    checklistRow(item: item, index: idx, isComplete: false)
                }

                if !fitness.goalChecklist.completeGoals.isEmpty {
                    Text(Copy.text("Completed"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                    ForEach(Array(fitness.goalChecklist.completeGoals.enumerated()), id: \.element.id) { idx, item in
                        checklistRow(item: item, index: idx, isComplete: true)
                    }
                }
            }
        }
        .cardSurface(palette: palette)
    }

    private func goalTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func checklistRow(item: PersonalGoalItem, index: Int, isComplete: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                fitness.toggleChecklistGoal(id: item.id)
            } label: {
                SvgIconView(
                    icon: isComplete ? .checkCircle2 : .circle,
                    size: 18,
                    color: isComplete ? palette.success : palette.textSecondary
                )
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.subheadline)
                .strikethrough(isComplete)
                .foregroundStyle(isComplete ? palette.textSecondary : palette.textPrimary)

            Spacer()

            Button {
                fitness.deleteChecklistGoals(at: IndexSet(integer: index), isComplete: isComplete)
            } label: {
                SvgIconView(icon: .trash2, size: 14, color: palette.textSecondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.text("Delete"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Sheets

private struct AddMealSheet: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: MealCategory = .lunch
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var isFavorite = false

    let onSave: (String, MealCategory, Int, MacroBreakdown, Bool) -> Void

    private var parsedCalories: Int? {
        Int(caloriesText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (parsedCalories ?? -1) >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Copy.text("Meal Name"), text: $name)
                    Picker(Copy.text("Meals"), selection: $category) {
                        ForEach(MealCategory.allCases) { item in
                            Text(Copy.text(item.localizationKey)).tag(item)
                        }
                    }
                    TextField(Copy.text("Calories"), text: $caloriesText)
                        .keyboardType(.numberPad)
                }

                Section(Copy.text("Macros")) {
                    TextField(Copy.text("Protein"), text: $proteinText)
                        .keyboardType(.decimalPad)
                    TextField(Copy.text("Carbs"), text: $carbsText)
                        .keyboardType(.decimalPad)
                    TextField(Copy.text("Fat"), text: $fatText)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Toggle(Copy.text("Favorites"), isOn: $isFavorite)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.bgCanvas)
            .navigationTitle(Copy.text("Add Meal"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.text("Save")) {
                        guard let calories = parsedCalories, calories >= 0 else { return }
                        let macros = MacroBreakdown(
                            proteinG: Double(proteinText.replacingOccurrences(of: ",", with: ".")) ?? 0,
                            carbsG: Double(carbsText.replacingOccurrences(of: ",", with: ".")) ?? 0,
                            fatG: Double(fatText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        )
                        onSave(name, category, calories, macros, isFavorite)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private struct LogSleepSheet: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var bedTime: Date
    @State private var wakeTime: Date
    @State private var quality: Int = 4
    @State private var note = ""

    let onSave: (Date, Date, Date, Int, String) -> Void

    init(onSave: @escaping (Date, Date, Date, Int, String) -> Void) {
        self.onSave = onSave
        let now = Date()
        let cal = HistoryCalendar.calendar
        let wake = cal.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
        let bed = cal.date(bySettingHour: 23, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: now) ?? now) ?? now.addingTimeInterval(-8 * 3_600)
        _bedTime = State(initialValue: bed)
        _wakeTime = State(initialValue: wake)
    }

    private var previewDurationMinutes: Int {
        SleepEntry(date: date, bedTime: bedTime, wakeTime: wakeTime, quality: quality).durationMinutes
    }

    var body: some View {
        let hrs = previewDurationMinutes / 60
        let mins = previewDurationMinutes % 60
        NavigationStack {
            Form {
                Section {
                    DatePicker(Copy.text("Day"), selection: $date, displayedComponents: .date)
                    DatePicker(Copy.text("Bedtime"), selection: $bedTime, displayedComponents: .hourAndMinute)
                    DatePicker(Copy.text("Wake Time"), selection: $wakeTime, displayedComponents: .hourAndMinute)
                    LabeledContent(
                        Copy.text("Sleep Duration"),
                        value: Copy.format("%@ h %@ m", Copy.number(hrs), Copy.number(mins))
                    )
                }

                Section(Copy.text("Sleep Quality")) {
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { idx in
                            Button {
                                quality = idx
                            } label: {
                                SvgIconView(
                                    icon: .sparkles,
                                    size: 26,
                                    color: idx <= quality ? palette.accent : palette.textSecondary.opacity(0.3)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Copy.number(idx))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                    TextField(Copy.text("Notes"), text: $note)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.bgCanvas)
            .navigationTitle(Copy.text("Log Sleep"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.text("Save")) {
                        onSave(date, bedTime, wakeTime, quality, note)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct LogBodyWeightSheet: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var weightKg: Double
    @State private var date = Date()

    let onSave: (Double, Date) -> Void

    init(initialWeight: Double, onSave: @escaping (Double, Date) -> Void) {
        _weightKg = State(initialValue: min(400, max(20, initialWeight)))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(Copy.text("Weight"))
                        Spacer()
                        Text(Copy.format("%@ kg", Copy.decimal(weightKg, digits: 1)))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(palette.accent)
                    }
                    Stepper(
                        Copy.text("Weight"),
                        value: $weightKg,
                        in: 20.0...400.0,
                        step: 0.5
                    )
                    .labelsHidden()
                    DatePicker(Copy.text("Day"), selection: $date, displayedComponents: .date)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.bgCanvas)
            .navigationTitle(Copy.text("Log Weight"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.text("Save")) {
                        onSave(weightKg, date)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct EditPersonalGoalsSheet: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var dailySteps: Int
    @State private var dailySleepHours: Double
    @State private var dailyCalorieTarget: Int
    @State private var weeklyWorkoutsTarget: Int
    @State private var hasTargetWeight: Bool
    @State private var targetWeightKg: Double
    @State private var dailyHydrationMl: Int
    @State private var dailyProteinG: Int
    @State private var dailyCarbsG: Int
    @State private var dailyFatG: Int

    let onSave: (PersonalGoals) -> Void

    init(goals: PersonalGoals, onSave: @escaping (PersonalGoals) -> Void) {
        _dailySteps = State(initialValue: goals.dailySteps)
        _dailySleepHours = State(initialValue: goals.dailySleepHours)
        _dailyCalorieTarget = State(initialValue: goals.dailyCalorieTarget)
        _weeklyWorkoutsTarget = State(initialValue: goals.weeklyWorkoutsTarget)
        _hasTargetWeight = State(initialValue: goals.targetWeightKg != nil)
        _targetWeightKg = State(initialValue: goals.targetWeightKg ?? 70.0)
        _dailyHydrationMl = State(initialValue: goals.dailyHydrationMl)
        _dailyProteinG = State(initialValue: goals.dailyProteinG)
        _dailyCarbsG = State(initialValue: goals.dailyCarbsG)
        _dailyFatG = State(initialValue: goals.dailyFatG)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(Copy.text("Personal Goals")) {
                    Stepper(value: $dailySteps, in: 500...50_000, step: 500) {
                        LabeledContent(Copy.text("Daily Steps"), value: Copy.number(dailySteps))
                    }
                    Stepper(value: $dailySleepHours, in: 3.0...16.0, step: 0.5) {
                        LabeledContent(Copy.text("Sleep Target"), value: "\(Copy.decimal(dailySleepHours, digits: 1)) \(Copy.text("h"))")
                    }
                    Stepper(value: $dailyCalorieTarget, in: 800...10_000, step: 50) {
                        LabeledContent(Copy.text("Daily Calories"), value: Copy.format("%@ kcal", Copy.number(dailyCalorieTarget)))
                    }
                    Stepper(value: $weeklyWorkoutsTarget, in: 1...14, step: 1) {
                        LabeledContent(Copy.text("Weekly Workouts"), value: Copy.number(weeklyWorkoutsTarget))
                    }
                    Stepper(value: $dailyHydrationMl, in: 500...10_000, step: 250) {
                        LabeledContent(Copy.text("Daily Hydration"), value: Copy.format("%@ ml", Copy.number(dailyHydrationMl)))
                    }
                }

                Section(Copy.text("Target Weight")) {
                    Toggle(Copy.text("Target Weight"), isOn: $hasTargetWeight)
                    if hasTargetWeight {
                        Stepper(value: $targetWeightKg, in: 20.0...400.0, step: 0.5) {
                            LabeledContent(Copy.text("Target Weight"), value: Copy.format("%@ kg", Copy.decimal(targetWeightKg, digits: 1)))
                        }
                    }
                }

                Section(Copy.text("Macro Targets")) {
                    Stepper(value: $dailyProteinG, in: 20...500, step: 5) {
                        LabeledContent(Copy.text("Protein"), value: Copy.format("%@ g", Copy.number(dailyProteinG)))
                    }
                    Stepper(value: $dailyCarbsG, in: 20...1_000, step: 5) {
                        LabeledContent(Copy.text("Carbs"), value: Copy.format("%@ g", Copy.number(dailyCarbsG)))
                    }
                    Stepper(value: $dailyFatG, in: 10...400, step: 5) {
                        LabeledContent(Copy.text("Fat"), value: Copy.format("%@ g", Copy.number(dailyFatG)))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.bgCanvas)
            .navigationTitle(Copy.text("Personal Goals"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.text("Save Goals")) {
                        let updated = PersonalGoals(
                            dailySteps: dailySteps,
                            dailySleepHours: dailySleepHours,
                            dailyCalorieTarget: dailyCalorieTarget,
                            weeklyWorkoutsTarget: weeklyWorkoutsTarget,
                            targetWeightKg: hasTargetWeight ? targetWeightKg : nil,
                            dailyHydrationMl: dailyHydrationMl,
                            dailyProteinG: dailyProteinG,
                            dailyCarbsG: dailyCarbsG,
                            dailyFatG: dailyFatG
                        )
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}
