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

    /// Suggests a category for one payee from the given candidates. Returns nil if
    /// unavailable, if the model errors, or if its raw suggestion is the literal
    /// "Uncategorized" fallback (no plausible match, not even a proposal). Otherwise
    /// always returns a result — matchedCategoryID is nil when the suggested name
    /// doesn't near-duplicate-match any candidate, meaning "propose creating this,"
    /// not "no suggestion."
    func suggestCategory(payee: String, candidates: [CategoryCandidate]) async -> CategorySuggestionResult?
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

/// Domain-level wrapper pairing the model's raw @Generable output with the post-hoc
/// near-duplicate match determination against the caller's actual candidates. Kept
/// separate from CategorySuggestion (rather than adding matchedCategoryID directly to
/// that struct) since CategorySuggestion's schema is macro-synthesized from @Guide
/// properties — mixing in a plain post-hoc field there is unverified against how that
/// synthesis actually works.
struct CategorySuggestionResult: Sendable {
    let suggestion: CategorySuggestion
    let matchedCategoryID: UUID?
}
