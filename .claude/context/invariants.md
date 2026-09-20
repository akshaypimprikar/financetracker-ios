# Project Invariants

These rules are inviolable. No agent may override them.

1. All money values must use `Decimal`, not `Double`.
2. `Transaction.importHash` = SHA256(date+amount+payee) — must never be regenerated on re-import.
3. Domain Services have zero SwiftData imports — must be unit-testable without a simulator.
4. ViewModels depend on repository protocols, never concrete SwiftData implementations.
5. `AccountType.creditCard` is a liability — negative balance reduces net worth.
6. Any `Sendable` Repository/Service protocol meant to be conformed to by an `actor` must be declared `nonisolated`, never left to the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` default. An actor cannot conform to a protocol the compiler infers as `@MainActor`-isolated, and no per-conformance annotation works around it. `nonisolated` on a protocol declaration isn't recognized by CI's Swift 6.2 compiler, so gate it `#if compiler(>=6.4) / #else / #endif` with the *plain, unmodified* protocol declaration duplicated verbatim in the `#else` branch — never omit the `#else` branch, or the protocol won't exist at all under CI's compiler. See `TransactionImportWriting.swift` for the full pattern.
