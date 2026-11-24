import XCTest
@testable import StepTrack

final class ExerciseLibraryTests: XCTestCase {
    func testBundledExercisesDatasetLoadsAllCategoriesAndRegions() throws {
        let loader = try ExerciseLibraryLoader(bundle: .main)
        XCTAssertEqual(loader.exercises.count, 1_324)

        XCTAssertEqual(BodyPart.allCases.count, 10)
        for bodyPart in BodyPart.allCases {
            XCTAssertFalse(loader.exercises(for: bodyPart).isEmpty, "Expected exercises for bodyPart \(bodyPart.rawValue)")
        }

        XCTAssertEqual(TargetMuscle.allCases.count, 19)
        for target in TargetMuscle.allCases {
            XCTAssertFalse(loader.exercises(for: target).isEmpty, "Expected exercises for target \(target.rawValue)")
        }

        XCTAssertEqual(EquipmentType.allCases.count, 28)
        XCTAssertEqual(loader.exercises(for: EquipmentType.band).count, 54)
        XCTAssertEqual(loader.exercises(for: EquipmentType.resistanceBand).count, 7)
        XCTAssertEqual(
            loader.exercises(for: EquipmentType.band).count + loader.exercises(for: EquipmentType.resistanceBand).count,
            loader.exercises(for: EquipmentCategory.band).count
        )

        // All 15 selectable 3D body regions resolve non-empty exercises.
        XCTAssertEqual(BodyRegionID.allCases.count, 15)
        for region in BodyRegionID.allCases {
            XCTAssertFalse(loader.exercises(for: region).isEmpty, "Expected exercises for region \(region.rawValue)")
        }

        // Exact expected counts for neck and cardio.
        XCTAssertEqual(loader.exercises(for: BodyPart.neck).count, 2)
        XCTAssertEqual(loader.exercises(for: BodyRegionID.neck).count, 2)
        XCTAssertEqual(loader.exercises(for: BodyPart.cardio).count, 29)
        XCTAssertEqual(loader.exercises(for: BodyRegionID.cardio).count, 29)
    }

    func testBodyMeshAssetAndStructuralNodeNames() {
        let objURL = Bundle.main.url(forResource: "human_body", withExtension: "obj")
        XCTAssertNotNil(objURL)
        XCTAssertEqual(BodyRegionID.structuralNodeNames, ["head", "torso_core", "hands", "feet"])
        for structural in BodyRegionID.structuralNodeNames {
            XCTAssertNil(BodyRegionID(rawValue: structural))
        }
    }

    func testSanitizeDisplayTextFixesMojibakeAndCollapsesWhitespace() {
        XCTAssertEqual(ExerciseRecord.sanitizeDisplayText("45\u{0432}\u{00B0} side bend"), "45\u{00B0} side bend")
        XCTAssertEqual(ExerciseRecord.sanitizeDisplayText("45\u{00C2}\u{00B0}   side\n  bend  "), "45\u{00B0} side bend")
        XCTAssertEqual(ExerciseRecord.formatExerciseTitle("barbell bench press"), "Barbell bench press")
    }

    func testSearchHandlesCaseDiacriticsWhitespaceAndEmptyResults() throws {
        let loader = try ExerciseLibraryLoader(bundle: .main)

        let upperMatches = loader.search(query: "  BENCH   PRESS ")
        let lowerMatches = loader.search(query: "bench press")
        XCTAssertFalse(lowerMatches.isEmpty)
        XCTAssertEqual(upperMatches.map(\.id), lowerMatches.map(\.id))

        let filtered = loader.search(query: "curl", region: .biceps, equipment: .dumbbell)
        XCTAssertFalse(filtered.isEmpty)
        XCTAssertTrue(filtered.allSatisfy { $0.equipment == .dumbbell && $0.target == .biceps })

        let empty = loader.search(query: "zzzznonexistentexercise")
        XCTAssertTrue(empty.isEmpty)
    }

    func testDataInitializerAndMissingResourceErrors() throws {
        let validJSON = """
        [
          {
            "id": "custom-1",
            "name": "45\u{00C2}\u{00B0} incline press",
            "body_part": "chest",
            "target": "pectorals",
            "equipment": "dumbbell",
            "muscle_group": "chest",
            "secondary_muscles": ["triceps"],
            "instruction_steps": ["Press dumbbells upward."]
          }
        ]
        """
        let customLoader = try ExerciseLibraryLoader(data: Data(validJSON.utf8))
        XCTAssertEqual(customLoader.exercises.count, 1)
        let record = try XCTUnwrap(customLoader.exercise(id: "custom-1"))
        XCTAssertEqual(record.sanitizedName, "45\u{00B0} incline press")
        XCTAssertEqual(record.displayName, "45\u{00B0} incline press")

        XCTAssertThrowsError(try ExerciseLibraryLoader(data: Data("{invalid".utf8))) { error in
            guard case ExerciseLibraryError.invalidData = error else {
                return XCTFail("Expected invalidData, got \(error)")
            }
        }

        XCTAssertThrowsError(try ExerciseLibraryLoader(bundle: .main, resourceName: "nonexistent-dataset", fileExtension: "json")) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .resourceNotFound("nonexistent-dataset.json"))
        }
    }
}
