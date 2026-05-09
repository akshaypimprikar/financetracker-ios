import Testing
import Foundation
import SwiftData
@testable import FinanceTracker

@Suite("ImportViewModel")
struct ImportViewModelTests {

    @Test func loadCSVAdvancesToColumnMapping() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let vm = ImportViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx)
        )

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop"
        vm.loadCSV(csv)

        #expect(vm.step == .columnMapping)
        #expect(!vm.csvSampleRows.isEmpty)
    }

    @Test func applyMappingParsesTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let vm = ImportViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx)
        )

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop\n2026-05-02,1200.00,Rent"
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try vm.applyMapping(mapping)

        #expect(vm.step == .preview)
        #expect(vm.pendingTransactions.count == 2)
        #expect(vm.skippedCount == 0)
    }

    @Test func applyMappingDeduplicatesExistingTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)

        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let hash = CSVImportService.importHash(
            date: date, amount: Decimal(string: "25.50")!, payee: "Coffee Shop"
        )
        let existing = Transaction(
            date: date, amount: Decimal(string: "25.50")!, payee: "Coffee Shop",
            type: .debit, importHash: hash, account: account
        )
        ctx.insert(existing)
        try ctx.save()

        let vm = ImportViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx)
        )

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop\n2026-05-02,50.00,Grocery"
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try vm.applyMapping(mapping)

        #expect(vm.pendingTransactions.count == 1)
        #expect(vm.skippedCount == 1)
        #expect(vm.pendingTransactions[0].payee == "Grocery")
    }

    @Test func confirmImportSavesTransactionsAndRecord() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let vm = ImportViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx)
        )
        try vm.load()

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop"
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try vm.applyMapping(mapping)
        try vm.confirmImport(filename: "test.csv")

        let txs = try SwiftDataTransactionRepository(context: ctx).fetchAll()
        let records = try SwiftDataImportRecordRepository(context: ctx).fetchAll()

        #expect(txs.count == 1)
        #expect(txs[0].payee == "Coffee Shop")
        #expect(records.count == 1)
        #expect(records[0].transactionCount == 1)
        #expect(vm.step == .filePicker)
    }
}
