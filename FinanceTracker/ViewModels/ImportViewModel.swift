import Foundation
import Observation

enum ImportStep: Equatable {
    case filePicker, columnMapping, preview
}

enum ImportFailure: Equatable {
    /// Some chunks failed. `persistedCount` transactions from the chunks that
    /// completed before the failure are already durably saved; a best-effort
    /// `ImportRecord` was written for that partial count so there's an audit
    /// trail even for an incomplete import.
    case partiallyFailed(persistedCount: Int)
    /// Every transaction was successfully persisted, but the bookkeeping `ImportRecord`
    /// itself failed to save. No transaction data was lost.
    case recordSaveFailed(persistedCount: Int)
}

@Observable
final class ImportViewModel {
    private(set) var step: ImportStep = .filePicker
    private(set) var rawCSVText: String = ""
    private(set) var csvSampleRows: [[String]] = []
    private(set) var pendingTransactions: [ParsedTransaction] = []
    private(set) var skippedCount: Int = 0
    private(set) var accounts: [Account] = []
    private(set) var progress: Double = 0
    private(set) var importFailure: ImportFailure?
    private(set) var categories: [Category] = []
    /// Categories created via `createAndAssignCategory` during this preview session but
    /// not yet persisted — only written to `categoryRepo` if `startImport()` actually
    /// succeeds, so cancelling the sheet without importing never leaves an orphan
    /// category with zero transactions sitting in the store.
    private(set) var pendingNewCategories: [Category] = []
    private(set) var suggestions: [String: CategorySuggestionResult] = [:]   // keyed by payee
    /// Existing + this-session's not-yet-persisted categories — the full set a chip's
    /// `Menu` or a confirmed-chip lookup should consider, since a category the user just
    /// tapped "Create" on must behave like any other pickable category immediately,
    /// even before it's actually saved.
    var allCategories: [Category] { categories + pendingNewCategories }
    var isImporting: Bool { importTask != nil }
    var selectedAccount: Account?
    /// Explicit completion signal for the View to dismiss on — not inferred from
    /// `step`, since `step` returning to `.filePicker` is also the initial state
    /// and would overload a future "start over" affordance with silent auto-dismiss.
    var onImportCompleted: (() -> Void)?

    private let accountRepo: any AccountRepositoryProtocol
    private let importRecordRepo: any ImportRecordRepositoryProtocol
    private let importService: CSVImportService
    private let importWriter: any TransactionImportWriting
    private let categoryRepo: any CategoryRepositoryProtocol
    private let categorySuggester: any CategorySuggesting
    private let chunkSize: Int
    private var importTask: Task<Void, Error>?
    /// Bumped by every `startImport()` and `reset()`. A task's completion handlers
    /// (catch/success blocks) compare their captured generation against the current
    /// one before mutating any state the user could currently be looking at — so a
    /// stale, still-unwinding task from a prior session can't clobber a session the
    /// user has since started fresh (e.g. cancel, then immediately load a new CSV).
    /// Writing the best-effort audit ImportRecord is NOT gated by this — persisting
    /// an accurate record of what actually landed in the store matters regardless of
    /// which session is currently on screen.
    private var importGeneration = 0

    init(
        accountRepo: any AccountRepositoryProtocol,
        importRecordRepo: any ImportRecordRepositoryProtocol,
        importWriter: any TransactionImportWriting,
        categoryRepo: any CategoryRepositoryProtocol,
        categorySuggester: any CategorySuggesting = FoundationModelsCategorySuggester(),
        importService: CSVImportService = CSVImportService(),
        chunkSize: Int = 300
    ) {
        self.accountRepo = accountRepo
        self.importRecordRepo = importRecordRepo
        self.importWriter = importWriter
        self.categoryRepo = categoryRepo
        self.categorySuggester = categorySuggester
        self.importService = importService
        self.chunkSize = chunkSize
    }

    func load() throws {
        accounts = try accountRepo.fetchAll()
        if selectedAccount == nil { selectedAccount = accounts.first }
        categories = try categoryRepo.fetchAll()
    }

