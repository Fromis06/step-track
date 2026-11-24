import XCTest
@preconcurrency import UserNotifications
@testable import StepTrack

private final class DeniedMockNotificationCenter: NotificationScheduling, @unchecked Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        false
    }

    func add(_ request: UNNotificationRequest) async throws {
        throw NSError(domain: UNErrorDomain, code: UNError.Code.notificationsNotAllowed.rawValue)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        []
    }

    func removeAllPendingNotificationRequests() {}
}

final class SideloadFallbackTests: XCTestCase {
    private var savedDailyGoal: Any?
    private var savedSnapshot: Any?
    private var savedTrackingEnabled: Any?
    private var savedManualFallback: Any?
    private var savedHistoryData: Data?

    override func setUp() {
        super.setUp()
        savedDailyGoal = ActivityStorage.defaults.object(forKey: "dailyGoal")
        savedSnapshot = ActivityStorage.defaults.object(forKey: "activitySnapshot")
        savedTrackingEnabled = UserDefaults.standard.object(forKey: "trackingEnabled")
        savedManualFallback = UserDefaults.standard.object(forKey: "manualStepFallback")
        savedHistoryData = try? Data(contentsOf: HistoryStorage.fileURL)

        try? HistoryStorage.clear()
        ActivityStorage.clear()
        ActivityStorage.defaults.removeObject(forKey: "dailyGoal")
        UserDefaults.standard.removeObject(forKey: "trackingEnabled")
        UserDefaults.standard.removeObject(forKey: "manualStepFallback")
    }

    override func tearDown() {
        if let savedHistoryData {
            try? FileManager.default.createDirectory(
                at: HistoryStorage.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? savedHistoryData.write(to: HistoryStorage.fileURL, options: .atomic)
        } else {
            try? HistoryStorage.clear()
        }
        savedHistoryData = nil
        restoreDefault(savedDailyGoal, key: "dailyGoal", in: ActivityStorage.defaults)
        restoreDefault(savedSnapshot, key: "activitySnapshot", in: ActivityStorage.defaults)
        restoreDefault(savedTrackingEnabled, key: "trackingEnabled", in: UserDefaults.standard)
        restoreDefault(savedManualFallback, key: "manualStepFallback", in: UserDefaults.standard)
        super.tearDown()
    }

    private func restoreDefault(_ value: Any?, key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func testProvisioningProfileDecodeEntitlementsEdgeCases() throws {
        let plistWithoutEntitlements = try PropertyListSerialization.data(
            fromPropertyList: ["AppIDName": "StepTrack Sideload"],
            format: .xml,
            options: 0
        )
        XCTAssertNil(ProvisioningProfile.decodeEntitlements(in: plistWithoutEntitlements))

        let unclosedXML = Data("<?xml version=\"1.0\"?><plist><dict><key>Entitlements</key>".utf8)
        XCTAssertNil(ProvisioningProfile.decodeEntitlements(in: unclosedXML))

        let corruptXML = Data("<?xml version=\"1.0\"?><plist><not-valid-xml></plist>".utf8)
        XCTAssertNil(ProvisioningProfile.decodeEntitlements(in: corruptXML))
    }

    @MainActor
    func testSigningStatusCurrentUnderSideloadAndSimulator() {
        let status = SigningStatus.current
        if ActivityStore.isRunningOnSimulator {
            XCTAssertNil(status.healthKitInProfile)
        }
        if ActivityStore.motionOnly {
            XCTAssertFalse(status.widgetIncluded)
            XCTAssertFalse(status.sharedContainerAvailable)
        }
    }

    @MainActor
    func testActivityStorageFallbackClampingAndCorruptSnapshotRecovery() throws {
        if ActivityStore.motionOnly {
            XCTAssertNil(ActivityStorage.sharedDefaults)
            XCTAssertTrue(ActivityStorage.defaults === UserDefaults.standard)
        }

        XCTAssertEqual(ActivityStorage.goal, 8_000)
        ActivityStorage.goal = 10
        XCTAssertEqual(ActivityStorage.goal, 500)
        ActivityStorage.goal = 99_999
        XCTAssertEqual(ActivityStorage.goal, 50_000)

        ActivityStorage.defaults.set(Data("corrupt-snapshot".utf8), forKey: "activitySnapshot")
        XCTAssertEqual(ActivityStorage.load(), .empty)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let missingURL = directory.appendingPathComponent("missing.json")
        XCTAssertNil(try HistoryStorage.load(from: missingURL))

        var v2 = ActivityHistory()
        v2.version = 2
        let v2URL = directory.appendingPathComponent("v2.json")
        try HistoryStorage.save(v2, to: v2URL)
        XCTAssertThrowsError(try HistoryStorage.load(from: v2URL))
    }

    @MainActor
    func testActivityStoreConnectFallbackManualStepsGoalAndReset() async {
        let store = ActivityStore()
        defer { store.clearSavedData() }

        await store.connect()

        if ActivityStore.isRunningOnSimulator {
            XCTAssertTrue(store.enabled)
            XCTAssertTrue(store.isUsingManualFallback)
            XCTAssertEqual(store.sourceName, Copy.text("Manual entry"))
            XCTAssertNil(store.message)
        }

        // Seed past day goals (>7 days and yesterday) before updating today's goal,
        // verifying historical targets and >7-day history remain preserved.
        let calendar = HistoryCalendar.calendar
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: now)!
        let yesterdayKey = HistoryCalendar.key(for: yesterday, calendar: calendar)
        let tenDaysAgoKey = HistoryCalendar.key(for: tenDaysAgo, calendar: calendar)

        var seeded = ActivityHistory()
        seeded.changeGoal(7_000, on: tenDaysAgo, calendar: calendar)
        seeded.setManualSteps(4_200, on: tenDaysAgo, observedAt: tenDaysAgo, calendar: calendar)
        seeded.changeGoal(7_000, on: yesterday, calendar: calendar)
        seeded.setManualSteps(6_500, on: yesterday, observedAt: yesterday, calendar: calendar)
        store.applyRestoredBackup(history: seeded, goal: 7_000)

        XCTAssertEqual(store.history.days[yesterdayKey]?.steps, 6_500)
        XCTAssertEqual(store.history.days[tenDaysAgoKey]?.steps, 4_200)

        store.setGoal(11_000)
        XCTAssertEqual(store.dailyGoal, 11_000)
        XCTAssertEqual(store.snapshot.goal, 11_000)
        XCTAssertEqual(store.history.days[yesterdayKey]?.goal, 7_000)
        XCTAssertEqual(store.history.days[tenDaysAgoKey]?.goal, 7_000)
        XCTAssertEqual(store.history.days[tenDaysAgoKey]?.steps, 4_200)

        // Clamping manual steps 0...200_000 and rejecting future date without state mutation.
        let future = calendar.date(byAdding: .day, value: 3, to: Date())!
        store.addManualSteps(9_999, on: future)
        XCTAssertNil(store.history.days[HistoryCalendar.key(for: future, calendar: calendar)])

        store.addManualSteps(350_000)
        let maxObservedAt = store.snapshot.updatedAt
        let maxKey = HistoryCalendar.key(for: maxObservedAt, calendar: calendar)
        XCTAssertEqual(store.history.days[maxKey]?.steps, 200_000)
        XCTAssertEqual(store.snapshot.steps(on: maxObservedAt), 200_000)
        if calendar.isDateInToday(maxObservedAt) {
            XCTAssertEqual(store.stepsToday, 200_000)
            XCTAssertEqual(store.distanceMetersToday, 200_000 * 0.762, accuracy: 0.1)
        }
        // Historical >7-day entry must still remain intact after subsequent manual step entries.
        XCTAssertEqual(store.history.days[tenDaysAgoKey]?.steps, 4_200)

        store.addManualSteps(-50)
        let minObservedAt = store.snapshot.updatedAt
        let minKey = HistoryCalendar.key(for: minObservedAt, calendar: calendar)
        XCTAssertEqual(store.history.days[minKey]?.steps, 0)
        XCTAssertEqual(store.stepsToday, 0)

        store.clearSavedData()
        XCTAssertFalse(store.enabled)
        XCTAssertFalse(store.isUsingManualFallback)
        XCTAssertEqual(store.stepsToday, 0)
    }

    @MainActor
    func testActivityStorePreservesSavedOlderThanSevenDayHistoryOnManualFallbackConnect() async throws {
        let calendar = HistoryCalendar.calendar
        let now = Date()
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: now)!
        let tenDaysAgoKey = HistoryCalendar.key(for: tenDaysAgo, calendar: calendar)

        var preExisting = ActivityHistory()
        preExisting.changeGoal(7_500, on: tenDaysAgo, calendar: calendar)
        preExisting.setManualSteps(4_800, on: tenDaysAgo, observedAt: tenDaysAgo, calendar: calendar)
        try HistoryStorage.save(preExisting)

        let store = ActivityStore()
        defer { store.clearSavedData() }

        await store.connect()
        if ActivityStore.isRunningOnSimulator {
            XCTAssertTrue(store.isUsingManualFallback)
        }
        XCTAssertEqual(store.history.days[tenDaysAgoKey]?.steps, 4_800)
        XCTAssertEqual(store.history.days[tenDaysAgoKey]?.goal, 7_500)
    }

