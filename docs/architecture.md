# Melete — architecture and build plan

Read `spec.md` first. The spec wins if this file disagrees with it. The coordinator ("coord") has the last word.

## Toolchain

- Swift Package Manager (no `.xcodeproj` in git). Swift tools 6.0, language mode 5, macOS 14 target.
- **Full Xcode is required** (SwiftData macros are not in Command Line Tools). `make check` stops with a message if `xcode-select -p` is not Xcode.
- `make build` / `make test` (Swift Testing) / `make app` (release `build/Melete.app`) / `make run` / `make debug-app` / `make debug-run STATE=<name>`.
- `scripts/bundle.sh` writes `Info.plist` (`LSUIElement`, bundle id `dev.melete.Melete`) and ad-hoc signs. No bundled resources in v1 (chimes are system sounds via `NSSound`).
- SwiftData store: `~/Library/Application Support/Melete/Melete.store` (explicit URL). Verified working in the bundled app and in `swift test`.

## Package layout and owners

```
Package.swift                                  coord
Makefile, scripts/                             coord
Sources/MeleteCore/
  Timer/  Phase.swift, TimeSource.swift        coord (contract)
          TimerEngine.swift                    coord wrote it; sol owns tests + bug fixes (no public signature change without coord)
  Model/  TaskItem.swift, SessionRecord.swift  coord (contract)
  Store/  MeleteStore.swift                    coord wrote it; sol may extend (add methods, fix bugs)
  Settings/MeleteSettings.swift                coord wrote it; sol may extend
  Stats/  StatsCalculator.swift                sol implements (stub bodies now)
  NotchState/**                                opus (pure state logic for the notch, testable)
Sources/Melete/
  App/    main.swift, AppDelegate.swift, AppModel.swift   coord
  Shared/ MonoStyle.swift                      coord (style + timing constants; ask to change)
  Notch/**                                     opus
  Windows/**                                   sol
  Services/** (ChimePlayer, LoginItem)         sol
Tests/MeleteCoreTests/
  NotchState*Tests.swift                       opus
  everything else                              sol
```

Rules:
- Edit only your paths. Need a change elsewhere? Post on the board. Small, obvious fixes to coord files (a compile error you caused) are OK if you post a note.
- Keep `swift build` and `swift test` green on your branch at every commit.
- Do not push. Commit to your branch only. Coord merges and pushes.

## Contract summary (see the source for full docs)

- `TimerEngine` (`@MainActor @Observable`): `phase`, `state: TimerState`, `cyclePosition`, `durations`, `currentTaskID`, `intention`, `nextBreak`.
  Actions: `startFocus()`, `start(_:)`, `select(_:)`, `pause()`, `resume()`, `togglePause()`, `skip()`, `reset()`, `extendFiveMinutes()`, `startBreak()`, `skipBreak()`, `stop()`, `reconcile()`.
  Reads: `remaining(at:)`, `progress(at:)`. Events: `onPhaseEnded(Phase)` (reached 0:00), `onSessionEnded(SessionSummary)` (any end).
  DEBUG only: `debugForce(phase:state:cyclePosition:)`.
- `TimerState`: `.idle`, `.running(endsAt:total:)`, `.paused(remaining:total:)`, `.awaitingChoice(ended:)`.
- `SessionSummary` → `MeleteStore.record(_:)` inserts or updates by id and increments the task's count once.
- `MeleteStore`: tasks CRUD + `move`, `record`, `sessions(from:to:)`, `container` (use `.modelContainer(model.store.container)` + `@Query` in SwiftUI if you like).
- `MeleteSettings`: minutes, `cycleLength` (2…6), `chimeName` (`MeleteSettings.chimeChoices`), `chimeVolume`, `hasCompletedFirstRun`, `durations`. Launch at login = `LoginItem` (reads `SMAppService`, not stored).
- `AppModel` (app target): `settings`, `store`, `engine`, `chime`, `openStats()`, `openSettings()`, `onSessionReachedZero` (notch sets it), `currentTaskTitle`, `quit()`. It already wires: summary → store, 0:00 → chime + `onSessionReachedZero`, settings → engine durations, wake → `engine.reconcile()`.
- `NotchController` (opus): `init(model:)`, `start()`, `showFullPanel(firstRun:)`.
- `StatsWindowController` / `SettingsWindowController` (sol): `init(model:)`, `show()`.

