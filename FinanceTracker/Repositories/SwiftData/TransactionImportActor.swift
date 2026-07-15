import Foundation
import SwiftData

@ModelActor
actor TransactionImportActor: TransactionImportWriting {
    private var cachedAccount: (id: UUID, account: Account)?

    func existingHashes() async throws -> Set<String> {
        var descriptor = FetchDescriptor<Transaction>()
        descriptor.propertiesToFetch = [\.importHash]
        let all = try modelContext.fetch(descriptor)
        return Set(all.compactMap(\.importHash))
    }

    func save(chunk: [ParsedTransaction], accountID: UUID) async throws {
        try Task.checkCancellation()
        let account = try resolveAccount(id: accountID)
        for parsed in chunk {
            let tx = Transaction(
                date: parsed.date,
                amount: parsed.amount,
                payee: parsed.payee,
                type: .debit,
                importHash: parsed.importHash,
                account: account
            )
            modelContext.insert(tx)
        }
        try modelContext.save()   // ONE save() per chunk, never per row
    }

    /// A single CSV import always targets one account, but `save(chunk:accountID:)`
    /// runs once per chunk — cache the resolved account so a 10k-row import doesn't
    /// re-fetch the same account 30+ times. Delegates to the existing
    /// SwiftDataAccountRepository fetch-by-id logic rather than duplicating it.
    private func resolveAccount(id: UUID) throws -> Account {
        if let cachedAccount, cachedAccount.id == id {
            return cachedAccount.account
        }
        guard let account = try SwiftDataAccountRepository(context: modelContext).fetch(id: id) else {
            throw TransactionImportError.accountNotFound
        }
        cachedAccount = (id, account)
        return account
    }
}