    @MainActor
    func testActivityStoreApplyRestoredBackupActivatesFreshInstall() {
        let store = ActivityStore()
        defer { store.clearSavedData() }

        XCTAssertFalse(store.enabled)

        var restored = ActivityHistory()
        let today = Date()
        let todayKey = HistoryCalendar.key(for: today)
        restored.changeGoal(9_000, on: today)
        restored.setManualSteps(5_400, on: today, observedAt: today)

        store.applyRestoredBackup(history: restored, goal: 9_000)
        XCTAssertEqual(store.dailyGoal, 9_000)
        XCTAssertEqual(store.history.days[todayKey]?.steps, 5_400)
        XCTAssertEqual(store.snapshot.steps(on: today), 5_400)
        XCTAssertTrue(store.enabled)
        if ActivityStore.isRunningOnSimulator {
            XCTAssertTrue(store.isUsingManualFallback)
        }
    }

    @MainActor
    func testNotificationSchedulingDeniedDegradesGracefully() async {
        let scheduler = DailyReminderScheduler()
        let deniedCenter = DeniedMockNotificationCenter()

        do {
            try await scheduler.scheduleDailyReminder(hour: 8, minute: 30, using: deniedCenter)
            XCTFail("Expected denied mock center to throw when authorization is denied")
        } catch {
            XCTAssertNotNil(error)
        }

        // FitnessStore rest timer must not crash when notification authorization is denied.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fitnessStore = FitnessStore(
            localStore: LocalStore(directory: tempDir),
            notificationCenter: deniedCenter,
            isFixture: false
        )
        fitnessStore.startRestTimer(seconds: 45)
        XCTAssertTrue(fitnessStore.isRestTimerRunning)
        XCTAssertEqual(fitnessStore.restRemainingSeconds, 45)
        fitnessStore.stopRestTimer()
        XCTAssertFalse(fitnessStore.isRestTimerRunning)
    }
}