## State machine decisions (coord, 16 Nov)

These fill the gaps the review found. They are in `TimerEngine` and in `spec.md`.

| Event | Result |
|---|---|
| Skip during focus | Not counted. Idle, focus next. Cycle unchanged |
| Skip during a break | Next focus starts at once. Skipping a long break resets the cycle |
| Reset | Session ends uncounted. Idle, same phase next |
| Manual Focus/Short/Long (idle only) | Sets the next phase. Does not change the cycle |
| Long break ends or is skipped | Cycle (dots) back to 0 |
| Durations change mid-session | Applies to the next session. Smaller `cycleLength` clamps the dots now |
| New day | First start on a new day resets the cycle. No midnight timer |
| Quit / relaunch | `cyclePosition` is kept (UserDefaults). A running session is lost and not logged |
| Number of dots | = `cycleLength` (2…6) |
| Full panel (8) while running | Shows mode (read-only), time with pause/skip/reset, intention, tasks (selecting a task changes the task credited at 0:00). Closes on click outside or Esc, not on hover exit |
| 4b hover / click | Opens the session-end choices (9 or 10) again |
| Tasks UI | Click circle = done/undone. Double-click title = rename. Hover row → planned-count stepper (−/+) and delete (×). Drag to reorder. Done tasks stay, struck through |
| Session end at 0:00 (phase 4) | Choices 9/10 open from any expansion (none, peek, full) with a 30 s auto-close. From full: commit text, drop key focus. Pointer enter/exit does not cancel the deadline; pointer inside at the deadline → close on pointer exit. Reopened 4b choices = normal hover panel |
| Fullscreen (phase 4) | Entering fullscreen collapses a full panel carried over from the desktop. 1 s dwell on 4b opens the choices (no key focus) |
| Esc (phase 4) | One Esc commits the text edit and closes the full panel |
| Action at the deadline (phase 4) | Every action first completes a session that is past 0:00. Pause, reset and skip then do nothing more; the choices show |
| Task credit (phase 4) | Any focus session (counted or not) is credited to the task / intention selected when it ends. "+5" keeps the 0:00 credit |
| Home screen (phase 5) | Follow the pointer only to non-fullscreen screens. Pointer on a fullscreen screen → stay on the home screen (last normal screen, else built-in, else first normal). Its top-center hot zone still reveals the notch there after 1 s; after the exit delay it returns home. All screens fullscreen → old behavior. Pure logic: `NotchScreenPicker` |
| Session end in fullscreen (phase 5) | Choices open on the pointer's screen. In fullscreen: no 30 s deadline; becoming fullscreen cancels it; leaving fullscreen does not restart it. A full panel open at 0:00 shows the choices where it is |

## Notch shell technical notes (from the review)

- `NSPanel` subclass, `.borderless + .nonactivatingPanel`, override `canBecomeKey` → `true` only while the full panel shows (the intention / task fields need typing). Session-end and peek must not take key focus.
- Collapsed: `ignoresMouseEvents = true` (tracking areas stop working). Detect hover with `NSEvent.addGlobalMonitorForEvents(.mouseMoved)` + a local monitor; no Accessibility permission needed. Hover exit delay `Mono.hoverExitDelay`.
- Fullscreen: no public API. **Decision (coord, 16 Nov, after the spike):** the main check is the private SkyLight call `CGSCopyManagedDisplaySpaces`, loaded with `dlsym` (current space type 4 = fullscreen, per display UUID). It runs on space change, screen change and app activation only. Reason: the public `CGWindowListCopyWindowInfo` check fails on the notch screen (a fullscreen window has the same bounds as a zoomed one). If the symbol is missing, the code falls back to the `CGWindowList` check. Acceptable because Melete is built from source, not sold in the App Store. Not yet tested: Safari video, Keynote, "Displays have separate Spaces" off, auto-hidden menu bar.
- Idle + hover shape is 72 pt tall (mock: 62 pt) so the Start button is not under the camera housing (coord approved).
- Notch geometry: `safeAreaInsets.top > 0` → notch; width = `frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width`. Else no-notch tab.
- Level: start with `.mainMenu + 3` (boring.notch). Test with many status items: wings must not hide clicks on status items outside the wing area.
- Low idle CPU: no timers when idle + collapsed. Redraw the countdown once per second only while it is visible (`TimelineView(.periodic)` or one `Timer`).
- DEBUG: `MELETE_DEBUG_STATE` env var forces a notch state at launch (names: `idle, idleHover, running, break, paused, done, peek, full, focusEnd, breakEnd, noNotch, firstRun`). Also `MELETE_DEBUG_SCREEN`, `MELETE_DEBUG_FULLSCREEN=builtin|external`, `MELETE_DEBUG_NO_FULLSCREEN`, `MELETE_DEBUG_SEED`, `MELETE_DEBUG_SECONDS` (writes real settings) using `engine.debugForce` + view-state overrides.

