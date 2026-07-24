import Foundation
import FoundationModels

/// The one concrete CategorySuggesting implementation the app ships. Not itself
/// unit-testable in CI — requires live Apple Intelligence-eligible hardware or an
/// Apple Intelligence-enabled host Mac's Simulator (see decisions.md 2026-07-21).
/// ImportViewModelTests exercises the ViewModel against FakeCategorySuggesting instead.
struct FoundationModelsCategorySuggester: CategorySuggesting {
    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func suggestCategory(payee: String, candidates: [CategoryCandidate]) async -> CategorySuggestion? {
        guard isAvailable, !candidates.isEmpty else { return nil }

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
        guard candidates.contains(where: {
            $0.name.caseInsensitiveCompare(suggestion.categoryName) == .orderedSame
        }) else {
            return nil
        }
        return suggestion
    }
}
