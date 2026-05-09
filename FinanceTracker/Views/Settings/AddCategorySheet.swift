import SwiftUI

struct AddCategorySheet: View {
    @Bindable var categoryVM: CategoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type = CategoryType.expense
    @State private var icon = "tag.fill"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
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
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        try? categoryVM.add(name: name, icon: icon,
                                            colorHex: "#888888", type: type)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
