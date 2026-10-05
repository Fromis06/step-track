import SwiftUI
import HealthKit
import CoreMotion
import WidgetKit

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var snapshot = ActivityStorage.load()
    @Published private(set) var loading = false
    @Published private(set) var message: String?
    @Published private(set) var connectionDiagnostic: String?
    @Published private(set) var history = ActivityHistory()
    @Published private(set) var historyMessage: String?
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "trackingEnabled")
    @Published private(set) var goal = ActivityStorage.goal

    private let health = HKHealthStore()
    private let pedometer = CMPedometer()
    private var observer: HKObserverQuery?
    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    private var observing = false
    private var historyWritable = true

    init() {
        do {
            history = try HistoryStorage.load() ?? ActivityHistory.migrating(snapshot, goal: goal, now: Date())
            if history.goals.isEmpty { history.changeGoal(goal, on: Date()) }
            try HistoryStorage.save(history)
        } catch {
            historyWritable = false
            historyMessage = "History could not be opened. Saved data has not been replaced."
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-fixture") { loadPreviewHistory(); return }
        #endif
        // Register on launch, including a launch triggered by HealthKit background delivery.
        if enabled && !Self.motionOnly { startHealthObservation() }
    }

    func setGoal(_ value: Int) {
        guard historyWritable else { return }
        var updated = history
        let target = max(500, min(50_000, value))
        updated.changeGoal(target, on: Date())
        do {
            try HistoryStorage.save(updated)
            history = updated
            goal = target
            ActivityStorage.goal = target
            snapshot.goal = target
            ActivityStorage.save(snapshot)
            historyMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            historyMessage = "Could not save history. Please try again."
        }
    }

    static var motionOnly: Bool {
        #if MOTION_ONLY
        true
        #else
        false
        #endif
    }
    var sourceName: String { Self.motionOnly ? Copy.text("iPhone sensor") : "Apple Health" }
    var todaySteps: Int { snapshot.steps() }
    var progress: Double { snapshot.progress() }
    var todayDistance: Double? {
        Calendar.current.isDateInToday(snapshot.updatedAt) ? snapshot.meters : nil
    }

    func connect() async {
        guard !loading else { return }
        loading = true
        message = nil
        connectionDiagnostic = nil
        do {
            if Self.motionOnly {
                guard CMPedometer.isStepCountingAvailable() else { throw ActivityError.unavailable }
                _ = try await motionData(from: Calendar.current.startOfDay(for: Date()), to: Date())
            } else {
                guard SigningStatus.current.healthKitInProfile != false else {
                    throw ActivityError.healthKitNotProvisioned
                }
                guard HKHealthStore.isHealthDataAvailable() else { throw ActivityError.unavailable }
                try await health.requestAuthorization(toShare: [], read: [stepType, distanceType])
                // Success means the authorization sheet completed, NOT that read access was granted.
            }
            enabled = true
            UserDefaults.standard.set(true, forKey: "trackingEnabled")
        } catch {
            if case ActivityError.healthKitNotProvisioned = error {
                message = "HealthKit is missing from this app's signing profile."
            } else {
                message = "Could not connect. Check access in Settings."
            }
            let detail = error as NSError
            connectionDiagnostic = "\(detail.domain) (\(detail.code)): \(detail.localizedDescription)"
        }
        loading = false
        if enabled { await resume() }
    }

    func resume() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-fixture") { return }
        #endif
        guard enabled else { return }
        if !Self.motionOnly { startHealthObservation() }
        await refresh()
    }

    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-fixture") { return }
        #endif
        guard enabled else { return }
        if let refreshTask { await refreshTask.value; return }
        let currentGeneration = generation
        let task = Task { await self.loadActivity(generation: currentGeneration) }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func loadActivity(generation expectedGeneration: Int) async {
        loading = true
        defer { loading = false }
        do {
            let now = Date()
            let calendar = HistoryCalendar.calendar
            let today = calendar.startOfDay(for: now)
            let days: [ActivityDay]
            let meters: Double?
            if Self.motionOnly {
                var results: [ActivityDay] = []
                var todayMeters: Double?
                for offset in (-6)...0 {
                    let start = calendar.date(byAdding: .day, value: offset, to: today)!
                    let end = min(now, calendar.date(byAdding: .day, value: 1, to: start)!)
                    let data = try await motionData(from: start, to: end)
                    results.append(ActivityDay(date: start, steps: data.numberOfSteps.intValue))
                    if offset == 0 { todayMeters = data.distance?.doubleValue }
                }
                days = results
                meters = todayMeters
            } else {
                days = try await healthDays(now: now)
                meters = try await healthDistance(start: today, end: now)
            }
            guard enabled, expectedGeneration == generation else { return }
            snapshot = ActivitySnapshot(updatedAt: now, days: days, meters: meters, goal: goal)
            ActivityStorage.save(snapshot)
            if historyWritable {
                var updated = history
                updated.merge(days, observedAt: now)
                do {
                    try HistoryStorage.save(updated)
                    history = updated
                    historyMessage = nil
                } catch {
                    historyMessage = "Could not save history. Please try again."
                }
            }
            WidgetCenter.shared.reloadAllTimelines()
            message = nil
        } catch {
            guard enabled, expectedGeneration == generation else { return }
            // Retain the last successful snapshot; label it stale instead of fabricating zero data.
            message = "Could not update. Unlock iPhone and pull to refresh."
        }
    }

    func disconnect() {
        do { try HistoryStorage.clear() }
        catch { historyMessage = "Could not save history. Please try again."; return }
        generation += 1
        enabled = false
        UserDefaults.standard.set(false, forKey: "trackingEnabled")
        if let observer { health.stop(observer) }
        observer = nil
        observing = false
        if !Self.motionOnly {
            health.disableBackgroundDelivery(for: stepType) { _, _ in }
        }
        snapshot = .empty
        snapshot.goal = goal
        message = nil
        ActivityStorage.clear()
        history = ActivityHistory()
        history.changeGoal(goal, on: Date())
        historyWritable = true
        historyMessage = nil
        do { try HistoryStorage.save(history) }
        catch { historyMessage = "Could not save history. Please try again." }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var stepType: HKQuantityType { HKQuantityType(.stepCount) }
    private var distanceType: HKQuantityType { HKQuantityType(.distanceWalkingRunning) }

    private func startHealthObservation() {
        guard !observing else { return }
        observing = true
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completion, error in
            guard error == nil else { completion(); return }
            Task { @MainActor [weak self] in
                if let self { await self.refresh() }
                completion()
            }
        }
        observer = query
        health.execute(query)
        health.enableBackgroundDelivery(for: stepType, frequency: .hourly) { _, _ in }
    }

    private func healthDays(now: Date) async throws -> [ActivityDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -29, to: today)!
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: now),
                options: .cumulativeSum, anchorDate: today, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                guard let collection else { continuation.resume(throwing: ActivityError.unavailable); return }
                var records: [ActivityDay] = []
                collection.enumerateStatistics(from: start, to: now) { statistics, _ in
                    records.append(ActivityDay(date: statistics.startDate,
                                               steps: Int(statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0)))
                }
                continuation.resume(returning: records)
            }
            health.execute(query)
        }
    }

    private func healthDistance(start: Date, end: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: distanceType,
                                          quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                          options: .cumulativeSum) { _, statistics, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .meter()))
            }
            health.execute(query)
        }
    }

    private func motionData(from start: Date, to end: Date) async throws -> CMPedometerData {
        try await withCheckedThrowingContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                if let error { continuation.resume(throwing: error); return }
                guard let data else { continuation.resume(throwing: ActivityError.unavailable); return }
                continuation.resume(returning: data)
            }
        }
    }

    #if DEBUG
    private func loadPreviewHistory() {
        let calendar = HistoryCalendar.calendar
        let now = Date()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        var preview = ActivityHistory()
        preview.changeGoal(5_000, on: start)
        let today = calendar.startOfDay(for: now)
        preview.changeGoal(8_000, on: today)
        var date = start
        var index = 0
        var recent: [ActivityDay] = []
        while date <= today {
            let count = date == today ? 6_280 : (index % 5 == 0 ? 3_400 : 5_600 + index % 4 * 850)
            let sample = ActivityDay(date: date, steps: count)
            preview.merge([sample], observedAt: now)
            recent.append(sample)
            index += 1
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        history = preview
        goal = 8_000
        snapshot = ActivitySnapshot(updatedAt: now, days: Array(recent.suffix(7)), meters: 4_180, goal: goal)
        enabled = true
    }
    #endif
}

private enum ActivityError: LocalizedError {
    case unavailable
    case healthKitNotProvisioned
    var errorDescription: String? {
        switch self {
        case .unavailable: "Health data is unavailable on this device."
        case .healthKitNotProvisioned: "The installed provisioning profile does not include HealthKit."
        }
    }
}
