import Testing
import SwiftUI
@testable import FinanceTracker

@Suite("Theme Tokens")
struct ThemeTokenTests {

    // MARK: Colors

    @Test func colorsPositive()                  { #expect(Theme.Colors.positive == .green) }
    @Test func colorsDestructive()               { #expect(Theme.Colors.destructive == .red) }
    @Test func colorsTransfer()                  { #expect(Theme.Colors.transfer == .blue) }
    @Test func colorsNetWorthCardBackground()    { #expect(Theme.Colors.netWorthCardBackground == Color.teal.opacity(0.12)) }
    @Test func colorsSpendingCardBackground()    { #expect(Theme.Colors.spendingCardBackground == Color.orange.opacity(0.08)) }
    @Test func colorsPrimaryInteractive()        { #expect(Theme.Colors.primaryInteractive == Color.accentColor) }

    // MARK: Spacing

    @Test func spacingTight()                    { #expect(Theme.Spacing.tight == 2) }
    @Test func spacingCompact()                  { #expect(Theme.Spacing.compact == 4) }
    @Test func spacingRowSpacing()               { #expect(Theme.Spacing.rowSpacing == 6) }
    @Test func spacingContentSpacing()           { #expect(Theme.Spacing.contentSpacing == 8) }
    @Test func spacingElementSpacing()           { #expect(Theme.Spacing.elementSpacing == 12) }
    @Test func spacingCardPadding()              { #expect(Theme.Spacing.cardPadding == 16) }
    @Test func spacingSheetSpacing()             { #expect(Theme.Spacing.sheetSpacing == 24) }
    @Test func spacingCornerRadiusCard()         { #expect(Theme.Spacing.cornerRadiusCard == 12) }
    @Test func spacingCornerRadiusCardLarge()    { #expect(Theme.Spacing.cornerRadiusCardLarge == 16) }

    // MARK: Typography

    @Test func typographyAmountDisplay() {
        #expect(Theme.Typography.amountDisplay == Font.system(size: 36, weight: .bold, design: .rounded))
    }

    // MARK: Glass

    // Theme.Glass.cardMaterial (SwiftUI.Material) and .netWorthTint/.spendingTint
    // (LinearGradient) are not Equatable, so their declared type is verified by
    // this file compiling at all rather than a runtime equality check.
    @Test func glassCardShadowColor()             { #expect(Theme.Glass.cardShadowColor == Color.black.opacity(0.12)) }
    @Test func glassCardShadowRadius()            { #expect(Theme.Glass.cardShadowRadius == 12) }
    @Test func glassCardShadowY()                 { #expect(Theme.Glass.cardShadowY == 4) }
}
