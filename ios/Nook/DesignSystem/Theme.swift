import SwiftUI
import UIKit

extension UIColor {
    /// `0xRRGGBB`.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    /// `0xRRGGBB`, the same in light and dark mode.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// A color with its own value in light and dark mode.
    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

/// Design tokens from the spec (section 3.2). Dark values keep the same hues.
enum Theme {
    static var background: Color { .dynamic(light: 0xF6F8FC, dark: 0x0F141B) }
    static var surface: Color { .dynamic(light: 0xFFFFFF, dark: 0x171D26) }
    static var surfaceMuted: Color { .dynamic(light: 0xEEF3F9, dark: 0x1D2430) }
    static var primary: Color { .dynamic(light: 0x7DADE3, dark: 0x8DB8EA) }
    static var accent: Color { .dynamic(light: 0x4F86D0, dark: 0x8DB8EA) }
    static var primarySoft: Color { .dynamic(light: 0xEAF2FC, dark: 0x1E2A3A) }
    static var textPrimary: Color { .dynamic(light: 0x202938, dark: 0xE8EDF4) }
    static var textSecondary: Color { .dynamic(light: 0x7B8798, dark: 0x8E9AAB) }
    static var textTertiary: Color { .dynamic(light: 0xA7B1BF, dark: 0x5F6B7B) }
    static var border: Color { .dynamic(light: 0xE8EDF4, dark: 0x263040) }
    /// Top edge of card borders, a touch lighter than `border` for a soft bevel.
    static var cardHighlight: Color { .dynamic(light: 0xFFFFFF, dark: 0x2B3544) }
    static var shadow: Color { .dynamic(light: 0x1E3A5F, dark: 0x000000, lightAlpha: 0.07, darkAlpha: 0.40) }
    static var shadowNear: Color { .dynamic(light: 0x1E3A5F, dark: 0x000000, lightAlpha: 0.04, darkAlpha: 0.25) }
    /// Selected home tab.
    static var navy: Color { .dynamic(light: 0x1F2A44, dark: 0xDCE6F5) }
    static var onNavy: Color { .dynamic(light: 0xFFFFFF, dark: 0x0F141B) }
    /// Misty header behind the home screen.
    static var mistTop: Color { .dynamic(light: 0xD9E8FA, dark: 0x15233A) }
    static var mistWave: Color { .dynamic(light: 0xBFD6F3, dark: 0x1F3150) }
    static var mistGlow: Color { .dynamic(light: 0xFFFFFF, dark: 0x2C4470, lightAlpha: 0.95, darkAlpha: 0.45) }
}

/// Soft accent families for icon tiles, dots and charts.
struct Pastel: Sendable {
    let base: Color
    let soft: Color
    let strong: Color

    static var blue: Pastel {
        Pastel(
            base: .dynamic(light: 0x6FA3E6, dark: 0x7FB0EC),
            soft: .dynamic(light: 0xE6F0FC, dark: 0x1C2A3D),
            strong: .dynamic(light: 0x4F86D0, dark: 0x9DC2F0)
        )
    }

    static var mint: Pastel {
        Pastel(
            base: .dynamic(light: 0x5CC8A1, dark: 0x5CC8A1),
            soft: .dynamic(light: 0xE4F6EF, dark: 0x173129),
            strong: .dynamic(light: 0x2FAE7E, dark: 0x6FD6B0)
        )
    }

    static var peach: Pastel {
        Pastel(
            base: .dynamic(light: 0xF4A26B, dark: 0xF4A26B),
            soft: .dynamic(light: 0xFDEFE4, dark: 0x35261C),
            strong: .dynamic(light: 0xE08445, dark: 0xF6B486)
        )
    }

    static var rose: Pastel {
        Pastel(
            base: .dynamic(light: 0xEC7C84, dark: 0xEC7C84),
            soft: .dynamic(light: 0xFCEAEC, dark: 0x361F23),
            strong: .dynamic(light: 0xD65C66, dark: 0xF29AA1)
        )
    }

    static var violet: Pastel {
        Pastel(
            base: .dynamic(light: 0x9A8CE8, dark: 0x9A8CE8),
            soft: .dynamic(light: 0xEFECFC, dark: 0x262342),
            strong: .dynamic(light: 0x7A6AD8, dark: 0xB5AAF0)
        )
    }

    static var slate: Pastel {
        Pastel(
            base: .dynamic(light: 0x8A96A8, dark: 0x8A96A8),
            soft: .dynamic(light: 0xEEF1F5, dark: 0x222A35),
            strong: .dynamic(light: 0x5F6B7B, dark: 0xB4BFCE)
        )
    }
}

enum NookFont {
    static var screenTitle: Font { .system(.largeTitle, weight: .bold) }
    static var greeting: Font { .system(.subheadline, weight: .medium) }
    static var cardTitle: Font { .headline }
    static var rowTitle: Font { .system(.subheadline, weight: .semibold) }
    static var caption: Font { .footnote }
    static var micro: Font { .system(.caption, weight: .medium) }
    static var amount: Font { .system(.title, weight: .bold).monospacedDigit() }
}

enum Metrics {
    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14
    static let tileSize: CGFloat = 40
    static let sectionSpacing: CGFloat = 16
    /// Bottom space so the last card scrolls clear of the floating tab bar.
    static let tabBarClearance: CGFloat = 112
}
