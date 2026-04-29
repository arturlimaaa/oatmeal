import AppKit
import SwiftUI

/// The Oatmeal leaf mark rendered as a vector shape.
///
/// Reproduces the SVG silhouette from the design handoff (64×64 viewBox):
/// a teardrop leaf body, a central rachis cutout, six pinnate vein cutouts,
/// and a small stem at the base. Uses `evenOdd` fill so the mark renders
/// crisply on any background (solid, gradient, or translucent).
public struct OatLeafShape: Shape {

    public init() {}

    public func path(in rect: CGRect) -> Path {
        // Source path is authored on a 64×64 viewBox; scale to `rect`.
        let s = min(rect.width, rect.height) / 64.0
        let ox = rect.midX - (64 * s) / 2
        let oy = rect.midY - (64 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }

        var path = Path()

        // Leaf body (teardrop)
        path.move(to: p(32, 6))
        path.addCurve(to: p(54, 34), control1: p(46, 10), control2: p(54, 22))
        path.addCurve(to: p(30, 58), control1: p(54, 46), control2: p(44, 56))
        path.addCurve(to: p(12, 40), control1: p(18, 58), control2: p(12, 50))
        path.addCurve(to: p(32, 6),  control1: p(12, 26), control2: p(20, 12))
        path.closeSubpath()

        // Central rachis cutout
        path.move(to: p(31, 10))
        path.addLine(to: p(31, 58))
        path.addLine(to: p(33, 58))
        path.addLine(to: p(33, 10))
        path.closeSubpath()

        // Pinnate vein cutouts — three pairs down the leaf
        let veins: [(CGPoint, CGPoint, CGPoint, CGPoint)] = [
            (p(31, 14), p(24, 16), p(19, 20), p(17, 26)),
            (p(33, 14), p(40, 16), p(45, 20), p(47, 26)),
            (p(31, 26), p(22, 27), p(16, 32), p(15, 38)),
            (p(33, 26), p(42, 27), p(48, 32), p(49, 38)),
            (p(31, 38), p(21, 39), p(16, 44), p(17, 50)),
            (p(33, 38), p(43, 39), p(48, 44), p(47, 50)),
        ]
        let veinEndpoints: [CGPoint] = [
            p(31, 22), p(33, 22),
            p(31, 33), p(33, 33),
            p(31, 45), p(33, 45),
        ]
        for (i, vein) in veins.enumerated() {
            path.move(to: vein.0)
            path.addCurve(to: vein.3, control1: vein.1, control2: vein.2)
            path.addLine(to: veinEndpoints[i])
            path.closeSubpath()
        }

        // Stem at base
        path.move(to: p(31, 58))
        path.addLine(to: p(29, 63))
        path.addLine(to: p(31, 63))
        path.addLine(to: p(33, 63))
        path.addLine(to: p(31, 58))
        path.closeSubpath()

        return path
    }
}

/// The Oatmeal leaf as a drop-in View with size + tint.
///
/// Use this for in-app occurrences (sidebar lockup, header, popover). The
/// menu-bar icon uses the asset-catalog template PNG directly via `MenuBarExtra`,
/// since `NSStatusItem` requires an `NSImage` template, not a SwiftUI view.
public struct OatLeafMark: View {
    public var size: CGFloat
    public var tint: Color

    public init(size: CGFloat = 20, tint: Color = Color.om.ink) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        OatLeafShape()
            .fill(tint, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview("OatLeafMark — sizes") {
    HStack(spacing: 16) {
        OatLeafMark(size: 16, tint: .om.ink)
        OatLeafMark(size: 24, tint: .om.oat2)
        OatLeafMark(size: 40, tint: .om.ring)
        OatLeafMark(size: 64, tint: .om.ink)
    }
    .padding(32)
    .background(Color.om.paper)
}
