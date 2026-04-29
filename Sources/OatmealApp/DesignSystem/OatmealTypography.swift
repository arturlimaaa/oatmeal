import SwiftUI

/// Semantic type tokens for the Oatmeal design system.
///
/// Three families:
/// - **serif** (Instrument Serif) — titles, display, hero quotes
/// - **sans** (Inter Tight) — UI, body, buttons
/// - **mono** (JetBrains Mono) — timestamps, metadata, kbd pills
///
/// `Font.custom` falls back silently to the system font when the requested
/// family is not installed, so the design system remains usable on machines
/// that do not have the brand fonts.
public enum OatmealTypography {

    // MARK: Raw families (with graceful fallback)

    public static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        let name = italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular"
        return .custom(name, size: size, relativeTo: .largeTitle)
    }

    public static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("InterTight-Regular", size: size, relativeTo: .body)
            .weight(weight)
    }

    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrainsMono-Regular", size: size, relativeTo: .caption)
            .weight(weight)
    }

    // MARK: Role-based styles

    /// Hero display — used for the biggest editorial moments (brand, onboarding).
    public static let display = serif(56)

    /// Page title — used on top of library, workspace, summary.
    public static let title = serif(42)

    /// Section title — used for H2 inside notes.
    public static let sectionTitle = serif(22)

    /// Row title — used on meeting rows, action rows.
    public static let rowTitle = serif(20)

    /// Pull-quote / TLDR — italic serif on summary.
    public static let pullQuote = serif(22, italic: true)

    /// Body UI text.
    public static let body = sans(13)

    /// Body paragraph text (slightly larger, reading-grade).
    public static let bodyParagraph = sans(15)

    /// Button and inline control text.
    public static let button = sans(12, weight: .medium)

    /// Small metadata (descriptions, helper copy).
    public static let caption = sans(12)

    /// Eyebrow labels — small mono, uppercase, wide tracking.
    public static let eyebrow = mono(10)

    /// Metadata, timestamps, durations.
    public static let meta = mono(11)

    /// Keystroke pills.
    public static let kbd = mono(10)
}

public extension Font {
    /// Short-hand namespace: `Font.om.title`, `Font.om.body`, etc.
    static let om = OatmealFontTokens()
}

public struct OatmealFontTokens: Sendable {
    public let display      = OatmealTypography.display
    public let title        = OatmealTypography.title
    public let sectionTitle = OatmealTypography.sectionTitle
    public let rowTitle     = OatmealTypography.rowTitle
    public let pullQuote    = OatmealTypography.pullQuote
    public let body         = OatmealTypography.body
    public let bodyParagraph = OatmealTypography.bodyParagraph
    public let button       = OatmealTypography.button
    public let caption      = OatmealTypography.caption
    public let eyebrow      = OatmealTypography.eyebrow
    public let meta         = OatmealTypography.meta
    public let kbd          = OatmealTypography.kbd
}
