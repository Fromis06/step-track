import SwiftUI

struct BodyLibraryView: View {
    @EnvironmentObject private var fitness: FitnessStore
    @Environment(\.themePalette) private var palette
    @AppStorage(Copy.storageKey, store: ActivityStorage.defaults) private var language = "en"

    @State private var selectedRegion: BodyRegionID?
    @State private var selectedBodyPart: BodyPart?
    @State private var selectedTarget: TargetMuscle?
    @State private var selectedCategory: EquipmentCategory?
    @State private var searchText = ""
    @State private var isBackView = false
    @State private var resetTrigger = 0

    init() {}

    private var locale: Locale {
        _ = language
        return Copy.locale
    }

    private var results: [ExerciseRecord] {
        ExerciseLibraryLoader.shared.search(
            query: searchText,
            bodyPart: selectedBodyPart,
            target: selectedTarget,
            region: selectedRegion,
            equipmentCategory: selectedCategory
        )
    }

    private var availableTargets: [TargetMuscle] {
        guard let selectedBodyPart else { return [] }
        return TargetMuscle.allCases.filter { $0.bodyPart == selectedBodyPart }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    bodyMapCard
                    searchFieldCard
                    bodyPartFilterRow
                    if availableTargets.count > 1 {
                        targetSubFilterRow
                    }
                    equipmentFilterRow
                    resultsSection
                }
                .padding(20)
            }
            .background(palette.bgCanvas)
            .contentMargins(.bottom, 86, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.locale, locale)
            .onChange(of: selectedRegion) { _, newRegion in
                if newRegion != nil {
                    selectedBodyPart = nil
                    selectedTarget = nil
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Copy.text("Body Map"))
                    .font(.title2.weight(.bold))
                    .tracking(-0.7)
                    .foregroundStyle(palette.textPrimary)
                Text(Copy.text("Exercise Library"))
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                SvgIconView(.dumbbell, size: 13, color: palette.accent)
                Text(Copy.number(results.count))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(palette.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.accentMuted, in: Capsule())
            .padding(.trailing, 52)
        }
    }

    // MARK: - Interactive 3D Body Map Card

    private var bodyMapCard: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                BodyMap3DView(
                    selectedRegion: $selectedRegion,
                    isBackView: $isBackView,
                    resetTrigger: resetTrigger,
                    accentColor: palette.accent,
                    structuralColor: palette.textSecondary.opacity(0.45),
                    defaultMuscleColor: palette.textSecondary.opacity(0.85),
                    cardioColor: palette.danger,
                    backgroundColor: palette.bgCardElevated
                )
                .frame(height: 310)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack {
                    if let region = selectedRegion {
                        HStack(spacing: 6) {
                            Text(Copy.text(region.localizationKey))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                            Text(Copy.number(results.count))
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.85))
                            Button {
                                selectedRegion = nil
                            } label: {
                                SvgIconView(.x, size: 12, color: .white)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.accent, in: Capsule())
                    }
                    Spacer()
                }
                .padding(12)
            }

            HStack(spacing: 10) {
                Button {
                    isBackView.toggle()
                } label: {
                    HStack(spacing: 6) {
                        SvgIconView(isBackView ? .bodyFront : .bodyBack, size: 16, color: palette.accent)
                        Text(Copy.text(isBackView ? "Front" : "Back"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityIdentifier("bodyFlipButton")

                Button {
                    isBackView = false
                    selectedRegion = nil
                    selectedBodyPart = nil
                    selectedTarget = nil
                    selectedCategory = nil
                    searchText = ""
                    resetTrigger += 1
                } label: {
                    HStack(spacing: 6) {
                        SvgIconView(.rotateCcw, size: 15, color: palette.textPrimary)
                        Text(Copy.text("Reset View"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(palette.bgCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityIdentifier("bodyResetButton")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(BodyRegionID.allCases) { region in
                        let isSelected = selectedRegion == region
                        Button {
                            if isSelected {
                                selectedRegion = nil
                            } else {
                                selectedRegion = region
                                isBackView = region.isBackFacing
                            }
                        } label: {
                            Text(Copy.text(region.localizationKey))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isSelected ? .white : palette.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected ? palette.accent : palette.bgCardElevated,
                                    in: Capsule()
                                )
                        }
                    }
                }
            }
        }
        .cardSurface(palette: palette, cornerRadius: 24, padding: 14)
    }

    // MARK: - Search & Filters

    private var searchFieldCard: some View {
        HStack(spacing: 8) {
            SvgIconView(.search, size: 16, color: palette.textSecondary)
            TextField(Copy.text("Search exercises"), text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("exerciseSearchField")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    SvgIconView(.x, size: 15, color: palette.textSecondary)
                }
                .accessibilityLabel(Copy.text("Reset"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(palette.bgCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.borderSubtle, lineWidth: 1)
        )
    }

    private var bodyPartFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(
                    label: Copy.text("All"),
                    isSelected: selectedBodyPart == nil && selectedRegion == nil
                ) {
                    selectedBodyPart = nil
                    selectedTarget = nil
                    selectedRegion = nil
                }

                ForEach(BodyPart.allCases) { part in
                    filterPill(
                        label: Copy.text(part.localizationKey),
                        isSelected: selectedBodyPart == part
                    ) {
                        selectedRegion = nil
                        if selectedBodyPart == part {
                            selectedBodyPart = nil
                            selectedTarget = nil
                        } else {
                            selectedBodyPart = part
                            selectedTarget = nil
                        }
                    }
                }
            }
        }
    }

    private var targetSubFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(
                    label: Copy.text("All"),
                    isSelected: selectedTarget == nil
                ) {
                    selectedTarget = nil
                }

                ForEach(availableTargets) { target in
                    filterPill(
                        label: Copy.text(target.localizationKey),
                        isSelected: selectedTarget == target
                    ) {
                        selectedTarget = selectedTarget == target ? nil : target
                    }
                }
            }
        }
    }

    private var equipmentFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(
                    label: Copy.text("All"),
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }

                ForEach(EquipmentCategory.allCases) { category in
                    filterPill(
                        label: Copy.text(category.localizationKey),
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
        }
    }

    private func filterPill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? palette.accent : palette.bgCard, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.clear : palette.borderSubtle, lineWidth: 1)
                )
        }
    }

    // MARK: - Results List

    @ViewBuilder
    private var resultsSection: some View {
        if results.isEmpty {
            VStack(spacing: 12) {
                SvgIconView(.search, size: 32, color: palette.textSecondary)
                Text(Copy.text("No exercises found"))
                    .font(.headline)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .cardSurface(palette: palette)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(results) { exercise in
                    NavigationLink {
                        ExerciseDetailView(exercise: exercise)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(exercise.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(palette.textPrimary)
                                    .multilineTextAlignment(.leading)

                                HStack(spacing: 6) {
                                    Text(Copy.text(exercise.target.localizationKey))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(palette.accent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(palette.accentMuted, in: Capsule())

                                    Text(Copy.text(exercise.equipment.localizationKey))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(palette.textSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(palette.bgCardElevated, in: Capsule())
                                }
                            }
                            Spacer()
                            SvgIconView(.chevronRight, size: 16, color: palette.textSecondary)
                        }
                        .padding(14)
                        .background(palette.bgCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(palette.borderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
