import Foundation
import Observation

enum ImportStep: Equatable {
    case filePicker, columnMapping, preview
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
    private(set) var isImporting = false
    private(set) var importError: Error?
    var selectedAccount: Account?

    private let accountRepo: any AccountRepositoryProtocol
    private let importRecordRepo: any ImportRecordRepositoryProtocol
    private let importService: CSVImportService
    private let importWriter: any TransactionImportWriting
    private let chunkSize: Int
    private var importTask: Task<Void, Error>?

    init(
        accountRepo: any AccountRepositoryProtocol,
        importRecordRepo: any ImportRecordRepositoryProtocol,
        importWriter: any TransactionImportWriting,
        importService: CSVImportService = CSVImportService(),
        chunkSize: Int = 300
    ) {
        self.accountRepo = accountRepo
        self.importRecordRepo = importRecordRepo
        self.importWriter = importWriter
        self.importService = importService
        self.chunkSize = chunkSize
    }

    func load() throws {
        accounts = try accountRepo.fetchAll()
        if selectedAccount == nil { selectedAccount = accounts.first }
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

    func startImport(filename: String = "import.csv") {
        guard !isImporting, let account = selectedAccount, !pendingTransactions.isEmpty else { return }
        let accountID = account.id
        let items = pendingTransactions
        // Captured into a local so each chunk's child task only holds this
        // Sendable protocol existential, not the whole ImportViewModel via `self`.
        let writer = importWriter

        isImporting = true
        progress = 0
        importError = nil

        importTask = Task {
            defer { isImporting = false; importTask = nil }
            do {
                let chunks = items.chunked(into: chunkSize)
                var completed = 0
                try await withThrowingTaskGroup(of: Int.self) { group in
                    for (index, chunk) in chunks.enumerated() {
                        group.addTask(name: "CSV import chunk \(index)") {
                            try await writer.save(chunk: chunk, accountID: accountID)
                            return chunk.count
                        }
                    }
                    for try await count in group {
                        completed += count
                        self.progress = Double(completed) / Double(items.count)
                    }
                }
                let record = ImportRecord(filename: filename, transactionCount: items.count)
                try importRecordRepo.save(record)
                reset()
            } catch {
                // Some chunks may already be persisted (cancellation or a mid-run
                // failure both land here). Clear pendingTransactions rather than
                // leaving the stale pre-import list in place — a re-tap of Import
                // must not re-send rows that already made it into SwiftData.
                // Recovering the exact remaining set is a future enhancement; the
                // safe behavior for now is forcing a fresh applyMapping() dedup pass.
                pendingTransactions = []
                skippedCount = 0
                importError = error
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    func reset() {
        step = .filePicker
        rawCSVText = ""
        csvSampleRows = []
        pendingTransactions = []
        skippedCount = 0
        progress = 0
    }
}

private extension Array {
    /// `size` is a caller contract (always a small positive int — see chunkSize),
    /// not defensively branched on.
    func chunked(into size: Int) -> [[Element]] {
        guard !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
