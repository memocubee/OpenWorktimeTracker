import SwiftUI

// MARK: - Ethereal Chronometer Design System

enum DesignTokens {

    // MARK: - Colors (Adaptive Light/Dark)

    enum Colors {
        static let primary = Color("primary", bundle: nil)
        static let primaryContainer = Color("primaryContainer", bundle: nil)
        static let tertiary = Color("tertiary", bundle: nil)
        static let error = Color("error", bundle: nil)

        // Accents come from the palette shared with the widget
        static let accentBlue = PaletteColor.blue.color
        static let accentGreen = PaletteColor.green.color
        static let accentOrange = PaletteColor.orange.color
        static let accentRed = PaletteColor.red.color

        static let surface = Color(light: .init(hex: 0xF9F9FE), dark: .init(hex: 0x1A1C1F))
        static let surfaceContainerLow = Color(
            light: .init(hex: 0xF3F3F8), dark: .init(hex: 0x1E1E22))
        static let surfaceContainer = Color(light: .init(hex: 0xEDEDF2), dark: .init(hex: 0x25252A))
        static let surfaceContainerHigh = Color(
            light: .init(hex: 0xE8E8ED), dark: .init(hex: 0x2B2D32))
        static let surfaceContainerHighest = Color(
            light: .init(hex: 0xE2E2E7), dark: .init(hex: 0x33353A))

        static let onSurface = Color(light: .init(hex: 0x1A1C1F), dark: .init(hex: 0xE2E2E7))
        static let onAccent = Color.white
        static let onSurfaceVariant = PaletteColor.secondary.color
        static let outlineVariant = Color(light: .init(hex: 0xC1C6D7), dark: .init(hex: 0x44474E))

        // Glass effect
        static let glassBackground = Color(
            light: .white.opacity(0.7), dark: .init(hex: 0x1E1E1E).opacity(0.7))
        static let glassBorder = Color(light: .white.opacity(0.15), dark: .white.opacity(0.1))
    }

    // MARK: - Typography

    enum Typography {
        static let menuBar = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        static let displayLarge = Font.system(size: 48, weight: .light, design: .rounded)
        static let displayMedium = Font.system(size: 36, weight: .light, design: .rounded)
        static let displaySmall = Font.system(size: 28, weight: .medium, design: .rounded)
        static let displaySeconds = Font.system(size: 20, weight: .medium, design: .rounded)

        static let headlineSmall = Font.system(size: 16, weight: .semibold)
        static let titleMedium = Font.system(size: 14, weight: .semibold)
        static let bodyMedium = Font.system(size: 13, weight: .regular)
        static let bodySmall = Font.system(size: 12, weight: .regular)
        static let labelLarge = Font.system(size: 13, weight: .semibold)
        static let labelSmall = Font.system(size: 11, weight: .semibold)
        static let labelMicro = Font.system(size: 11, weight: .medium)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - Popover

    static let popoverWidth: CGFloat = 380
    static let popoverMinHeight: CGFloat = 660
    static let promptWidth: CGFloat = 380
}
