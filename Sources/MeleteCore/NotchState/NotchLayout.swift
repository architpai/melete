import CoreGraphics
import Foundation

/// What a screen looks like at the top. Built from `NSScreen` in the app; plain values here so it can be tested.
public struct ScreenGeometry: Equatable, Sendable {
    /// Screen frame in global AppKit coordinates (origin bottom left).
    public var frame: CGRect
    public var visibleFrame: CGRect
    /// `safeAreaInsets.top`. > 0 means the screen has a notch.
    public var safeAreaTop: CGFloat
    /// `auxiliaryTopLeftArea.width` / `auxiliaryTopRightArea.width` (nil on screens without a notch).
    public var auxLeftWidth: CGFloat?
    public var auxRightWidth: CGFloat?

    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat,
                auxLeftWidth: CGFloat? = nil, auxRightWidth: CGFloat? = nil) {
        self.frame = frame; self.visibleFrame = visibleFrame; self.safeAreaTop = safeAreaTop
        self.auxLeftWidth = auxLeftWidth; self.auxRightWidth = auxRightWidth
    }

    public var hasNotch: Bool { safeAreaTop > 0 }
}

/// Sizes in points. Defaults equal `Mono` in the app target and the mocks.
public struct NotchMetrics: Equatable, Sendable {
    public var wing: CGFloat = 64
    public var collapsedExtraHeight: CGFloat = 4
    public var fallbackNotch = CGSize(width: 185, height: 32)
    public var noNotchTab = CGSize(width: 104, height: 28)
    /// Invisible hover zone on a screen without a notch (mock 6-I).
    public var hoverZone = CGSize(width: 200, height: 24)
    /// Mock sizes. Expanded heights are for a 32 pt notch; `NotchLayout` adds (top inset − 32).
    public var idleHoverSize = CGSize(width: 250, height: 62)
    public var peekSize = CGSize(width: 360, height: 128)
    public var fullSize = CGSize(width: 440, height: 392)
    public var sessionEndSize = CGSize(width: 330, height: 148)
    public var firstRunExtraHeight: CGFloat = 26
    /// Concave top corners ("ears") at each side of the shape.
    public var flare: CGFloat = 9
    public var mockNotchHeight: CGFloat = 32

    public init() {}
}

/// The shape the notch window draws (or nothing).
public enum NotchPresentation: Equatable, Sendable {
    /// Nothing drawn (idle, or hidden in fullscreen). The hardware notch shows as usual.
    case hidden
    /// Running / paused / done (B) on a notch screen, or the small tab on a screen without a notch.
    case collapsed
    case idleHover
    case peek
    case full(firstRun: Bool)
    case choices(ended: Phase)
}

/// Pure geometry: notch rect, shape size per presentation, hover zones, panel frame.
public struct NotchLayout: Equatable, Sendable {
    public var screen: ScreenGeometry
    public var metrics: NotchMetrics

    public init(screen: ScreenGeometry, metrics: NotchMetrics = NotchMetrics()) {
        self.screen = screen; self.metrics = metrics
    }

    public var hasNotch: Bool { screen.hasNotch }

    /// Hardware notch size. Screens without a notch: zero width, menu bar height.
    public var notchSize: CGSize {
        guard hasNotch else { return CGSize(width: 0, height: topInset) }
        var w = metrics.fallbackNotch.width
        if let l = screen.auxLeftWidth, let r = screen.auxRightWidth {
            let computed = screen.frame.width - l - r
            if computed > 40 { w = computed }
        }
        return CGSize(width: w, height: screen.safeAreaTop)
    }

    /// Height of the band at the top that content must stay below (notch or menu bar).
    public var topInset: CGFloat {
        if hasNotch { return screen.safeAreaTop }
        let menu = screen.frame.maxY - screen.visibleFrame.maxY
        return menu > 4 ? menu : 24
    }

    /// Center x of the notch (or of the screen) in global coordinates.
    public var centerX: CGFloat {
        if hasNotch, let l = screen.auxLeftWidth, let r = screen.auxRightWidth, screen.frame.width - l - r > 40 {
            return screen.frame.minX + l + (screen.frame.width - l - r) / 2
        }
        return screen.frame.midX
    }

    public var top: CGFloat { screen.frame.maxY }

    /// Size of the black shape (without the flares).
    public func shapeSize(_ p: NotchPresentation) -> CGSize {
        let extra = topInset - metrics.mockNotchHeight
        func grown(_ s: CGSize) -> CGSize { CGSize(width: s.width, height: s.height + extra) }
        switch p {
        case .hidden:
            return hasNotch ? notchSize : CGSize(width: metrics.noNotchTab.width, height: 0)
        case .collapsed:
            return hasNotch
                ? CGSize(width: notchSize.width + 2 * metrics.wing, height: notchSize.height + metrics.collapsedExtraHeight)
                : metrics.noNotchTab
        case .idleHover: return grown(CGSize(width: max(metrics.idleHoverSize.width, notchSize.width + 40), height: metrics.idleHoverSize.height))
        case .peek: return grown(CGSize(width: max(metrics.peekSize.width, notchSize.width + 2 * metrics.wing), height: metrics.peekSize.height))
        case let .full(firstRun):
            var s = grown(metrics.fullSize)
            if firstRun { s.height += metrics.firstRunExtraHeight }
            return s
        case .choices: return grown(metrics.sessionEndSize)
        }
    }

    /// The shape rect in global coordinates (top centered on the notch).
    public func shapeRect(_ p: NotchPresentation) -> CGRect {
        let s = shapeSize(p)
        return CGRect(x: centerX - s.width / 2, y: top - s.height, width: s.width, height: s.height)
    }

    /// Where the pointer must be to wake a hidden notch.
    /// - notch screen: the hardware notch.
    /// - no notch: the invisible zone at the top center (mock 6-I).
    /// - fullscreen: the area the collapsed shape would cover (or the notch / zone when idle).
    public func hotZone(idle: Bool) -> CGRect {
        let size: CGSize
        if !idle { size = shapeSize(.collapsed) }
        else if hasNotch { size = notchSize }
        else { size = metrics.hoverZone }
        return CGRect(x: centerX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
    }

    /// The fixed panel frame: wide and tall enough for every presentation plus the flares.
    public var panelFrame: CGRect {
        let widest = [shapeSize(.full(firstRun: true)), shapeSize(.peek), shapeSize(.collapsed), shapeSize(.idleHover)]
            .map(\.width).max() ?? 440
        let w = widest + 2 * metrics.flare + 8
        let h = shapeSize(.full(firstRun: true)).height + 8
        return CGRect(x: (centerX - w / 2).rounded(), y: top - h, width: w.rounded(.up), height: h.rounded(.up))
    }
}
