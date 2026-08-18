import SwiftUI

extension Theme {
    enum Glass {
        static let cardMaterial: Material = .regularMaterial

        static let netWorthTint = LinearGradient(
            colors: [Color.teal.opacity(0.28), Color.teal.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let spendingTint = LinearGradient(
            colors: [Color.orange.opacity(0.22), Color.orange.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let cardShadowColor: Color = .black.opacity(0.12)
        static let cardShadowRadius: CGFloat = 12
        static let cardShadowY: CGFloat = 4
    }
}
