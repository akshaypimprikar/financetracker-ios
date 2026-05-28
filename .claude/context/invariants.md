# Project Invariants

These rules are inviolable. No agent may override them.

1. All money values must use `Decimal`, not `Double`.
2. `Transaction.importHash` = SHA256(date+amount+payee) — must never be regenerated on re-import.
3. Domain Services have zero SwiftData imports — must be unit-testable without a simulator.
4. ViewModels depend on repository protocols, never concrete SwiftData implementations.
5. `AccountType.creditCard` is a liability — negative balance reduces net worth.
