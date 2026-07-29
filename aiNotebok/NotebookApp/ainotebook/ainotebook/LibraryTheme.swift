import SwiftUI

// MARK: - Theme Definition

enum LibraryThemeID: String, CaseIterable, Identifiable, Codable {
    case classic
    case retroDark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .retroDark: return "Retro Dark"
        }
    }

    var theme: LibraryTheme {
        switch self {
        case .classic: return .classic
        case .retroDark: return .retroDark
        }
    }
}

struct LibraryTheme {
    // Background
    let backgroundColor: Color

    // Cards
    let cardBackground: Color
    let cardCornerRadius: CGFloat
    let cardShadowColor: Color
    let cardShadowRadius: CGFloat
    let cardUsesGradientCover: Bool

    // Typography
    let titleFont: Font
    let cardTitleFont: Font
    let cardMetaFont: Font
    let buttonFont: Font

    // Header buttons
    let headerButtonStyle: HeaderButtonStyle
    let headerTitleFont: Font

    // New notebook card
    let newCardBorderColor: Color
    let newCardTextColor: Color
    let newCardIconColor: Color

    // Favorites
    let favoriteIcon: String
    let favoriteColor: Color

    // Card title/meta colors (retro uses colored titles per notebook)
    let cardTitleColor: Color?  // nil = use notebook.coverColor
    let cardMetaColor: Color

    enum HeaderButtonStyle {
        case circleIcon      // Classic: circle outline + icon
        case pillLabel       // Retro: dark pill with icon + text
    }
}

// MARK: - Classic Theme

extension LibraryTheme {
    static let classic = LibraryTheme(
        backgroundColor: Color(.systemBackground),
        cardBackground: .clear,
        cardCornerRadius: 24,
        cardShadowColor: Color.black.opacity(0.08),
        cardShadowRadius: 12,
        cardUsesGradientCover: true,
        titleFont: .system(size: 34, weight: .bold),
        cardTitleFont: .system(size: 26, weight: .bold, design: .rounded),
        cardMetaFont: .caption.bold(),
        buttonFont: .system(size: 17, weight: .semibold),
        headerButtonStyle: .circleIcon,
        headerTitleFont: .system(size: 34, weight: .bold),
        newCardBorderColor: Color.secondary.opacity(0.4),
        newCardTextColor: .primary,
        newCardIconColor: .primary,
        favoriteIcon: "star.fill",
        favoriteColor: .white.opacity(0.9),
        cardTitleColor: .white,
        cardMetaColor: .white.opacity(0.92)
    )
}

// MARK: - Retro Dark Theme

extension LibraryTheme {
    static let retroDark = LibraryTheme(
        backgroundColor: Color(red: 0.08, green: 0.08, blue: 0.08),
        cardBackground: Color(red: 0.95, green: 0.94, blue: 0.92),
        cardCornerRadius: 16,
        cardShadowColor: Color.black.opacity(0.3),
        cardShadowRadius: 8,
        cardUsesGradientCover: false,
        titleFont: .system(size: 34, weight: .bold, design: .monospaced),
        cardTitleFont: .system(size: 16, weight: .bold, design: .monospaced),
        cardMetaFont: .system(size: 11, weight: .regular, design: .monospaced),
        buttonFont: .system(size: 13, weight: .medium, design: .monospaced),
        headerButtonStyle: .pillLabel,
        headerTitleFont: .system(size: 34, weight: .bold, design: .monospaced),
        newCardBorderColor: Color.white.opacity(0.4),
        newCardTextColor: .white,
        newCardIconColor: .white,
        favoriteIcon: "star.fill",
        favoriteColor: Color(red: 0.2, green: 0.2, blue: 0.2),
        cardTitleColor: nil,  // uses notebook.coverColor
        cardMetaColor: Color(red: 0.35, green: 0.35, blue: 0.35)
    )
}

// MARK: - Persistence

enum LibraryThemePreference {
    private static let key = "LibraryThemeID"

    static func load() -> LibraryThemeID {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let themeID = LibraryThemeID(rawValue: raw) else {
            return .retroDark
        }
        return themeID
    }

    static func save(_ themeID: LibraryThemeID) {
        UserDefaults.standard.set(themeID.rawValue, forKey: key)
    }
}
