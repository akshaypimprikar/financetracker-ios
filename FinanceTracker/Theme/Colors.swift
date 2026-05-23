import SwiftUI

enum Theme {}

extension Theme {
    enum Colors {
        static let positive: Color = .green
        static let destructive: Color = .red
        static let transfer: Color = .blue
        static let netWorthCardBackground: Color = .teal.opacity(0.12)
        static let spendingCardBackground: Color = .orange.opacity(0.08)
        static let primaryInteractive: Color = .accentColor
    }
}
