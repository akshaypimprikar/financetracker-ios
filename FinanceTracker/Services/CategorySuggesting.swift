import Foundation
import FoundationModels

/// Sendable projection of `Category` — `Category` itself is a SwiftData `@Model`
/// reference type with no Sendable conformance, so it can't safely cross into an
/// actor-isolated conformer of `CategorySuggesting` (e.g. FakeCategorySuggesting).
/// Mirrors the existing `accountID: UUID` precedent on `TransactionImportWriting`:
/// only the identity + display data needed for suggestion/matching crosses the
/// boundary, never the live model object.
struct CategoryCandidate: Sendable {
    let id: UUID
    let name: String
}

/// Domain Service protocol — zero SwiftData imports.
protocol CategorySuggesting: Sendable {
    /// Backed by SystemLanguageModel.default.availability == .available.
    /// Checked once per import session (preview step), not per row.
    var isAvailable: Bool { get }

    /// Suggests a category for one payee from the given candidates.
    /// Returns nil if unavailable, if the model errors, or if its chosen
    /// categoryName doesn't case-insensitively match any candidate name
    /// (fails safe — no suggestion is always a valid outcome).
    func suggestCategory(payee: String, candidates: [CategoryCandidate]) async -> CategorySuggestion?
}

@Generable
struct CategorySuggestion: Sendable {
    @Guide(description: "The single best-matching category name from the list of existing category names provided in the prompt. Must be copied exactly from that list, character-for-character, or the literal string \"Uncategorized\" if none plausibly fit.")
    let categoryName: String

    @Guide(description: "Confidence that this suggestion is correct")
    let confidence: Confidence

    @Generable
    enum Confidence: String, Sendable {
        case high, medium, low
    }
}
