import Testing
@testable import FinanceTracker

@Suite("CategoryNameMatching")
struct CategoryNameMatchingTests {

    @Test func exactMatch() {
        #expect(CategoryNameMatching.isNearDuplicate("Groceries", .expense, "Groceries", .expense))
    }

    @Test func caseInsensitiveMatch() {
        #expect(CategoryNameMatching.isNearDuplicate("groceries", .expense, "GROCERIES", .expense))
    }

    @Test func wordOrderSwapMatches() {
        #expect(CategoryNameMatching.isNearDuplicate("Coffee & Dining", .expense, "Dining & Coffee", .expense))
    }

    @Test func connectorVariationMatches() {
        #expect(CategoryNameMatching.isNearDuplicate("Coffee & Dining", .expense, "Coffee and Dining", .expense))
    }

    @Test func punctuationAndWhitespaceNoiseMatches() {
        #expect(CategoryNameMatching.isNearDuplicate("Coffee  &  Dining", .expense, "Coffee&Dining", .expense))
    }

    @Test func substringIsNotATrueDuplicate() {
        #expect(!CategoryNameMatching.isNearDuplicate("Travel", .expense, "Travel Insurance", .expense))
    }

    @Test func extraWordIsNotATrueDuplicate() {
        #expect(!CategoryNameMatching.isNearDuplicate("Shopping", .expense, "Online Shopping", .expense))
    }

    @Test func unrelatedNamesDoNotMatch() {
        #expect(!CategoryNameMatching.isNearDuplicate("Groceries", .expense, "Transport", .expense))
    }

    @Test func connectorOnlyNamesDoNotMatchEachOther() {
        // Regression guard: "The" and "For" both normalize to an empty token set
        // (every token is a connector word) — without an explicit empty-set guard,
        // Set equality would treat any two such names as duplicates of each other.
        #expect(!CategoryNameMatching.isNearDuplicate("The", .expense, "For", .expense))
        #expect(!CategoryNameMatching.isNearDuplicate("And", .expense, "A", .expense))
    }

    @Test func sameNameDifferentTypeIsNotADuplicate() {
        // Regression guard for issue #66: an Income category and an Expense category
        // sharing a name (e.g. rental income vs. a rent expense, both "Rent") are two
        // legitimately different categories, not duplicates of each other.
        #expect(!CategoryNameMatching.isNearDuplicate("Rent", .income, "Rent", .expense))
    }

    @Test func sameNameSameTypeStillMatches() {
        #expect(CategoryNameMatching.isNearDuplicate("Rent", .expense, "Rent", .expense))
        #expect(CategoryNameMatching.isNearDuplicate("Rent", .income, "Rent", .income))
    }
}
