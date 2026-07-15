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
    /// re-fetch the same account 30+ times.
    ///
    /// Fetches directly on this actor's own `modelContext` rather than delegating to
    /// `SwiftDataAccountRepository` — that repository is implicitly `@MainActor`-isolated
    /// (inferred from `AccountRepositoryProtocol` conformance under
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), so calling it from this actor would
    /// be a cross-actor-isolation violation. Confirmed by compiler warning when tried.
    private func resolveAccount(id: UUID) throws -> Account {
        if let cachedAccount, cachedAccount.id == id {
            return cachedAccount.account
        }
        var descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let account = try modelContext.fetch(descriptor).first else {
            throw TransactionImportError.accountNotFound
        }
        cachedAccount = (id, account)
        return account
    }
}
