import XCTest
@preconcurrency import UserNotifications
@testable import StepTrack

private actor NotificationRecorder {
    private(set) var requests: [UNNotificationRequest] = []
    func add(_ request: UNNotificationRequest) {
        requests.append(request)
    }
    func removeAll() {
        requests.removeAll()
    }
}

private final class MockNotificationCenter: NotificationScheduling, @unchecked Sendable {
    private let recorder = NotificationRecorder()

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func add(_ request: UNNotificationRequest) async throws {
        await recorder.add(request)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await recorder.requests
    }

    func removeAllPendingNotificationRequests() {
        Task { await recorder.removeAll() }
    }
}

final class SettingsViewTests: XCTestCase {
    func testScheduleDailyNotification() async throws {
        let scheduler = DailyReminderScheduler()
        let center = MockNotificationCenter()

        try await scheduler.scheduleDailyReminder(using: center)
        let pending = await center.pendingNotificationRequests()

        XCTAssertEqual(pending.count, 1)
        let added = try XCTUnwrap(pending.first)
        XCTAssertEqual(added.identifier, DailyReminderScheduler.reminderIdentifier)
        XCTAssertEqual(added.content.title, "Step Track")
        XCTAssertEqual(added.content.body, "Daily activity reminder")

        let trigger = try XCTUnwrap(added.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 9)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
    }
}
