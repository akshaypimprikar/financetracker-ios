import Foundation

/// Order-independent, connector-word-insensitive category name matching. Two names
/// are considered the same category if their normalized token sets are exactly equal
/// — catches word-order and connector variations ("Coffee & Dining" vs "Dining & Coffee"
/// vs "Coffee and Dining") without the false-positive risk of a broader similarity
/// threshold: "Travel" and "Travel Insurance" have different token sets, so they are
/// correctly NOT treated as duplicates despite one containing the other. Does not catch
/// typos or synonyms — token-set equality only, not fuzzy spelling correction.
///
/// Matching is scoped to `Category.type`: an Income category and an Expense category
/// sharing a name (e.g. rental income vs. a rent expense, both named "Rent") are two
/// legitimately different categories, not duplicates of each other — see issue #66.
enum CategoryNameMatching {
    private static let connectors: Set<String> = ["and", "the", "of", "for", "a", "an"]

    static func isNearDuplicate(_ lhs: String, _ lhsType: CategoryType, _ rhs: String, _ rhsType: CategoryType) -> Bool {
        guard lhsType == rhsType else { return false }
        let lhsTokens = normalizedTokens(lhs)
        // A name made entirely of connector words (e.g. "The", "For") normalizes to an
        // empty set — without this guard, any two such names would compare equal to
        // each other via Set equality, treating unrelated names as duplicates.
        guard !lhsTokens.isEmpty else { return false }
        return lhsTokens == normalizedTokens(rhs)
    }

    private static func normalizedTokens(_ name: String) -> Set<String> {
        Set(
            name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && !connectors.contains($0) }
        )
    }
}
