import AppKit
import MeleteCore

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var notchGeometry: ScreenGeometry {
        ScreenGeometry(frame: frame, visibleFrame: visibleFrame, safeAreaTop: safeAreaInsets.top,
                       auxLeftWidth: auxiliaryTopLeftArea?.width, auxRightWidth: auxiliaryTopRightArea?.width)
    }

    static func containing(_ p: NSPoint) -> NSScreen? {
        // Include the top edge (NSRect.contains excludes maxY).
        screens.first { NSPointInRect(p, $0.frame) || ($0.frame.minX...$0.frame.maxX ~= p.x && p.y == $0.frame.maxY) }
    }
}

/// Fullscreen detection. There is no public API.
/// 1. Main: the private SkyLight call `CGSCopyManagedDisplaySpaces` (loaded with dlsym, so a missing symbol
///    only disables it). The current space of a display has `type == 4` when it is a fullscreen space.
/// 2. Fallback: a normal-level window of another app covers the whole screen and the screen has no
///    menu bar window. Weak on notch screens (a fullscreen window there has the same bounds as a zoomed one).
/// Call only on space / screen / app changes, never on mouse moves.
@MainActor
enum FullscreenDetector {
    private typealias ConnFn = @convention(c) () -> Int32
    private typealias SpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let cgs: (ConnFn, SpacesFn)? = {
        guard let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let c = dlsym(h, "CGSMainConnectionID"), let s = dlsym(h, "CGSCopyManagedDisplaySpaces")
        else { return nil }
        return (unsafeBitCast(c, to: ConnFn.self), unsafeBitCast(s, to: SpacesFn.self))
    }()

    /// Display UUID → is the current space fullscreen. Nil when the private call is not available.
    static func fullscreenByDisplayUUID() -> [String: Bool]? {
        guard let (conn, spaces) = cgs, let arr = spaces(conn())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        var out: [String: Bool] = [:]
        for d in arr {
            guard let id = d["Display Identifier"] as? String else { continue }
            let type = (d["Current Space"] as? [String: Any])?["type"] as? Int ?? 0
            out[id.uppercased()] = (type == 4)
            // "Main" is used when displays share one space ("Displays have separate Spaces" off).
        }
        return out
    }

    static func uuid(of screen: NSScreen) -> String? {
        guard let u = CGDisplayCreateUUIDFromDisplayID(screen.displayID)?.takeRetainedValue() else { return nil }
        return (CFUUIDCreateString(nil, u) as String?)?.uppercased()
    }

    static func isFullscreen(_ screen: NSScreen) -> Bool {
        if let map = fullscreenByDisplayUUID() {
            if let id = uuid(of: screen), let v = map[id] { return v }
            if map.count == 1, let v = map.values.first { return v } // shared space ("Main")
        }
        return windowListFallback(screen)
    }

    private static func windowListFallback(_ screen: NSScreen) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let f = screen.frame
        // Screen rect in CG coordinates (origin top left of the primary screen).
        let cg = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        let me = ProcessInfo.processInfo.processIdentifier
        var covered = false, menuBar = false
        for w in list {
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            guard let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: bd) else { continue }
            let pid = w[kCGWindowOwnerPID as String] as? Int32 ?? 0
            if layer == 0, pid != me, b.insetBy(dx: -1, dy: -1).contains(cg.insetBy(dx: 0, dy: screen.safeAreaInsets.top / 2)) {
                covered = true
            }
            if layer == Int(CGWindowLevelForKey(.mainMenuWindow)), b.intersects(cg), abs(b.minY - cg.minY) < 2 {
                menuBar = true
            }
        }
        return covered && !menuBar
    }
}
