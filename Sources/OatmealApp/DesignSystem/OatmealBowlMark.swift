import SwiftUI

/// The Oatmeal bowl brand mark. Raster, rendered from the asset catalog.
///
/// Used for hero moments (onboarding welcome, brand surfaces). For functional
/// UI chrome, use `OatLeafMark` instead — it tints cleanly with the design
/// system palette.
public struct OatmealBowlMark: View {
    public var size: CGFloat

    public init(size: CGFloat = 200) {
        self.size = size
    }

    public var body: some View {
        Image("OatmealBowl", bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Oatmeal bowl")
    }
}

#Preview("OatmealBowlMark") {
    VStack {
        OatmealBowlMark(size: 200)
        OatmealBowlMark(size: 96)
    }
    .padding(32)
    .background(Color.om.paper)
}
