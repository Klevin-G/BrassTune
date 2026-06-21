import SwiftUI

enum BTThemeID: String, CaseIterable, Identifiable {
    case system
    case brassNight
    case brassDay
    case liquidClear
    case liquidTinted
    case highContrast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .brassNight: return "Brass Night"
        case .brassDay: return "Brass Day"
        case .liquidClear: return "Liquid Brass - Clear"
        case .liquidTinted: return "Liquid Brass - Tinted"
        case .highContrast: return "High Contrast"
        }
    }
}

enum BTGlassStyle: String {
    case solid
    case clear
    case tinted
}

struct BTThemePalette {
    let id: BTThemeID
    let colorScheme: ColorScheme?
    let background: Color
    let surface: Color
    let surfaceAlt: Color
    let text: Color
    let mutedText: Color
    let accent: Color
    let secondaryAccent: Color
    let border: Color
    let success: Color
    let warning: Color
    let danger: Color
    let info: Color
    let glassStyle: BTGlassStyle
    let glassTint: Color
    let glassOpacity: Double
}

enum BTGeneratedThemeTokens {
    static let radiusSmall: CGFloat = 14
    static let radiusMedium: CGFloat = 18
    static let radiusLarge: CGFloat = 24
    static let radiusExtraLarge: CGFloat = 28
    static let tapTarget: CGFloat = 44

    static func palette(for theme: BTThemeID, systemScheme: ColorScheme, highContrast: Bool) -> BTThemePalette {
        let resolvedTheme: BTThemeID
        if theme == .system {
            resolvedTheme = systemScheme == .dark ? .brassNight : .brassDay
        } else {
            resolvedTheme = theme
        }

        if highContrast || resolvedTheme == .highContrast {
            return BTThemePalette(
                id: .highContrast,
                colorScheme: nil,
                background: Color(hex: "#000000"),
                surface: Color(hex: "#101010"),
                surfaceAlt: Color(hex: "#1e1e1e"),
                text: Color.white,
                mutedText: Color(hex: "#e5e5e5"),
                accent: Color(hex: "#f0c970"),
                secondaryAccent: Color(hex: "#75b7ff"),
                border: Color.white.opacity(0.64),
                success: Color(hex: "#6bd287"),
                warning: Color(hex: "#f0c970"),
                danger: Color(hex: "#ff6b6b"),
                info: Color(hex: "#75b7ff"),
                glassStyle: .solid,
                glassTint: Color(hex: "#101010"),
                glassOpacity: 1
            )
        }

        switch resolvedTheme {
        case .brassDay:
            return BTThemePalette(
                id: .brassDay,
                colorScheme: .light,
                background: Color(hex: "#f7f3e9"),
                surface: Color(hex: "#fffaf0"),
                surfaceAlt: Color(hex: "#efe6d2"),
                text: Color(hex: "#07111d"),
                mutedText: Color(hex: "#46515e"),
                accent: Color(hex: "#8d6f33"),
                secondaryAccent: Color(hex: "#111923"),
                border: Color(hex: "#d8a53f").opacity(0.34),
                success: Color(hex: "#16733e"),
                warning: Color(hex: "#8d6f33"),
                danger: Color(hex: "#b83333"),
                info: Color(hex: "#1769aa"),
                glassStyle: .solid,
                glassTint: Color(hex: "#fffaf0"),
                glassOpacity: 1
            )
        case .liquidClear:
            return BTThemePalette(
                id: .liquidClear,
                colorScheme: .dark,
                background: Color(hex: "#07111d"),
                surface: Color(hex: "#111923").opacity(0.78),
                surfaceAlt: Color(hex: "#172330").opacity(0.84),
                text: Color.white,
                mutedText: Color(hex: "#c9d4df"),
                accent: Color(hex: "#f0c970"),
                secondaryAccent: Color(hex: "#59c9b2"),
                border: Color.white.opacity(0.18),
                success: Color(hex: "#6bd287"),
                warning: Color(hex: "#e5c45c"),
                danger: Color(hex: "#e25d5d"),
                info: Color(hex: "#75b7ff"),
                glassStyle: .clear,
                glassTint: Color(hex: "#0a121c"),
                glassOpacity: 0.58
            )
        case .liquidTinted:
            return BTThemePalette(
                id: .liquidTinted,
                colorScheme: .dark,
                background: Color(hex: "#0b1118"),
                surface: Color(hex: "#221b0f").opacity(0.82),
                surfaceAlt: Color(hex: "#2b2417").opacity(0.86),
                text: Color.white,
                mutedText: Color(hex: "#eadab9"),
                accent: Color(hex: "#f0c970"),
                secondaryAccent: Color(hex: "#59c9b2"),
                border: Color(hex: "#d8a53f").opacity(0.24),
                success: Color(hex: "#6bd287"),
                warning: Color(hex: "#e5c45c"),
                danger: Color(hex: "#e25d5d"),
                info: Color(hex: "#75b7ff"),
                glassStyle: .tinted,
                glassTint: Color(hex: "#221b0f"),
                glassOpacity: 0.64
            )
        case .brassNight, .system, .highContrast:
            return BTThemePalette(
                id: .brassNight,
                colorScheme: .dark,
                background: Color(hex: "#07111d"),
                surface: Color(hex: "#111923"),
                surfaceAlt: Color(hex: "#172330"),
                text: Color.white,
                mutedText: Color(hex: "#c9d4df"),
                accent: Color(hex: "#f0c970"),
                secondaryAccent: Color(hex: "#59c9b2"),
                border: Color.white.opacity(0.12),
                success: Color(hex: "#6bd287"),
                warning: Color(hex: "#e5c45c"),
                danger: Color(hex: "#e25d5d"),
                info: Color(hex: "#75b7ff"),
                glassStyle: .solid,
                glassTint: Color(hex: "#111923"),
                glassOpacity: 1
            )
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red: UInt64
        let green: UInt64
        let blue: UInt64
        switch cleaned.count {
        case 3:
            red = (value >> 8) * 17
            green = ((value >> 4) & 0xF) * 17
            blue = (value & 0xF) * 17
        default:
            red = value >> 16
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        }
        self.init(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }
}
