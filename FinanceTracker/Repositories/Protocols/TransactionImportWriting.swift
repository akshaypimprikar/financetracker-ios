import Foundation

protocol TransactionImportWriting: Sendable {
    /// All `importHash` values currently in the store, fetched once rather than
    /// checked per row — see docs/superpowers/specs/2026-07-15-csv-import-async-migration.md.
    func existingHashes() async throws -> Set<String>

    /// Inserts and saves one chunk of parsed rows against the account identified by
    /// `accountID`. Exactly one `save()` per call — never per row.
    ///
    /// `accountID` is `UUID` (the existing `Account.id` domain identity), not
    /// `PersistentIdentifier` — the latter is a SwiftData type and would violate
    /// the Foundation-only-imports rule for Repository Protocols. See the
    /// deviation note in docs/superpowers/plans/2026-07-15-csv-import-async-migration.md.
    func save(chunk: [ParsedTransaction], accountID: UUID) async throws
}

enum TransactionImportError: Error, Equatable {
    case accountNotFound
}
