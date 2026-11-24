import SwiftUI

struct ExercisePickerSheet: View {
    let titleKey: String
    let excludedIDs: Set<String>
    let onSelect: (ExerciseRecord) -> Void

    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedBodyPart: BodyPart?
    @State private var selectedCategory: EquipmentCategory?

    init(
        titleKey: String = "Add Exercise",
        excludedIDs: Set<String> = [],
        onSelect: @escaping (ExerciseRecord) -> Void
    ) {
        self.titleKey = titleKey
        self.excludedIDs = excludedIDs
        self.onSelect = onSelect
    }

    private var results: [ExerciseRecord] {
        ExerciseLibraryLoader.shared
            .search(
                query: searchText,
                bodyPart: selectedBodyPart,
                equipmentCategory: selectedCategory
            )
            .filter { !excludedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchBar
                bodyPartFilterRow
                equipmentFilterRow
                resultsList
            }
            .padding(.top, 8)
            .background(palette.bgCanvas)
            .navigationTitle(Copy.text(titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.text("Close")) { dismiss() }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            SvgIconView(.search, size: 16, color: palette.textSecondary)
            TextField(Copy.text("Search exercises"), text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    SvgIconView(.x, size: 15, color: palette.textSecondary)
                }
                .accessibilityLabel(Copy.text("Reset"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.bgCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderSubtle, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var bodyPartFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(
                    label: Copy.text("All"),
                    isSelected: selectedBodyPart == nil
                ) {
                    selectedBodyPart = nil
                }
                ForEach(BodyPart.allCases) { part in
                    filterPill(
                        label: Copy.text(part.localizationKey),
                        isSelected: selectedBodyPart == part
                    ) {
                        selectedBodyPart = selectedBodyPart == part ? nil : part
                    }
                }
            }
            .padding(.horizontal, 16)
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
            .padding(.horizontal, 16)
        }
    }

    private func filterPill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isSelected ? palette.accent : palette.bgCard,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.clear : palette.borderSubtle, lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                SvgIconView(.search, size: 32, color: palette.textSecondary)
                Text(Copy.text("No exercises found"))
                    .font(.headline)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(results) { exercise in
                        Button {
                            onSelect(exercise)
                            dismiss()
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
                                SvgIconView(.plus, size: 18, color: palette.accent)
                            }
                            .padding(14)
                            .background(palette.bgCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(palette.borderSubtle, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }
}
