import XCTest
@testable import StepTrack

final class AddGoalViewTests: XCTestCase {
    func testGoalCRUDAndJSONRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("goals.json")

        var store = GoalChecklistStore()
        store.addGoal(title: "   ")
        XCTAssertTrue(store.items.isEmpty)

        store.addGoal(title: "Hit 10,000 steps", isComplete: false)
        store.addGoal(title: "Bench 80 kg", isComplete: true)
        store.addGoal(title: "Sleep 8 hours", isComplete: false)

        XCTAssertEqual(store.incompleteGoals.count, 2)
        XCTAssertEqual(store.completeGoals.count, 1)

        let firstIncompleteID = try XCTUnwrap(store.incompleteGoals.first?.id)
        store.toggleCompletion(id: firstIncompleteID)
        XCTAssertEqual(store.incompleteGoals.count, 1)
        XCTAssertEqual(store.completeGoals.count, 2)

        store.deleteGoals(at: IndexSet(integer: 0), isComplete: true)
        XCTAssertEqual(store.completeGoals.count, 1)

        try store.save(to: fileURL)
        let loaded = try GoalChecklistStore.load(from: fileURL)
        XCTAssertEqual(loaded, store)
    }
}