## Message board (delegates ↔ coordinator)

Location: **`/Users/paiarchit/random-musing/melete/.board/`** — absolute path, outside the worktrees, gitignored. All agents use this path.

```
.board/
  README.md            # these rules
  msgs/                # one file per message, never edited after writing
    <epoch>-<from>-<type>.md      e.g. 1794800000-opus-question.md
  status/opus.md       # your current status (overwrite)
  status/sol.md
  reviews/<reviewer>-on-<owner>-<n>.md
```

Message file content: first line `to: <opus|sol|coord|all>`, then the text. Use `date +%s` for the epoch. Reference files as `path:line` and commits by short SHA.

Types: `status`, `question`, `answer`, `contract-change`, `review-request`, `review`, `blocker`, `decision` (coord only).

Rules:
- Check `msgs/` (`ls -1 .board/msgs | tail`) when you start, before every commit, and before you finish.
- **Never wait for an answer.** Every question must state the default you will use. Use that default, write it in your status, and continue. The other agent or coord can correct it later.
- A `decision` from coord overrides everything.
- The contract is frozen. Use `contract-change` only when you are blocked; meanwhile work around it in your own paths.

## Phases

1. **Scaffold** (coord) — done: package, contract, working engine + store + settings, app wiring, stubs, bundle script, tests green.
2. **Build** (parallel, separate worktrees from `main`):
   - opus, first milestone = **spike**: panel above the menu bar, mouse pass-through + hover, notch geometry, follow pointer screen, fullscreen detection. Post a `status` with results (what works, what does not) before building the views.
   - sol, first milestone = engine tests for every rule in the table above + StatsCalculator with tests. Then windows and services.
3. **Merge** (coord): merge both into `main`, fix integration, `make test`, `make app`.
4. **Cross-review** on the merged app: opus reviews sol's paths, sol reviews opus's paths. Reviews in `.board/reviews/`. Owners fix on top of `main`; coord merges.
5. **User test**: the user runs `make run` with the checklist below.

## Manual test checklist (phase 5)

- First launch: full panel opens with "Melete lives here". Open the app again from Finder → full panel.
- Idle notch looks normal. Hover → Start. Click → full panel.
- Start focus → collapsed B: dots (= cycle length), time, bar. Pause → pause icon, blink. Break → cup, dashed bar.
- Session end: panel opens, chime, choices; no answer → closes after 30 s → "Done" blinks; hover reopens choices.
- External monitor: tab follows pointer screen; idle = nothing, hover zone (0.4 s) opens it.
- Fullscreen video: hidden; shows at session end and stays until a choice; 1 s hover at top center shows it.
- Mixed screens (one fullscreen, one normal): the notch stays on the normal screen when the pointer goes to the fullscreen screen. 1 s hover at the fullscreen screen's top center shows it there; it returns home when the pointer leaves, and after a choice.
- A screen goes fullscreen while the choices show → they stay. The fullscreen app exits → the notch follows the pointer again. Unplug / plug in the external screen.
- Tasks: add, select, rename, planned count, reorder, delete, count goes up at 0:00, mark done, count past plan.
- Stats window and Settings window open from the panel icons. Settings changes apply to the next session. Quit from Settings.
- Sleep the Mac mid-session → time is correct after wake.
- Activity Monitor: idle CPU ≈ 0 %.
