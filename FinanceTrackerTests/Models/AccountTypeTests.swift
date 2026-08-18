import Testing
@testable import FinanceTracker

@Suite("AccountType")
struct AccountTypeTests {
    @Test(arguments: [
        (AccountType.checking, "Checking"),
        (AccountType.savings, "Savings"),
        (AccountType.creditCard, "Credit Card"),
        (AccountType.cash, "Cash"),
        (AccountType.investment, "Investment"),
    ])
    func displayNameMatchesExpected(type: AccountType, expected: String) {
        #expect(type.displayName == expected)
    }
}
