import Foundation

// Swift 6.4 (Xcode 27) infers @MainActor onto this protocol via the project's
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor default. TransactionImportActor's
// conformance then makes its `init(modelContainer:)` main-actor isolated, so the
// nonisolated callers in TransactionImportActorTests get "main actor-isolated
// initializer 'init(modelContainer:)' cannot be called from outside of the actor"
// (a warning in this project's Swift 5 mode, an error in Swift 6 mode; checked on
// Xcode 27.1, 2026-10-23). `nonisolated` on the protocol itself fixes it, but
// that spelling isn't recognized by CI's older (Swift 6.2, Xcode 26.4.1) compiler,
// which never had this issue in the first place — gated to only apply on 6.4+.
#if compiler(>=6.4)
nonisolated protocol TransactionImportWriting: Sendable {
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
#else
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
#endif

enum TransactionImportError: Error, Equatable {
    case accountNotFound
}
