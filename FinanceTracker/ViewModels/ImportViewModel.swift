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
    var selectedAccount: Account?

    private let transactionRepo: any TransactionRepositoryProtocol
    private let accountRepo: any AccountRepositoryProtocol
    private let importRecordRepo: any ImportRecordRepositoryProtocol
    private let importService: CSVImportService

    init(
        transactionRepo: any TransactionRepositoryProtocol,
        accountRepo: any AccountRepositoryProtocol,
        importRecordRepo: any ImportRecordRepositoryProtocol,
        importService: CSVImportService = CSVImportService()
    ) {
        self.transactionRepo = transactionRepo
        self.accountRepo = accountRepo
        self.importRecordRepo = importRecordRepo
        self.importService = importService
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

    func applyMapping(_ mapping: ColumnMapping) throws {
        let parsed = try importService.parse(csv: rawCSVText, mapping: mapping)
        var existingHashes = Set<String>()
        for p in parsed {
            if try transactionRepo.existsWithHash(p.importHash) {
                existingHashes.insert(p.importHash)
            }
        }
        let deduped = importService.deduplicated(parsed: parsed, existingHashes: existingHashes)
        pendingTransactions = deduped
        skippedCount = parsed.count - deduped.count
        step = .preview
    }

    func confirmImport(filename: String = "import.csv") throws {
        guard let account = selectedAccount else { return }
        for parsed in pendingTransactions {
            let tx = Transaction(
                date: parsed.date,
                amount: parsed.amount,
                payee: parsed.payee,
                type: .debit,
                importHash: parsed.importHash,
                account: account
            )
            try transactionRepo.save(tx)
        }
        let record = ImportRecord(
            filename: filename,
            transactionCount: pendingTransactions.count
        )
        try importRecordRepo.save(record)
        reset()
    }

    func reset() {
        step = .filePicker
        rawCSVText = ""
        csvSampleRows = []
        pendingTransactions = []
        skippedCount = 0
    }
}
