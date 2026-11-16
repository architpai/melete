# Melete — product spec

Melete (Greek: study, reflection, practice) is a minimal Pomodoro timer that lives in the macOS notch.

Status: design final (16 Nov 2026). Mocks in `docs/mocks/` agree with this spec. Build plan: `docs/architecture.md`.

## Decisions

| Area | Decision |
|---|---|
| Audience | Open source, for others |
| Stack | Native Swift + SwiftUI, AppKit for the notch window. macOS only |
| Minimum OS | macOS 14 Sonoma (SwiftData, @Observable, Swift Charts) |
| Distribution | Build from source only (v1). Releases later |
| License | GPL-3.0 |
| Visual style | Pure monochrome (black, white, grays). No accent color |

## V1 features

1. **Core timer**: focus, short break, long break, cycles. Start, pause, skip, reset. Defaults 25 / 5 / 15, long break after 4 focus sessions. Durations and cycle length are editable in Settings. Cycle length ("long break after") is 2–6, so the dots fit in the wing.
2. **Tasks**: a task list. Each task has planned pomodoros and counts the done ones (e.g. 2 / 4). The count can go past the plan (5 / 4). The user marks a task done by hand. A quick one-off intention can be typed for a session instead of a task.
3. **Stats**: a separate Mac window. Tiles (today, focus time today, streak, this week = rolling 7 days), pomodoros chart (Week = 7 days, Month = 30 days, both per day; Year = 12 months, per month). Streak = days in a row with ≥1 pomodoro, ending today (or yesterday if today has none yet). Plus stats by task (including an "Intentions only" group), today's history list.
4. **Sound**: a short chime at session end. Chime picker (a few sounds) and volume slider in Settings.
5. **Launch at login**.
6. **First launch**: no Dock icon (agent app). On first launch the full panel opens once with the hint "Melete lives here". Opening the app again from Finder / Spotlight opens the full panel.

Not in v1: menu bar icon, global hotkey, right-click menu, CSV export, auto-pause on lock/idle, blocking, Focus/DND link, ambient sounds, Reminders sync, auto-start of sessions.

## Notch states

| # | State | Behavior |
|---|---|---|
| 1 | Idle | Normal notch. Nothing extra |
| 2 | Idle + hover | Notch grows down a little: Start focus button + duration |
| B | Running, collapsed | Left wing: one dot per focus session in the cycle (dots = cycle length, 2–6; default 4); filled = done. Right wing: remaining time. Thin progress bar under the notch. 64 pt wing at each side, the same width in every running state |
| 3 | Break | Cup icon beside the time, dim time, dashed progress bar |
| 4 | Paused | Pause icon beside the time, time blinks slowly, dim bar |
| 4b | Done, no answer | Panel closed after 30 s. Right wing shows "Done", blinking, until the user chooses |
| 7 | Hover peek | Current task or intention, large time, pause / skip / reset, bar, dots |
| 8 | Click: full panel | Mode (Focus / Short / Long), time, Start, reset, intention field, task list, Stats icon, Settings (gear) icon |
| 9 | Focus end | Panel expands by itself, chime plays. Choices: Start break / +5 min / Skip. Closes after 30 s → state 4b |
| 10 | Break end | Panel expands, chime plays. Choices: Start focus / Stop. Closes after 30 s → state 4b |

## Displays

- Follow the active screen (the screen with the pointer).
- Screen with notch: grow out of the notch.
- Screen without notch: running = small black tab at top center (mock 5). The tab is a short form: time + bar only, no dots. Break / pause / done use the same icon and blink rules as the right wing. Idle = nothing shows; an invisible hover zone at top center opens it (mock 6-I).
- Fullscreen app: hidden. At session end it shows the choices, then hides again. Hover the top center for 1 s to show it; it hides when the pointer leaves (mock 4c).

## Settings and quit

- Gear icon in the full notch panel opens the Settings window.
- Settings: timer durations, cycle length (2–6), chime picker + volume, launch at login, Quit.
- Display behavior is fixed, not a setting: follow the pointer screen, hide in fullscreen (show at session end and on 1 s hover), invisible hover zone on no-notch screens.
- Quit Melete is in the Settings window (only place).

## Technical decisions

- Storage: SwiftData, local only. No sync (confirmed).
- Window: borderless, non-activating `NSPanel`, level above the menu bar, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.
- Mouse events pass through when collapsed; a global mouse monitor detects hover.
- Notch size from `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Screen with notch: `safeAreaInsets.top > 0`.
- Timer uses wall-clock end dates (not tick counting), so sleep/wake keeps correct time.
- Launch at login via `SMAppService.mainApp`.
- Chime: a bundled sound with a GPL-compatible license, or a system sound.

## Counting rules (accepted)

Full state machine (skip, reset, stop, day change, relaunch, panel behavior, task controls): `architecture.md` → "State machine decisions".

- A pomodoro counts when a focus session reaches 0:00. "+5 min" adds to the same pomodoro.
- Skip during focus: the session does not count and the cycle does not advance.
- Skip at focus end (skip the break): the pomodoro counts; the next focus starts.
- Reset: the current session restarts; nothing counts.
- Stop at break end: the cycle position is kept until the end of the day.

## Risks to test in a prototype

- Fullscreen hover: the pointer at the top edge also shows the system menu bar. boring.notch has bugs here. Test first.
- Invisible hover zone on no-notch screens sits in the menu bar center. Needs a dwell delay (approx. 0.4 s) to stop accidental opens.

See `research.md` for sources.
