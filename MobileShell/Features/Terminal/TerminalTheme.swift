import SwiftUI

enum TerminalTheme: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case obsidianNeon
    case solarizedDark
    case everforestDark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .obsidianNeon:
            "Obsidian Neon"
        case .solarizedDark:
            "Solarized Dark"
        case .everforestDark:
            "Everforest Dark"
        }
    }

    var terminalBackground: Color {
        switch self {
        case .obsidianNeon:
            Color(red: 0.02, green: 0.03, blue: 0.07)
        case .solarizedDark:
            Color(red: 0.00, green: 0.17, blue: 0.21)
        case .everforestDark:
            Color(red: 0.12, green: 0.15, blue: 0.13)
        }
    }

    var terminalForeground: Color {
        switch self {
        case .obsidianNeon:
            Color(red: 0.93, green: 0.95, blue: 0.98)
        case .solarizedDark:
            Color(red: 0.58, green: 0.63, blue: 0.63)
        case .everforestDark:
            Color(red: 0.86, green: 0.82, blue: 0.68)
        }
    }

    var promptForeground: Color {
        switch self {
        case .obsidianNeon:
            Color(red: 0.24, green: 0.93, blue: 0.64)
        case .solarizedDark:
            Color(red: 0.52, green: 0.60, blue: 0.00)
        case .everforestDark:
            Color(red: 0.65, green: 0.74, blue: 0.53)
        }
    }

    var mutedForeground: Color {
        switch self {
        case .obsidianNeon:
            Color(red: 0.56, green: 0.59, blue: 0.70)
        case .solarizedDark:
            Color(red: 0.40, green: 0.48, blue: 0.51)
        case .everforestDark:
            Color(red: 0.50, green: 0.56, blue: 0.49)
        }
    }
}

enum TerminalFontSize: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case small
    case standard
    case large
    case extraLarge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small:
            "Small"
        case .standard:
            "Standard"
        case .large:
            "Large"
        case .extraLarge:
            "Extra Large"
        }
    }

    var pointSize: Double {
        switch self {
        case .small:
            12
        case .standard:
            13
        case .large:
            15
        case .extraLarge:
            17
        }
    }
}
