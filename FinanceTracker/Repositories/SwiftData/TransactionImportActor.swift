import Foundation
import SwiftData

@ModelActor
actor TransactionImportActor: TransactionImportWriting {
    private var cachedAccount: (id: UUID, account: Account)?
    private var cachedCategories: [UUID: Category?] = [:]   // caches misses too, not just hits

    /// No `propertiesToFetch` here — deliberately. SwiftData doesn't limit the SQL
    /// column list the way Core Data's `propertiesToFetch` does: it still issues one
    /// extra full-column `SELECT ... WHERE Z_PK = ?` per returned row when a property
    /// is accessed, on top of the narrower initial query. Confirmed via live SQL debug
    /// logging (`com.apple.CoreData.SQLDebug`) against this exact method: 1 narrow
    /// query + N full-row queries, versus 1 single full-column query with no
    /// `propertiesToFetch` at all. It's not a missed optimization — it was actively
    /// worse than a plain fetch.
    func existingHashes() async throws -> Set<String> {
        let descriptor = FetchDescriptor<Transaction>()
        let all = try modelContext.fetch(descriptor)
        return Set(all.compactMap(\.importHash))
    }

    func save(chunk: [ParsedTransaction], accountID: UUID) async throws {
        try Task.checkCancellation()
        let account = try resolveAccount(id: accountID)
        for parsed in chunk {
            let category = parsed.categoryID.flatMap { resolveCategory(id: $0) }
            let tx = Transaction(
                date: parsed.date,
                amount: parsed.amount,
                payee: parsed.payee,
                type: .debit,
                importHash: parsed.importHash,
                account: account,
                category: category
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

    /// Mirrors resolveAccount's cache pattern, but never throws — a category is
    /// optional on Transaction, so a stale/missing categoryID (e.g. deleted between
    /// preview and import) degrades to an uncategorized transaction rather than
    /// failing the whole chunk. Stays private — never crosses the actor's public
    /// boundary, so this doesn't violate Gate 8's "no @Model type crossing the
    /// actor's public boundary" check, identical to how cachedAccount already works.
    ///
    /// Caches misses (a nil entry), not just hits — a stale categoryID shared by
    /// many rows in a chunk would otherwise re-fetch for that same known-missing
    /// id on every row instead of once per import.
    private func resolveCategory(id: UUID) -> Category? {
        if let cached = cachedCategories[id] {
            return cached
        }
        var descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        let category = try? modelContext.fetch(descriptor).first
        cachedCategories[id] = category
        return category
    }
}
