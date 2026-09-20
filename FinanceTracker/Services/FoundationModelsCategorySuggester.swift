import Foundation
import FoundationModels

/// The one concrete CategorySuggesting implementation the app ships. Not itself
/// unit-testable in CI — requires live Apple Intelligence-eligible hardware or an
/// Apple Intelligence-enabled host Mac's Simulator (see decisions.md 2026-07-21).
/// ImportViewModelTests exercises the ViewModel against FakeCategorySuggesting instead.
struct FoundationModelsCategorySuggester: CategorySuggesting {
    /// `isAvailable`'s isolation depends on which `#if compiler(>=6.4)` branch of
    /// `CategorySuggesting` is active: `nonisolated` under Xcode 27/Swift 6.4+, but still
    /// implicitly `@MainActor`-isolated under CI's Swift 6.2 `#else` branch — the two
    /// toolchains compile this property under genuinely different isolation. Safe today
    /// either way only because `SystemLanguageModel` is Sendable/non-MainActor; this file
    /// isn't unit-tested in CI (see the type-level doc comment above), so a future edit
    /// adding MainActor-bound state here won't get caught by tests under either toolchain —
    /// check isolation by hand before adding any.
    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func suggestCategory(payee: String, candidates: [CategoryCandidate]) async -> CategorySuggestionResult? {
        guard isAvailable else { return nil }

        let categoryNames = candidates.map(\.name).joined(separator: ", ")
        let session = LanguageModelSession(model: SystemLanguageModel.default) {
            "You categorize personal finance transactions by payee name. Always pick from the exact category names given, or say Uncategorized if none fit."
        }

        let prompt = """
        Payee: \(payee)
        Existing categories: \(categoryNames)

        Suggest the single best-matching category for this payee from the list above.
        """

        guard let response = try? await session.respond(to: prompt, generating: CategorySuggestion.self) else {
            return nil
        }

        let suggestion = response.content
        guard suggestion.categoryName.caseInsensitiveCompare("Uncategorized") != .orderedSame else {
            return nil
        }

        // CSV import always creates .debit transactions (see TransactionImportActor) —
        // matching is scoped to .expense so an Income category sharing a suggested name
        // (e.g. "Interest") can never be attached to an imported expense transaction.
        let matchedCategoryID = candidates.first(where: {
            CategoryNameMatching.isNearDuplicate($0.name, $0.type, suggestion.categoryName, .expense)
        })?.id
        return CategorySuggestionResult(suggestion: suggestion, matchedCategoryID: matchedCategoryID)
    }
}
