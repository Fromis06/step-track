import Foundation

enum BodyPart: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case chest = "chest"
    case back = "back"
    case shoulders = "shoulders"
    case upperArms = "upper arms"
    case lowerArms = "lower arms"
    case waist = "waist"
    case upperLegs = "upper legs"
    case lowerLegs = "lower legs"
    case neck = "neck"
    case cardio = "cardio"

    var id: String { rawValue }

    var localizationKey: String { rawValue }
}

enum TargetMuscle: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case pectorals = "pectorals"
    case serratusAnterior = "serratus anterior"
    case upperBack = "upper back"
    case lats = "lats"
    case traps = "traps"
    case spine = "spine"
    case delts = "delts"
    case biceps = "biceps"
    case triceps = "triceps"
    case forearms = "forearms"
    case abs = "abs"
    case glutes = "glutes"
    case quads = "quads"
    case hamstrings = "hamstrings"
    case adductors = "adductors"
    case abductors = "abductors"
    case calves = "calves"
    case levatorScapulae = "levator scapulae"
    case cardiovascularSystem = "cardiovascular system"

    var id: String { rawValue }

    var localizationKey: String { rawValue }

    var bodyPart: BodyPart {
        switch self {
        case .pectorals, .serratusAnterior: .chest
        case .upperBack, .lats, .traps, .spine: .back
        case .delts: .shoulders
        case .biceps, .triceps: .upperArms
        case .forearms: .lowerArms
        case .abs: .waist
        case .glutes, .quads, .hamstrings, .adductors, .abductors: .upperLegs
        case .calves: .lowerLegs
        case .levatorScapulae: .neck
        case .cardiovascularSystem: .cardio
        }
    }
}

enum EquipmentType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case bodyWeight = "body weight"
    case dumbbell = "dumbbell"
    case barbell = "barbell"
    case ezBarbell = "ez barbell"
    case olympicBarbell = "olympic barbell"
    case trapBar = "trap bar"
    case cable = "cable"
    case leverageMachine = "leverage machine"
    case smithMachine = "smith machine"
    case sledMachine = "sled machine"
    case ellipticalMachine = "elliptical machine"
    case skiergMachine = "skierg machine"
    case stationaryBike = "stationary bike"
    case stepmillMachine = "stepmill machine"
    case upperBodyErgometer = "upper body ergometer"
    case band = "band"
    case resistanceBand = "resistance band"
    case kettlebell = "kettlebell"
    case weighted = "weighted"
    case assisted = "assisted"
    case stabilityBall = "stability ball"
    case medicineBall = "medicine ball"
    case bosuBall = "bosu ball"
    case rope = "rope"
    case roller = "roller"
    case wheelRoller = "wheel roller"
    case hammer = "hammer"
    case tire = "tire"

    var id: String { rawValue }

    var localizationKey: String { rawValue }

    var category: EquipmentCategory {
        switch self {
        case .bodyWeight: .bodyweight
        case .dumbbell: .dumbbell
        case .barbell, .ezBarbell, .olympicBarbell, .trapBar: .barbell
        case .cable: .cable
        case .leverageMachine, .smithMachine, .sledMachine, .ellipticalMachine,
             .skiergMachine, .stationaryBike, .stepmillMachine, .upperBodyErgometer: .machine
        case .band, .resistanceBand: .band
        case .kettlebell: .kettlebell
        case .weighted, .assisted, .stabilityBall, .medicineBall, .bosuBall,
             .rope, .roller, .wheelRoller, .hammer, .tire: .other
        }
    }
}

enum EquipmentCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case bodyweight
    case dumbbell
    case barbell
    case cable
    case machine
    case band
    case kettlebell
    case other

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .bodyweight: "Bodyweight"
        case .dumbbell: "Dumbbell"
        case .barbell: "Barbell"
        case .cable: "Cable"
        case .machine: "Machine"
        case .band: "Band"
        case .kettlebell: "Kettlebell"
        case .other: "Other"
        }
    }
}

enum BodyRegionID: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case chest = "chest"
    case backUpper = "back_upper"
    case backLats = "back_lats"
    case backLower = "back_lower"
    case shoulders = "shoulders"
    case biceps = "biceps"
    case triceps = "triceps"
    case forearms = "forearms"
    case abs = "abs"
    case glutes = "glutes"
    case quads = "quads"
    case hamstrings = "hamstrings"
    case calves = "calves"
    case neck = "neck"
    case cardio = "cardio"

    var id: String { rawValue }

    static let structuralNodeNames: Set<String> = ["head", "torso_core", "hands", "feet"]

    var bodyPart: BodyPart {
        switch self {
        case .chest: .chest
        case .backUpper, .backLats, .backLower: .back
        case .shoulders: .shoulders
        case .biceps, .triceps: .upperArms
        case .forearms: .lowerArms
        case .abs: .waist
        case .glutes, .quads, .hamstrings: .upperLegs
        case .calves: .lowerLegs
        case .neck: .neck
        case .cardio: .cardio
        }
    }

    var targets: [TargetMuscle] {
        switch self {
        case .chest: [.pectorals, .serratusAnterior]
        case .backUpper: [.upperBack, .traps]
        case .backLats: [.lats]
        case .backLower: [.spine]
        case .shoulders: [.delts]
        case .biceps: [.biceps]
        case .triceps: [.triceps]
        case .forearms: [.forearms]
        case .abs: [.abs]
        case .glutes: [.glutes, .abductors]
        case .quads: [.quads, .adductors]
        case .hamstrings: [.hamstrings]
        case .calves: [.calves]
        case .neck: [.levatorScapulae]
        case .cardio: [.cardiovascularSystem]
        }
    }

    var isBackFacing: Bool {
        switch self {
        case .backUpper, .backLats, .backLower, .triceps, .glutes, .hamstrings, .calves: true
        default: false
        }
    }

    var localizationKey: String {
        switch self {
        case .chest: "chest"
        case .backUpper: "upper back"
        case .backLats: "lats"
        case .backLower: "lower back"
        case .shoulders: "shoulders"
        case .biceps: "biceps"
        case .triceps: "triceps"
        case .forearms: "forearms"
        case .abs: "abs"
        case .glutes: "glutes"
        case .quads: "quads"
        case .hamstrings: "hamstrings"
        case .calves: "calves"
        case .neck: "neck"
        case .cardio: "cardio"
        }
    }
}

struct ExerciseRecord: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let bodyPart: BodyPart
    let target: TargetMuscle
    let equipment: EquipmentType
    let muscleGroup: String
    let secondaryMuscles: [String]
    let instructionSteps: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, target, equipment
        case bodyPart = "body_part"
        case muscleGroup = "muscle_group"
        case secondaryMuscles = "secondary_muscles"
        case instructionSteps = "instruction_steps"
    }

    var sanitizedName: String { Self.sanitizeDisplayText(name) }

    var displayName: String { Self.formatExerciseTitle(sanitizedName) }

    var sanitizedInstructionSteps: [String] {
        instructionSteps.map { Self.sanitizeDisplayText($0) }
    }

    static func sanitizeDisplayText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{0432}\u{00B0}", with: "\u{00B0}")
            .replacingOccurrences(of: "\u{00C2}\u{00B0}", with: "\u{00B0}")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func formatExerciseTitle(_ sanitized: String) -> String {
        guard let first = sanitized.first else { return sanitized }
        return first.uppercased() + sanitized.dropFirst()
    }
}
