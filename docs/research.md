# Research: notch Pomodoro apps (Nov 2026)

## Dedicated notch focus timers
- **Notchy** (notchy.dev, ~$24.99, closed). Countdown in notch. On session end the notch expands with: start break / +5 min / skip. Progress ring, focus sounds, streaks, 7-day chart, hotkey, music controls.
- **FocusNotch** (App Store, free). No window, no menu bar icon. Expands when the pointer is near. Website blocking via network extension. Complaints: one timer only, no chained breaks, blocking unreliable.
- **NotchFlow** (Product Hunt, subscription/lifetime). Hover = quick view, click = full view. Focus music, mindful breaks.
- **Pulse**, **NotchDock**: unverified.

## Notch suites with a timer
NotchNook Pro (Focus/Break modes, ruler to set minutes, multiple timers), Droppy (Pomodoro + iPhone Live Activity), seam, NotchNest, Atoll (GPL, boring.notch fork). boring.notch: no timer in release, only open PRs. Alcove, MediaMate, NotchDrop: no timer.

## Open source to study
- FunNotch (GPL-3.0): non-activating panel, floating pill on non-notch screens, presets, weekly chart, streak.
- dchavan2192/notch (MIT): single Swift file, NSPanel, mouse pass-through when collapsed, notch size from safeAreaInsets.
- 910studio/pomo: Tauri + React, float mode + hover pill on non-notch screens.
- NotchDrop (MIT): borderless NSWindow at `.statusBar + 8`.
- boring.notch (GPL-3.0): NSPanel at `.mainMenu + 3`.

## Common patterns
Countdown/ring beside notch when collapsed. Hover expands, click opens full view. 25/5/15 x4 cycle. Streaks + 7-day chart. Ambient sound. Pill on non-notch screens.

## Gaps / complaints
1. Fullscreen + external display bugs: notch stays visible in fullscreen, cannot hide on external displays (boring.notch #137, #426, #663, #1045, #1278, #1359).
2. Notch app covers menu bar items (#940).
3. Battery/CPU use (NotchNook reports, unverified).
4. Weak or missing blocking.
5. Bloat: users who want only a timer must buy a full notch suite.
6. Few apps link tasks/calendar to sessions. No shipped Focus/DND link found.

## Technical notes (macOS)
- Window: borderless, non-activating NSPanel, level `.mainMenu + 3` or `.statusBar + 8`. collectionBehavior `[.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]`.
- Notch detection: `safeAreaInsets.top > 0`. Width = `frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width`. ~185x32 pt (14"), ~220x38 pt (16").
- Find the built-in screen with `NSScreen.screens.first { $0.safeAreaInsets.top > 0 }`, not `NSScreen.main`.
- Pass mouse events through when collapsed; track hover with a global mouse monitor.
- Private SkyLight APIs only needed for lock screen display.

## Ideas to stand out
1. Focus timer only. Low idle CPU.
2. Per-screen display policy: notch / pill / menu bar / hidden. Reliable fullscreen hide + hotkey.
3. Progress drawn along the notch edge so the notch does not widen and hide menu bar items.
4. macOS Focus/DND via Shortcuts; App Intents for start/stop.
5. Strong blocking (later).
6. Intention + task per session; calendar gap suggestions.
7. Export (CSV), lock screen / iPhone Live Activity (later).
8. Gentle session-end expand with snooze/extend. Auto-pause on idle/lock.

## Sources
notchy.dev/mac-pomodoro-timer, apps.apple.com/gb/app/focusnotch/id6741244268, digitaltrends.com (FocusNotch review), producthunt.com/products/notchflow, lo.cafe (NotchNook), getdroppy.app, github.com/TheBoredTeam/boring.notch, github.com/Lakr233/NotchDrop, github.com/Ebullioscopic/Atoll, github.com/wiktorwiesek/FunNotch, github.com/dchavan2192/notch, github.com/910studio/pomo.
