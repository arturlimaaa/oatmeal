import SwiftUI

/// Spacing, radius, and hairline tokens for the Oatmeal design system.
///
/// Surfaces use these tokens instead of inline magic numbers so layout rhythm
/// stays consistent and palette/spacing tweaks remain cheap.
public enum OMSpacing {
    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 16
    public static let s5: CGFloat = 20
    public static let s6: CGFloat = 24
    public static let s7: CGFloat = 32
    public static let s8: CGFloat = 48
    public static let s9: CGFloat = 64
}

public enum OMRadius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 14
    public static let xl: CGFloat = 18
    public static let pill: CGFloat = 999
}

public enum OMHairlineWidth {
    public static let standard: CGFloat = 1
    public static let emphasized: CGFloat = 1.5
}
