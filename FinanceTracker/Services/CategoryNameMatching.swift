import Foundation

/// Order-independent, connector-word-insensitive category name matching. Two names
/// are considered the same category if their normalized token sets are exactly equal
/// — catches word-order and connector variations ("Coffee & Dining" vs "Dining & Coffee"
/// vs "Coffee and Dining") without the false-positive risk of a broader similarity
/// threshold: "Travel" and "Travel Insurance" have different token sets, so they are
/// correctly NOT treated as duplicates despite one containing the other. Does not catch
/// typos or synonyms — token-set equality only, not fuzzy spelling correction.
enum CategoryNameMatching {
    private static let connectors: Set<String> = ["and", "the", "of", "for", "a", "an"]

    static func isNearDuplicate(_ lhs: String, _ rhs: String) -> Bool {
        normalizedTokens(lhs) == normalizedTokens(rhs)
    }

    private static func normalizedTokens(_ name: String) -> Set<String> {
        Set(
            name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && !connectors.contains($0) }
        )
    }
}
