import AppKit
import SwiftUI

/// Semantic color tokens for the Oatmeal design system.
///
/// Every color is defined once with a light + dark variant. Call sites
/// reference tokens by semantic role (`paper`, `ink`, `oat`) rather than hex
/// values so future palette tweaks never require rewriting UI code.
///
/// Usage:
///     .background(Color.om.paper)
///     .foregroundStyle(Color.om.ink2)
public struct OatmealPalette: Sendable {
    // MARK: Paper (surfaces)
    public let paper: Color
    public let paper2: Color
    public let paper3: Color
    public let card: Color

    // MARK: Ink (text + icons)
    public let ink: Color
    public let ink2: Color
    public let ink3: Color
    public let ink4: Color

    // MARK: Hairlines
    public let line: Color
    public let line2: Color

    // MARK: Brand accents
    public let oat: Color
    public let oat2: Color
    public let ring: Color
    public let honey: Color
    public let sage: Color
    public let sage2: Color
    public let ember: Color

    // MARK: Feedback
    public let recDot: Color

    public init(
        paper: Color, paper2: Color, paper3: Color, card: Color,
        ink: Color, ink2: Color, ink3: Color, ink4: Color,
        line: Color, line2: Color,
        oat: Color, oat2: Color, ring: Color, honey: Color,
        sage: Color, sage2: Color, ember: Color,
        recDot: Color
    ) {
        self.paper = paper; self.paper2 = paper2; self.paper3 = paper3; self.card = card
        self.ink = ink; self.ink2 = ink2; self.ink3 = ink3; self.ink4 = ink4
        self.line = line; self.line2 = line2
        self.oat = oat; self.oat2 = oat2; self.ring = ring; self.honey = honey
        self.sage = sage; self.sage2 = sage2; self.ember = ember
        self.recDot = recDot
    }
}

public extension Color {
    /// Entry point for every semantic color token. See `OatmealPalette`.
    static let om = OatmealColors.shared
}

public enum OatmealColors {
    public static let shared = OatmealPalette(
        paper:  dynamic(light: 0xF5EFE4, dark: 0x1C1712),
        paper2: dynamic(light: 0xEFE7D6, dark: 0x231C15),
        paper3: dynamic(light: 0xE8DFC9, dark: 0x2A2218),
        card:   dynamic(light: 0xFBF7EE, dark: 0x241D15),

        ink:  dynamic(light: 0x2A1F14, dark: 0xF2E8D3),
        ink2: dynamic(light: 0x4A3B2A, dark: 0xD7C9AB),
        ink3: dynamic(light: 0x7A6A55, dark: 0x9C8E74),
        ink4: dynamic(light: 0x9B8B72, dark: 0x6E634F),

        line:  dynamicAlpha(light: (0x483620, 0.12), dark: (0xF0DCB4, 0.10)),
        line2: dynamicAlpha(light: (0x483620, 0.22), dark: (0xF0DCB4, 0.18)),

        oat:   dynamic(light: 0xC89A5C, dark: 0xD4A764),
        oat2:  dynamic(light: 0xB07F3E, dark: 0xE8C898),
        ring:  dynamic(light: 0x8B5E2F, dark: 0xD4A764),
        honey: dynamic(light: 0xE0A845, dark: 0xE8B75A),
        sage:  dynamic(light: 0x7A8C5C, dark: 0xA8B07A),
        sage2: dynamic(light: 0x5F7045, dark: 0x7A8C5C),
        ember: dynamic(light: 0xC2410C, dark: 0xE08555),

        recDot: Color(red: 217/255, green: 74/255, blue: 56/255)
    )

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDarkMode ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }

    private static func dynamicAlpha(light: (UInt32, CGFloat), dark: (UInt32, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDarkMode
                ? NSColor(hex: dark.0, alpha: dark.1)
                : NSColor(hex: light.0, alpha: light.1)
        })
    }
}

private extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .vibrantDark, .aqua]) == .darkAqua
            || bestMatch(from: [.darkAqua, .vibrantDark, .aqua]) == .vibrantDark
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8)  & 0xFF) / 255.0
        let b = CGFloat( hex        & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}
