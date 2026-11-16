import Testing
@testable import MeleteCore

/// Rules A/B (user test F1): which screen the one notch panel is on.
struct NotchStateScreenPickerTests {
    // The user's setup: built-in notched screen 1 + external screen 2 above it.
    static let builtIn: UInt32 = 1, external: UInt32 = 2, third: UInt32 = 3

    static func screens(builtInFS: Bool = false, externalFS: Bool = false) -> [NotchScreenInfo] {
        [NotchScreenInfo(id: builtIn, fullscreen: builtInFS, builtIn: true),
         NotchScreenInfo(id: external, fullscreen: externalFS, builtIn: false)]
    }

    @Test func followsPointerBetweenNormalScreens() {
        var p = NotchScreenPicker()
        let s = Self.screens()
        #expect(p.target(screens: s, pointer: Self.builtIn, pointerInHotZone: false, current: nil, pinned: false) == Self.builtIn)
        #expect(p.target(screens: s, pointer: Self.external, pointerInHotZone: false, current: Self.builtIn, pinned: false) == Self.external)
        #expect(p.target(screens: s, pointer: Self.builtIn, pointerInHotZone: false, current: Self.external, pinned: false) == Self.builtIn)
    }

    // F1: the pointer moves up to the fullscreen external screen; the notch stays on the built-in screen.
    @Test func staysOnHomeWhenPointerGoesToFullscreenScreen() {
        var p = NotchScreenPicker()
        let s = Self.screens(externalFS: true)
        #expect(p.target(screens: s, pointer: Self.builtIn, pointerInHotZone: false, current: Self.builtIn, pinned: false) == Self.builtIn)
        #expect(p.home == Self.builtIn)
        #expect(p.target(screens: s, pointer: Self.external, pointerInHotZone: false, current: Self.builtIn, pinned: false) == Self.builtIn)
    }

    @Test func homeIsTheLastNormalScreenNotAlwaysTheBuiltIn() {
        // Three screens: the panel was last on the normal external screen 2; screen 3 is fullscreen.
        var p = NotchScreenPicker()
        let s = Self.screens() + [NotchScreenInfo(id: Self.third, fullscreen: true, builtIn: false)]
        _ = p.target(screens: s, pointer: Self.external, pointerInHotZone: false, current: Self.external, pinned: false)
        #expect(p.target(screens: s, pointer: Self.third, pointerInHotZone: false, current: Self.external, pinned: false) == Self.external)
    }

