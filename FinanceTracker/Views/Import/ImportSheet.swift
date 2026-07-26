import SwiftUI
import UniformTypeIdentifiers

struct ImportSheet: View {
    @Bindable var viewModel: ImportViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isPickingFile = false
    @State private var dateColIndex = 0
    @State private var amountColIndex = 1
    @State private var payeeColIndex = 2
    @State private var hasHeader = true

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .filePicker:    filePickerStep
                case .columnMapping: columnMappingStep
                case .preview:       previewStep
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelImport()
                        viewModel.reset()
                        dismiss()
                    }
                    .accessibilityIdentifier("import-cancel-toolbar-button")
                }
            }
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            guard let url = try? result.get() else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            viewModel.loadCSV(text)
        }
        .onAppear {
            viewModel.onImportCompleted = { dismiss() }
        }
        .onDisappear {
            // Same cleanup as the toolbar Cancel button — swipe-to-dismiss shouldn't
            // leave step/pendingTransactions stale for the next time this sheet opens.
            viewModel.cancelImport()
            viewModel.reset()
        }
        .alert(
            "Import Problem",
            isPresented: Binding(
                get: { viewModel.importFailure != nil },
                set: { isPresented in
                    if !isPresented { viewModel.reset() }
                }
            ),
            presenting: viewModel.importFailure
        ) { _ in
            Button("OK") { }
        } message: { failure in
            Text(failureMessage(for: failure))
        }
    }

    private func failureMessage(for failure: ImportFailure) -> String {
        switch failure {
        case .partiallyFailed(let count):
            return count > 0
                ? "\(pluralized(count)) were imported before an error occurred. The rest were not imported — you can try again."
                : "The import could not be completed. No transactions were imported."
        case .recordSaveFailed(let count):
            return "All \(pluralized(count)) were imported successfully, but the import summary couldn't be saved."
        }
    }

    private func pluralized(_ count: Int) -> String {
        "\(count) transaction\(count == 1 ? "" : "s")"
    }

    @ViewBuilder
    private func categoryChip(for tx: ParsedTransaction) -> some View {
        if let (text, sparkleOpacity) = chipContent(for: tx) {
            categoryMenu(for: tx) {
                chipLabel(text: text, sparkleOpacity: sparkleOpacity)
            }
            .accessibilityIdentifier("import-category-chip-\(tx.importHash)")
        }
    }

    private func chipContent(for tx: ParsedTransaction) -> (text: String, sparkleOpacity: Double?)? {
        if let categoryID = tx.categoryID,
           let category = viewModel.categories.first(where: { $0.id == categoryID }) {
            return (category.name, nil)
        }
        if let suggestion = viewModel.suggestions[tx.payee] {
            return (suggestion.categoryName, opacity(for: suggestion.confidence))
        }
        return nil
    }

    private func chipLabel(text: String, sparkleOpacity: Double?) -> some View {
        HStack(spacing: Theme.Spacing.tight) {
            if let sparkleOpacity {
                Image(systemName: "sparkle")
                    .opacity(sparkleOpacity)
            }
            Text(text)
                .font(Theme.Typography.chipLabel)
        }
        .padding(.horizontal, Theme.Spacing.contentSpacing)
        .padding(.vertical, Theme.Spacing.compact)
        .background(Theme.Chips.suggestionBackground)
        .foregroundStyle(Theme.Colors.primaryInteractive)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func categoryMenu<Label: View>(
        for tx: ParsedTransaction,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Menu {
            ForEach(viewModel.categories) { category in
                Button(category.name) {
                    viewModel.setCategory(categoryID: category.id, forPayee: tx.payee)
                }
            }
        } label: {
            label()
        }
    }

    private func opacity(for confidence: CategorySuggestion.Confidence) -> Double {
        switch confidence {
        case .high:   Theme.Chips.confidenceHigh
        case .medium: Theme.Chips.confidenceMedium
        case .low:    Theme.Chips.confidenceLow
        }
    }

    private var stepTitle: String {
        switch viewModel.step {
        case .filePicker:    "Import CSV"
        case .columnMapping: "Map Columns"
        case .preview:       "Review Import"
        }
    }

    // MARK: Step 1 — File picker

    private var filePickerStep: some View {
        VStack(spacing: Theme.Spacing.sheetSpacing) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 72))
                .foregroundStyle(Theme.Colors.primaryInteractive)
            Text("Choose a CSV file to import")
                .font(Theme.Typography.sectionHeader)
            Text("Supported: comma- or semicolon-delimited, any column order")
                .font(Theme.Typography.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Choose File") { isPickingFile = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("import-choose-file-button")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: Step 2 — Column mapping

    private var columnMappingStep: some View {
        Form {
            Section("Column Positions (0-based)") {
                Stepper("Date: column \(dateColIndex)",
                        value: $dateColIndex, in: 0...20)
                Stepper("Amount: column \(amountColIndex)",
                        value: $amountColIndex, in: 0...20)
                Stepper("Payee: column \(payeeColIndex)",
                        value: $payeeColIndex, in: 0...20)
                Toggle("First row is header", isOn: $hasHeader)
            }

            if !viewModel.csvSampleRows.isEmpty {
                Section("File preview (first rows)") {
                    ForEach(Array(viewModel.csvSampleRows.prefix(4).enumerated()), id: \.offset) { _, row in
                        Text(row.enumerated().map { "\($0.offset):\($0.element)" }.joined(separator: "  "))
                            .font(Theme.Typography.code)
                            .lineLimit(1)
                    }
                }
            }

            Section {
                Button("Parse & Preview") {
                    let mapping = ColumnMapping(
                        dateIndex: dateColIndex,
                        amountIndex: amountColIndex,
                        payeeIndex: payeeColIndex,
                        hasHeader: hasHeader
                    )
                    Task {
                        try? await viewModel.applyMapping(mapping)
                        await viewModel.loadSuggestions()
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("import-parse-preview-button")
            }
        }
    }

    // MARK: Step 3 — Preview & confirm

    private var previewStep: some View {
        List {
            Section {
                HStack {
                    Text("New transactions")
                    Spacer()
                    Text("\(viewModel.pendingTransactions.count)")
                        .bold()
                        .foregroundStyle(Theme.Colors.positive)
                }
                HStack {
                    Text("Skipped (duplicates)")
                    Spacer()
                    Text("\(viewModel.skippedCount)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Import into account") {
                Picker("Account", selection: $viewModel.selectedAccount) {
                    ForEach(viewModel.accounts) { account in
                        Text(account.name).tag(account as Account?)
                    }
                }
            }

            if !viewModel.pendingTransactions.isEmpty {
                Section("Transactions to import") {
                    ForEach(viewModel.pendingTransactions, id: \.importHash) { tx in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.payee)
                                Text(tx.date,
                                     format: .dateTime.month(.abbreviated).day().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: Theme.Spacing.tight) {
                                categoryChip(for: tx)
                                Text(tx.amount, format: .currency(code: viewModel.selectedAccount?.currency ?? Locale.current.currency?.identifier ?? "USD"))
                            }
                        }
                    }
                }
            }

            Section {
                if viewModel.isImporting {
                    VStack(spacing: Theme.Spacing.sheetSpacing) {
                        ProgressView(value: viewModel.progress)
                            .tint(Theme.Colors.primaryInteractive)
                            .accessibilityIdentifier("import-progress-bar")
                        Button("Cancel Import") {
                            viewModel.cancelImport()
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("import-cancel-button")
                    }
                } else {
                    Button("Import \(viewModel.pendingTransactions.count) Transactions") {
                        viewModel.startImport()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.pendingTransactions.isEmpty ||
                              viewModel.selectedAccount == nil)
                    .accessibilityIdentifier("import-confirm-button")
                }
            }
        }
    }
}
