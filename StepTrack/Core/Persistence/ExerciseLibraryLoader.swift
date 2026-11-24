import Foundation

enum ExerciseLibraryError: Error, LocalizedError, Equatable {
    case resourceNotFound(String)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name):
            return "Missing exercise resource: \(name)"
        case .invalidData(let reason):
            return "Invalid exercise dataset: \(reason)"
        }
    }
}

private final class ExerciseBundleToken {}

final class ExerciseLibraryLoader: @unchecked Sendable {
    static let shared: ExerciseLibraryLoader = {
        let candidates: [Bundle] = [.main, Bundle(for: ExerciseBundleToken.self)]
        for bundle in candidates {
            if let loader = try? ExerciseLibraryLoader(bundle: bundle) {
                return loader
            }
        }
        return (try? ExerciseLibraryLoader(data: Data("[]".utf8))) ?? ExerciseLibraryLoader(records: [])
    }()

    let exercises: [ExerciseRecord]
    private let byID: [String: ExerciseRecord]
    private let byBodyPart: [BodyPart: [ExerciseRecord]]
    private let byTarget: [TargetMuscle: [ExerciseRecord]]
    private let byEquipment: [EquipmentType: [ExerciseRecord]]
    private let byCategory: [EquipmentCategory: [ExerciseRecord]]
    private let byRegion: [BodyRegionID: [ExerciseRecord]]
    private let searchableIndex: [(record: ExerciseRecord, haystack: String)]

    convenience init(
        bundle: Bundle = .main,
        resourceName: String = "exercises",
        fileExtension: String = "json"
    ) throws {
        guard let url = bundle.url(forResource: resourceName, withExtension: fileExtension)
            ?? bundle.url(forResource: resourceName, withExtension: fileExtension, subdirectory: "Datasets") else {
            throw ExerciseLibraryError.resourceNotFound("\(resourceName).\(fileExtension)")
        }
        let data = try Data(contentsOf: url)
        try self.init(data: data)
    }

    convenience init(data: Data) throws {
        let records: [ExerciseRecord]
        do {
            records = try JSONDecoder().decode([ExerciseRecord].self, from: data)
        } catch {
            throw ExerciseLibraryError.invalidData(error.localizedDescription)
        }
        self.init(records: records)
    }

    private init(records: [ExerciseRecord]) {
        self.exercises = records

        var idMap: [String: ExerciseRecord] = Dictionary(minimumCapacity: records.count)
        var bodyPartMap: [BodyPart: [ExerciseRecord]] = [:]
        var targetMap: [TargetMuscle: [ExerciseRecord]] = [:]
        var equipmentMap: [EquipmentType: [ExerciseRecord]] = [:]
        var categoryMap: [EquipmentCategory: [ExerciseRecord]] = [:]
        var indexed: [(record: ExerciseRecord, haystack: String)] = []
        indexed.reserveCapacity(records.count)

        for record in records {
            idMap[record.id] = record
            bodyPartMap[record.bodyPart, default: []].append(record)
            targetMap[record.target, default: []].append(record)
            equipmentMap[record.equipment, default: []].append(record)
            categoryMap[record.equipment.category, default: []].append(record)

            let parts = [
                record.sanitizedName,
                record.bodyPart.rawValue,
                record.target.rawValue,
                record.equipment.rawValue,
                record.muscleGroup
            ] + record.secondaryMuscles
            let folded = Self.normalizeQuery(parts.joined(separator: " "))
            indexed.append((record: record, haystack: folded))
        }

        var regionMap: [BodyRegionID: [ExerciseRecord]] = [:]
        for region in BodyRegionID.allCases {
            var seenIDs = Set<String>()
            var matches: [ExerciseRecord] = []
            for target in region.targets {
                for record in targetMap[target] ?? [] where seenIDs.insert(record.id).inserted {
                    matches.append(record)
                }
            }
            regionMap[region] = matches
        }

        self.byID = idMap
        self.byBodyPart = bodyPartMap
        self.byTarget = targetMap
        self.byEquipment = equipmentMap
        self.byCategory = categoryMap
        self.byRegion = regionMap
        self.searchableIndex = indexed
    }

    func exercise(id: String) -> ExerciseRecord? {
        byID[id]
    }

    func exercises(for bodyPart: BodyPart) -> [ExerciseRecord] {
        byBodyPart[bodyPart] ?? []
    }

    func exercises(for target: TargetMuscle) -> [ExerciseRecord] {
        byTarget[target] ?? []
    }

    func exercises(for region: BodyRegionID) -> [ExerciseRecord] {
        byRegion[region] ?? []
    }

    func exercises(for equipment: EquipmentType) -> [ExerciseRecord] {
        byEquipment[equipment] ?? []
    }

    func exercises(for category: EquipmentCategory) -> [ExerciseRecord] {
        byCategory[category] ?? []
    }

    func search(
        query: String = "",
        bodyPart: BodyPart? = nil,
        target: TargetMuscle? = nil,
        region: BodyRegionID? = nil,
        equipment: EquipmentType? = nil,
        equipmentCategory: EquipmentCategory? = nil
    ) -> [ExerciseRecord] {
        let normalizedQuery = Self.normalizeQuery(query)
        let regionTargetSet = region.map { Set($0.targets) }

        return searchableIndex.compactMap { entry in
            let record = entry.record
            if let bodyPart, record.bodyPart != bodyPart { return nil }
            if let target, record.target != target { return nil }
            if let regionTargetSet, !regionTargetSet.contains(record.target) { return nil }
            if let equipment, record.equipment != equipment { return nil }
            if let equipmentCategory, record.equipment.category != equipmentCategory { return nil }
            if !normalizedQuery.isEmpty && !entry.haystack.contains(normalizedQuery) { return nil }
            return record
        }
    }

    private static func normalizeQuery(_ raw: String) -> String {
        ExerciseRecord.sanitizeDisplayText(raw)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}