    @Test func noHomeKnownPrefersBuiltInScreen() {
        // At launch the pointer is on the fullscreen external screen.
        var p = NotchScreenPicker()
        #expect(p.target(screens: Self.screens(externalFS: true), pointer: Self.external, pointerInHotZone: false,
                         current: nil, pinned: false) == Self.builtIn)
        #expect(p.home == Self.builtIn)
    }

    @Test func noHomeKnownAndBuiltInFullscreenPicksAnotherNormalScreen() {
        var p = NotchScreenPicker()
        let s = Self.screens(builtInFS: true) + [NotchScreenInfo(id: Self.third, fullscreen: true, builtIn: false)]
        #expect(p.target(screens: s, pointer: Self.builtIn, pointerInHotZone: false, current: nil, pinned: false) == Self.external)
    }

    // Rule B: the hot zone of a fullscreen screen brings the panel there (hidden) for the 1 s dwell.
    @Test func hotZoneOnFullscreenScreenMovesThereAndBackHome() {
        var p = NotchScreenPicker()
        let s = Self.screens(externalFS: true)
        _ = p.target(screens: s, pointer: Self.builtIn, pointerInHotZone: false, current: Self.builtIn, pinned: false)
        #expect(p.target(screens: s, pointer: Self.external, pointerInHotZone: true, current: Self.builtIn, pinned: false) == Self.external)
        #expect(p.home == Self.builtIn) // a fullscreen screen never becomes home
        // Pointer leaves the hot zone before the dwell (not pinned): home at once.
        #expect(p.target(screens: s, pointer: Self.external, pointerInHotZone: false, current: Self.external, pinned: false) == Self.builtIn)
    }

    @Test func revealStaysWhilePinnedThenGoesHome() {
        var p = NotchScreenPicker(home: Self.builtIn)
        let s = Self.screens(externalFS: true)
        // Revealed (machine pins): the pointer left the hot zone, exit delay running.
        #expect(p.target(screens: s, pointer: Self.external, pointerInHotZone: false, current: Self.external, pinned: true) == Self.external)
        #expect(p.target(screens: s, pointer: Self.builtIn, pointerInHotZone: false, current: Self.external, pinned: true) == Self.external)
        // Exit delay over: not pinned.
        #expect(p.target(screens: s, pointer: Self.external, pointerInHotZone: false, current: Self.external, pinned: false) == Self.builtIn)
    }

    // Rule C: the controller moves the panel to the fullscreen pointer screen for the choices (pinned).
    // After the choice the picker sends it home.
    @Test func afterChoicesOnFullscreenScreenGoesHome() {
        var p = NotchScreenPicker(home: Self.builtIn)
        let s = Self.screens(externalFS: true)
        #expect(p.target(screens: s, pointer: Self.builtIn, pointerInHotZone: false, current: Self.external, pinned: true) == Self.external)
        #expect(p.target(screens: s, pointer: Self.external, pointerInHotZone: false, current: Self.external, pinned: false) == Self.builtIn)
    }

    @Test func pinnedOnNormalScreenStays() {
        var p = NotchScreenPicker()
        let s = Self.screens()
        #expect(p.target(screens: s, pointer: Self.external, pointerInHotZone: false, current: Self.builtIn, pinned: true) == Self.builtIn)
    }

    @Test func pinnedScreenRemovedRePicks() {
        var p = NotchScreenPicker(home: Self.external)
        let onlyBuiltIn = [NotchScreenInfo(id: Self.builtIn, fullscreen: false, builtIn: true)]
        #expect(p.target(screens: onlyBuiltIn, pointer: Self.builtIn, pointerInHotZone: false, current: Self.external, pinned: true) == Self.builtIn)
    }

    @Test func homeScreenRemovedRePicks() {
        // Home was a normal external screen 3, now unplugged; the pointer is on the fullscreen screen 2.
        var p = NotchScreenPicker(home: Self.third)
        let s = Self.screens(externalFS: true)
        #expect(p.target(screens: s, pointer: Self.external, pointerInHotZone: false, current: nil, pinned: false) == Self.builtIn)
        #expect(p.home == Self.builtIn)
    }

    @Test func homeScreenBecomesFullscreenRePicks() {
        var p = NotchScreenPicker(home: Self.builtIn)
        // Now the built-in screen is fullscreen and the external one is normal; the pointer is on the built-in.
        let s = Self.screens(builtInFS: true)
        #expect(p.target(screens: s, pointer: Self.builtIn, pointerInHotZone: false, current: Self.builtIn, pinned: false) == Self.external)
        #expect(p.home == Self.external)
    }

    @Test func fullscreenAppExitsThenFollowsNormally() {
        var p = NotchScreenPicker(home: Self.builtIn)
        #expect(p.target(screens: Self.screens(externalFS: true), pointer: Self.external, pointerInHotZone: false,
                         current: Self.builtIn, pinned: false) == Self.builtIn)
        #expect(p.target(screens: Self.screens(), pointer: Self.external, pointerInHotZone: false,
                         current: Self.builtIn, pinned: false) == Self.external)
    }

    // All screens fullscreen: old behavior (follow the pointer; the machine hides it there).
    @Test func allFullscreenFollowsPointer() {
        var p = NotchScreenPicker(home: Self.builtIn)
        let s = Self.screens(builtInFS: true, externalFS: true)
        #expect(p.target(screens: s, pointer: Self.external, pointerInHotZone: false, current: Self.builtIn, pinned: false) == Self.external)
        #expect(p.home == nil)
        #expect(p.target(screens: s, pointer: Self.builtIn, pointerInHotZone: false, current: Self.external, pinned: false) == Self.builtIn)
    }

    @Test func pointerOnNoScreenStays() {
        var p = NotchScreenPicker()
        #expect(p.target(screens: Self.screens(), pointer: nil, pointerInHotZone: false, current: Self.external, pinned: false) == Self.external)
        var q = NotchScreenPicker() // nothing known: home = the built-in screen
        #expect(q.target(screens: Self.screens(), pointer: nil, pointerInHotZone: false, current: nil, pinned: false) == Self.builtIn)
    }
}
