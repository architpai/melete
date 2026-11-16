import SwiftUI

/// The black island: flat top, concave "ears" at the top corners (like the hardware notch),
/// rounded bottom corners. The frame includes the ears: island width = frame width − 2 × flare.
struct NotchShape: Shape {
    var flare: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, radius) }
        set { flare = newValue.first; radius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let f = max(0, flare)
        let l = rect.minX + f, r = rect.maxX - f
        let b = rect.maxY
        let rad = max(0, min(radius, (r - l) / 2, rect.height - f))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Right ear: concave quarter circle from the top edge down to the island side.
        p.addQuadCurve(to: CGPoint(x: r, y: rect.minY + f), control: CGPoint(x: r, y: rect.minY))
        p.addLine(to: CGPoint(x: r, y: b - rad))
        p.addQuadCurve(to: CGPoint(x: r - rad, y: b), control: CGPoint(x: r, y: b))
        p.addLine(to: CGPoint(x: l + rad, y: b))
        p.addQuadCurve(to: CGPoint(x: l, y: b - rad), control: CGPoint(x: l, y: b))
        p.addLine(to: CGPoint(x: l, y: rect.minY + f))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: l, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
