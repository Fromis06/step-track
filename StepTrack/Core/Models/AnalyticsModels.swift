import Foundation

enum DashboardTimeframe: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case week
    case month
    case year

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    func dayCount(for referenceDate: Date = Date(), calendar: Calendar = HistoryCalendar.calendar) -> Int {
        switch self {
        case .week:
            return 7
        case .month:
            return calendar.range(of: .day, in: .month, for: referenceDate)?.count ?? 30
        case .year:
            return calendar.range(of: .day, in: .year, for: referenceDate)?.count ?? 365
        }
    }

    func dateRange(endingAt referenceDate: Date = Date(), calendar: Calendar = HistoryCalendar.calendar) -> (start: Date, end: Date) {
        let end = calendar.startOfDay(for: referenceDate)
        let daysBack: Int
        switch self {
        case .week: daysBack = 6
        case .month: daysBack = 29
        case .year: daysBack = 364
        }
        let start = calendar.date(byAdding: .day, value: -daysBack, to: end) ?? end
        return (start, end)
    }
}

struct StepTrendPoint: Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var date: Date
    var steps: Int
    var goal: Int
    var reachedGoal: Bool
}

struct StrengthTrendPoint: Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var date: Date
    var totalVolumeKg: Double
    var workoutsCount: Int
    var maxE1RM: Double
}

struct SleepTrendPoint: Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var date: Date
    var hours: Double
    var targetHours: Double
}

struct CalorieTrendPoint: Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var date: Date
    var caloriesIn: Int
    var caloriesOut: Int
}

struct BodyWeightTrendPoint: Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var date: Date
    var weightKg: Double
}

struct AnalyticsSummary: Equatable, Sendable {
    var timeframe: DashboardTimeframe
    var totalSteps: Int
    var averageSteps: Int
    var goalDaysCount: Int
    var totalDaysCount: Int
    var workoutsCompleted: Int
    var totalVolumeKg: Double
    var personalRecordsCount: Int
    var averageSleepHours: Double
    var averageCaloriesIn: Int
    var averageCaloriesOut: Int
    var averageHydrationMl: Int
    var latestWeightKg: Double?
    var weightDeltaKg: Double?
    var goalsCompletionRate: Double
    var checklistCompletedCount: Int
    var checklistTotalCount: Int
    var stepTrend: [StepTrendPoint]
    var strengthTrend: [StrengthTrendPoint]
    var sleepTrend: [SleepTrendPoint]
    var calorieTrend: [CalorieTrendPoint]
    var weightTrend: [BodyWeightTrendPoint]
}