    func loadCSV(_ text: String) {
        rawCSVText = text
        let delimiter: Character = text.contains(";") ? ";" : ","
        let lines = text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        csvSampleRows = lines.prefix(5).map {
            $0.components(separatedBy: String(delimiter))
              .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        step = .columnMapping
    }

    func applyMapping(_ mapping: ColumnMapping) async throws {
        let parsed = try importService.parse(csv: rawCSVText, mapping: mapping)
        let existingHashes = try await importWriter.existingHashes()
        let deduped = importService.deduplicated(parsed: parsed, existingHashes: existingHashes)
        pendingTransactions = deduped
        skippedCount = parsed.count - deduped.count
        step = .preview
    }

    func loadSuggestions() async {
        // No !categories.isEmpty guard here — a brand-new user's first CSV import
        // routinely has zero existing categories, and the model must still be able
        // to propose a brand-new one rather than going silent. That's now the
        // primary path (no default categories are ever seeded), not an edge case.
        guard categorySuggester.isAvailable else { return }
        // Captured so a dismiss-then-reopen (reset() bumps importGeneration) stops
        // this loop from writing suggestions into a session the user has since left —
        // same stale-task guard startImport() uses, needed here because this call
        // isn't wrapped in a tracked/cancellable Task the way startImport()'s is.
        let generation = importGeneration
        let candidates = categories.map { CategoryCandidate(id: $0.id, name: $0.name) }
        let uniquePayees = Set(pendingTransactions.map(\.payee))
        for payee in uniquePayees {
            if let result = await categorySuggester.suggestCategory(payee: payee, candidates: candidates) {
                guard generation == importGeneration else { return }
                suggestions[payee] = result
            }
        }
    }

    func setCategory(categoryID: UUID, forPayee payee: String) {
        for index in pendingTransactions.indices where pendingTransactions[index].payee == payee {
            pendingTransactions[index].categoryID = categoryID
        }
    }

    /// Creates a category from the model's proposed name (or reuses an existing
    /// near-duplicate instead of inserting a second one — see CategoryNameMatching),
    /// assigns it to this payee's rows, then re-checks every other still-unconfirmed
    /// cached suggestion against the updated category list. The rematch is cheap pure
    /// string comparison, not a new model call — it exists because loadSuggestions()
    /// computes suggestions for a whole CSV in one batch, before the user has tapped
    /// anything, so two payees can independently propose the same new category name.
    ///
    /// A newly created category is NOT persisted here — only staged in
    /// `pendingNewCategories` — so cancelling out of preview without importing never
    /// leaves a real, unused category behind. `startImport()` persists it for real.
    func createAndAssignCategory(named name: String, forPayee payee: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let category: Category
        if let existing = allCategories.first(where: { CategoryNameMatching.isNearDuplicate($0.name, trimmed) }) {
            category = existing
        } else {
            category = Category(name: trimmed, type: .expense)
            pendingNewCategories.append(category)
        }
        setCategory(categoryID: category.id, forPayee: payee)
        rematchPendingSuggestions(against: category)
    }

    private func rematchPendingSuggestions(against category: Category) {
        for (payee, result) in suggestions where result.matchedCategoryID == nil {
            guard CategoryNameMatching.isNearDuplicate(category.name, result.suggestion.categoryName) else { continue }
            suggestions[payee] = CategorySuggestionResult(suggestion: result.suggestion, matchedCategoryID: category.id)
        }
    }

    func startImport(filename: String = "import.csv") {
        guard !isImporting, let account = selectedAccount, !pendingTransactions.isEmpty else { return }
        let accountID = account.id
        let items = pendingTransactions
        // Captured into a local so each chunk's child task only holds this
        // Sendable protocol existential, not the whole ImportViewModel via `self`.
        let writer = importWriter

        importGeneration += 1
        let generation = importGeneration
        progress = 0
        importFailure = nil

        importTask = Task {
            defer { importTask = nil }

            // Persist this session's staged categories before any chunk writes a
            // transaction referencing one by id — TransactionImportActor resolves
            // categoryID against the store directly, so an unsaved category would
            // otherwise silently resolve to nil (transaction saved uncategorized).
            var savedCategories: [Category] = []
            do {
                for category in pendingNewCategories {
                    try categoryRepo.save(category)
                    savedCategories.append(category)
                }
            } catch {
                // Roll back whatever did persist before the failure — an all-or-nothing
                // guarantee for this session's staged categories, matching the same
                // "no orphan category" invariant a plain cancel already upholds. Without
                // this, a failure on the Nth of N saves would leave the first N-1 as
                // real, permanent categories with zero transactions and zero budget.
                for category in savedCategories {
                    try? categoryRepo.delete(category)
                }
                guard generation == self.importGeneration else { return }
                clearCurrentAttempt()
                importFailure = .partiallyFailed(persistedCount: 0)
                return
            }
            categories.append(contentsOf: pendingNewCategories)
            pendingNewCategories = []

            let chunks = items.chunked(into: chunkSize)
            var completed = 0

            do {
                try await withThrowingTaskGroup(of: Int.self) { group in
                    for (index, chunk) in chunks.enumerated() {
                        group.addTask(name: "CSV import chunk \(index)") {
                            try await writer.save(chunk: chunk, accountID: accountID)
                            return chunk.count
                        }
                    }
                    for try await count in group {
                        completed += count
                        guard generation == self.importGeneration else { continue }
                        self.progress = Double(completed) / Double(items.count)
                    }
                }
            } catch {
                // Some chunks may already be persisted (cancellation or a mid-run
                // failure both land here). Write a best-effort ImportRecord for
                // what actually landed so a partial import still has an audit
                // trail — unconditionally, since this is a data-safety concern
                // independent of which session is currently displayed.
                if completed > 0 {
                    try? importRecordRepo.save(ImportRecord(filename: filename, transactionCount: completed))
                }
                guard generation == importGeneration else { return }
                clearCurrentAttempt()
                // A user-initiated cancel (toolbar Cancel bumps the generation and
                // calls reset() itself, so this branch is for the in-preview "Cancel
                // Import" button, which doesn't) isn't a failure to alert about.
                if !(error is CancellationError) {
                    importFailure = .partiallyFailed(persistedCount: completed)
                }
                return
            }

            do {
                let record = ImportRecord(filename: filename, transactionCount: items.count)
                try importRecordRepo.save(record)
            } catch {
                // Every transaction is already durably persisted — only the
                // bookkeeping record failed. Don't fold this into the chunk-failure
                // path above: the data isn't missing, and a fresh applyMapping()
                // dedup pass would otherwise silently swallow it with no signal
                // that the import actually succeeded.
                guard generation == importGeneration else { return }
                importFailure = .recordSaveFailed(persistedCount: items.count)
                return
            }

            guard generation == importGeneration else { return }
            reset()
            onImportCompleted?()
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    func reset() {
        importGeneration += 1
        step = .filePicker
        rawCSVText = ""
        csvSampleRows = []
        clearCurrentAttempt()
        importFailure = nil
    }

    private func clearCurrentAttempt() {
        pendingTransactions = []
        skippedCount = 0
        progress = 0
        suggestions = [:]
        pendingNewCategories = []
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
