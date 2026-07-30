import Testing
@testable import FinanceTracker

@Suite("CategoryNameMatching")
struct CategoryNameMatchingTests {

    @Test func exactMatch() {
        #expect(CategoryNameMatching.isNearDuplicate("Groceries", "Groceries"))
    }

    @Test func caseInsensitiveMatch() {
        #expect(CategoryNameMatching.isNearDuplicate("groceries", "GROCERIES"))
    }

    @Test func wordOrderSwapMatches() {
        #expect(CategoryNameMatching.isNearDuplicate("Coffee & Dining", "Dining & Coffee"))
    }

    @Test func connectorVariationMatches() {
        #expect(CategoryNameMatching.isNearDuplicate("Coffee & Dining", "Coffee and Dining"))
    }

    @Test func punctuationAndWhitespaceNoiseMatches() {
        #expect(CategoryNameMatching.isNearDuplicate("Coffee  &  Dining", "Coffee&Dining"))
    }

    @Test func substringIsNotATrueDuplicate() {
        #expect(!CategoryNameMatching.isNearDuplicate("Travel", "Travel Insurance"))
    }

    @Test func extraWordIsNotATrueDuplicate() {
        #expect(!CategoryNameMatching.isNearDuplicate("Shopping", "Online Shopping"))
    }

    @Test func unrelatedNamesDoNotMatch() {
        #expect(!CategoryNameMatching.isNearDuplicate("Groceries", "Transport"))
    }

    @Test func connectorOnlyNamesDoNotMatchEachOther() {
        // Regression guard: "The" and "For" both normalize to an empty token set
        // (every token is a connector word) — without an explicit empty-set guard,
        // Set equality would treat any two such names as duplicates of each other.
        #expect(!CategoryNameMatching.isNearDuplicate("The", "For"))
        #expect(!CategoryNameMatching.isNearDuplicate("And", "A"))
    }
}
