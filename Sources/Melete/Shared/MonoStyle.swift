import SwiftUI

/// Shared monochrome style + timing constants. OWNER: coord (ask on the board to change).
enum Mono {
    // Colors (pure monochrome)
    static let ink = Color(white: 0.96)
    static let ink2 = Color(white: 0.96).opacity(0.6)
    static let ink3 = Color(white: 0.96).opacity(0.35)
    static let fill = Color.white.opacity(0.12)
    static let track = Color.white.opacity(0.18)
    static let notchBlack = Color.black

    // Notch geometry (points)
    static let wing: CGFloat = 64
    static let barHeight: CGFloat = 2
    static let collapsedExtraHeight: CGFloat = 4   // bar sits under the notch
    static let fallbackNotch = CGSize(width: 185, height: 32)
    static let noNotchTab = CGSize(width: 104, height: 28)
    static let peekSize = CGSize(width: 360, height: 128)
    static let fullSize = CGSize(width: 440, height: 392)
    static let sessionEndSize = CGSize(width: 330, height: 148)

    // Timing (seconds)
    static let hoverZoneDwell: TimeInterval = 0.4     // no-notch hover zone
    static let fullscreenHoverDwell: TimeInterval = 1.0
    static let hoverExitDelay: TimeInterval = 0.3
    static let sessionEndAutoClose: TimeInterval = 30

    /// "18:42", "1:05:00"
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
