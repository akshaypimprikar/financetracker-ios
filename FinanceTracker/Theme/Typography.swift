import SwiftUI

extension Theme {
    enum Typography {
        static let amountDisplay: Font = .system(size: 36, weight: .bold)
        static let sectionHeader: Font = .headline
        static let rowTitle:      Font = .body
        static let rowSubtitle:   Font = .caption
        static let code:          Font = .caption.monospaced()
    }
}
