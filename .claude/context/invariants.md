# Project Invariants

These rules are inviolable. No agent may override them.

1. All money values must use `Decimal`, not `Double`.
2. `Transaction.importHash` = SHA256(date+amount+payee) — must never be regenerated on re-import.
3. Domain Services have zero SwiftData imports — must be unit-testable without a simulator.
4. ViewModels depend on repository protocols, never concrete SwiftData implementations.
5. `AccountType.creditCard` is a liability — negative balance reduces net worth.
6. Any `Sendable` Repository/Service protocol meant to be conformed to by an `actor` must be declared `nonisolated` (gated `#if compiler(>=6.4)` — see `TransactionImportWriting.swift`), never left to the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` default. An actor cannot conform to a protocol the compiler infers as `@MainActor`-isolated, and no per-conformance annotation works around it.
