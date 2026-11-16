import Foundation

/// One screen as the picker sees it. `id` is the `CGDirectDisplayID` in the app.
public struct NotchScreenInfo: Equatable, Sendable {
    public var id: UInt32
    /// The screen shows a fullscreen space now (cached; refreshed on space / screen / app changes only).
    public var fullscreen: Bool
    /// The built-in (notched) screen.
    public var builtIn: Bool

    public init(id: UInt32, fullscreen: Bool, builtIn: Bool) {
        self.id = id; self.fullscreen = fullscreen; self.builtIn = builtIn
    }
}

/// Pure screen choice for the one notch panel (user test F1, coord decision 1794809444).
///
/// - Rule A (home screen): the notch follows the pointer only to screens that are not fullscreen.
///   When the pointer is on a fullscreen screen, the notch stays on its home screen: the last
///   non-fullscreen screen it was on, else the built-in screen if it is not fullscreen, else the first
///   non-fullscreen screen. When every screen is fullscreen there is no home: the notch follows the
///   pointer and the machine hides it there (old behavior).
/// - Rule B (reveal): the pointer in the hot zone of a fullscreen screen moves the panel there, hidden,
///   so the machine can run its 1 s dwell. When the reveal ends, the panel goes home again.
/// - While the machine pins the panel (an expansion is open, or a fullscreen reveal), it stays,
///   unless its screen is gone.
///
/// Called on every pointer move: O(number of screens), no allocations.
public struct NotchScreenPicker: Equatable, Sendable {
    /// The last non-fullscreen screen the panel was on.
    public private(set) var home: UInt32?

    public init(home: UInt32? = nil) { self.home = home }

    /// The screen the panel should be on.
    /// - Parameters:
    ///   - screens: all screens with their cached fullscreen flags.
    ///   - pointer: the screen with the pointer (nil if the pointer is on no screen).
    ///   - pointerInHotZone: the pointer is in the hot zone of the `pointer` screen.
    ///   - current: the screen the panel is on now (nil at start or after a screen change).
    ///   - pinned: the machine does not follow the pointer now (`!NotchMachine.followsPointerScreen`).
    public mutating func target(screens: [NotchScreenInfo], pointer: UInt32?, pointerInHotZone: Bool,
                                current: UInt32?, pinned: Bool) -> UInt32? {
        let cur = current.flatMap { id in screens.first { $0.id == id } }
        if let cur, !cur.fullscreen { home = cur.id }
        if pinned, let cur { return cur.id }

        let ptr = pointer.flatMap { id in screens.first { $0.id == id } }
        if let ptr, !ptr.fullscreen { return ptr.id }

        let homeScreen = validHome(screens)
        home = homeScreen
        if let ptr {
            // Fullscreen pointer screen: only the hot zone (Rule B) or "all fullscreen" brings the panel there.
            if pointerInHotZone || homeScreen == nil { return ptr.id }
            return homeScreen
        }
        // The pointer is on no screen (rare): stay, else go home, else any screen.
        return cur?.id ?? homeScreen ?? screens.first?.id
    }

    /// The stored home if it still exists and is not fullscreen; else the built-in screen if it is not
    /// fullscreen; else the first non-fullscreen screen; else nil (all screens fullscreen).
    public func validHome(_ screens: [NotchScreenInfo]) -> UInt32? {
        if let home, screens.contains(where: { $0.id == home && !$0.fullscreen }) { return home }
        if let b = screens.first(where: { $0.builtIn && !$0.fullscreen }) { return b.id }
        return screens.first { !$0.fullscreen }?.id
    }
}
