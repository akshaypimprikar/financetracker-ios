import SwiftUI

struct AddCategorySheet: View {
    @Bindable var categoryVM: CategoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type = CategoryType.expense
    @State private var icon = "tag.fill"

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var nearDuplicate: Category? {
        guard !trimmedName.isEmpty else { return nil }
        return categoryVM.findNearDuplicate(named: trimmedName, type: type)
    }
    private var canAdd: Bool { !trimmedName.isEmpty && nearDuplicate == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("category-name-field")
                    if let nearDuplicate {
                        Text("A similar category already exists: '\(nearDuplicate.name)'")
                            .font(Theme.Typography.rowSubtitle)
                            .foregroundStyle(Theme.Colors.destructive)
                            .accessibilityIdentifier("category-duplicate-warning")
                    }
                    Picker("Type", selection: $type) {
                        ForEach(CategoryType.allCases, id: \.self) { t in
                            Text(t.rawValue.capitalized).tag(t)
                        }
                    }
                    TextField("Icon (SF Symbol name)", text: $icon)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard canAdd else { return }
                        try? categoryVM.add(name: trimmedName, icon: icon,
                                            colorHex: "#888888", type: type)
                        dismiss()
                    }
                    .disabled(!canAdd)
                    .accessibilityIdentifier("add-category-confirm")
                }
            }
        }
    }
}
