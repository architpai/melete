# Melete — architecture and build plan

Read `spec.md` first. The spec wins if this file disagrees with it.

## Toolchain

- Swift Package Manager (no `.xcodeproj` in git). Swift tools 6.0, language mode 5, macOS 14 deployment target.
- Build on Xcode 26 toolchain (`swift build`). SwiftData `@Model` macros come from the SDK.
- `scripts/bundle.sh` makes `build/Melete.app`: release build, `Info.plist` (`LSUIElement = YES`, bundle id `dev.melete.Melete`), resources, ad-hoc `codesign -s -`.
- `Makefile`: `make build`, `make test`, `make app`, `make run` (bundles and opens the app).
- Users "build from source": `git clone … && make run`. Only Xcode / Command Line Tools needed.

## Package layout

```
Package.swift
Sources/
  MeleteCore/                 # pure logic. Foundation + SwiftData + Observation. NO AppKit/SwiftUI.
    Timer/    Phase.swift, TimerState.swift, TimerEngine.swift, Clock.swift
    Model/    TaskItem.swift, SessionRecord.swift          (SwiftData @Model)
    Store/    MeleteStore.swift                            (task CRUD, session log, queries)
    Settings/ MeleteSettings.swift                         (UserDefaults, @Observable)
    Stats/    StatsCalculator.swift                        (today, streak, per day, per task)
  Melete/                     # the app (executable target). AppKit + SwiftUI.
    App/      main.swift, AppDelegate.swift, AppModel.swift (wires engine + store + settings)
    Notch/    NotchPanel.swift, NotchWindowController.swift, ScreenTracker.swift,
              NotchGeometry.swift, HoverController.swift, FullscreenDetector.swift,
              NotchViewModel.swift (state machine for 1/2/B/3/4/4b/7/8/9/10)
    Notch/Views/ CollapsedView, IdleHoverView, PeekView, FullPanelView, SessionEndView,
              NoNotchTabView, FirstRunHint, MonoStyle.swift
    Windows/  StatsWindow.swift + views, SettingsWindow.swift + views
    Services/ ChimePlayer.swift, LoginItem.swift (SMAppService.mainApp)
    Resources/ Sounds/*.caf (free-license or generated)
Tests/
  MeleteCoreTests/            # engine, counting rules, stats, store (in-memory container)
scripts/bundle.sh
Makefile
```

## Shared contract (written by the coordinator in the scaffold)

The scaffold commit defines these public types in `MeleteCore`. Bodies may be stubs. **Changes to public signatures need coordinator approval on the board.**

- `enum Phase { focus, shortBreak, longBreak }`
- `enum TimerState { idle, running(endsAt: Date, total: TimeInterval), paused(remaining: TimeInterval, total: TimeInterval), awaitingChoice(ended: Phase) }`
- `protocol Clock { var now: Date { get } }` + `SystemClock`. Tests use a manual clock.
- `@MainActor @Observable final class TimerEngine`
  - state: `phase`, `state`, `cyclePosition` (0…cycleLength), `cycleLength`, `currentTaskID: UUID?`, `intention: String?`
  - actions: `startFocus()`, `start(_ phase:)`, `pause()`, `resume()`, `skip()`, `reset()`, `extendFiveMinutes()`, `startBreak()`, `skipBreak()`, `stop()`
  - reads: `remaining(at:)`, `progress(at:)` (0…1)
  - events: `var onPhaseEnded: ((Phase) -> Void)?`, `var onPomodoroCompleted: ((CompletedPomodoro) -> Void)?`
  - time is wall-clock (`endsAt`), one scheduled wake-up at `endsAt`, not a 1 s tick. Sleep/wake safe.
- `@Model TaskItem { id, title, plannedPomodoros, completedPomodoros, isDone, doneAt, createdAt, sortIndex }`
- `@Model SessionRecord { id, phase, startedAt, endedAt, plannedDuration, actualDuration, counted, taskID, taskTitle, intention }`
- `@MainActor final class MeleteStore` (wraps `ModelContext`): tasks CRUD + reorder + mark done, `log(_:)`, `sessions(in:)`. `init(inMemory:)` for tests.
- `@MainActor @Observable final class MeleteSettings`: durations, cycleLength (2…6), chimeName, chimeVolume, launchAtLogin, hasCompletedFirstRun.
- `struct StatsCalculator`: `today`, `focusTimeToday`, `streak`, `perDay(range:)`, `perTask(range:)`.

Counting rules: see `spec.md` → "Counting rules (accepted)". These live only in `TimerEngine` and have unit tests.

## Work split

| Area | Owner | Branch | Owns these paths |
|---|---|---|---|
| Notch shell | **Opus 5.5** ("opus") | `feat/notch-shell` | `Sources/Melete/App/**`, `Sources/Melete/Notch/**` |
| Core + windows | **GPT 6.1 Sol** ("sol") | `feat/core-windows` | `Sources/MeleteCore/**`, `Tests/**`, `Sources/Melete/Windows/**`, `Sources/Melete/Services/**`, `Sources/Melete/Resources/**`, `scripts/**`, `Makefile` |
| Contract, `Package.swift`, docs, merge | **Coordinator** ("coord") | `main` | `Package.swift`, `docs/**`, public signatures in `MeleteCore` |

Rules:
- Do not edit files outside your paths. If you need a change there, ask on the board.
- Until the other side lands, code against the contract. Use the stubs.
- Each delegate keeps `swift build` green on its branch, and `make test` green for sol.

### Opus 5.5 — notch shell acceptance
- Non-activating `NSPanel`, borderless, above the menu bar, all Spaces, fullscreen auxiliary. Mouse pass-through when collapsed.
- Notch geometry from `safeAreaInsets` / `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Fallback tab on no-notch screens.
- Follows the screen with the pointer. Fullscreen: hidden, shows at session end and after 1 s hover at top center.
- Every state in `spec.md` → "Notch states", matching the mocks (64 pt wings, dots, bar, cup, pause, blink, Done).
- Hover = peek, click = full panel. Panel at session end closes after 30 s → 4b. Invisible hover zone with ~0.4 s dwell on no-notch screens.
- First-run panel with "Melete lives here". `applicationShouldHandleReopen` opens the full panel. Gear opens Settings, chart icon opens Stats (call the window API sol provides; use a stub until then).
- Low idle CPU: no per-frame work when collapsed and idle. Redraw the countdown once per second only while visible.

### GPT 6.1 Sol — core + windows acceptance
- `TimerEngine` with all actions and counting rules. Unit tests for every rule, pause/resume, extend, skip, stop, cycle wrap, day change.
- SwiftData models + `MeleteStore` (local only). Tests with an in-memory container.
- `MeleteSettings` (UserDefaults). `StatsCalculator` with tests (streak, ranges).
- Stats window (mock 3/3): tiles, Week/Month/Year chart (Swift Charts), by task, today list. Monochrome.
- Settings window: durations, cycle length 2–6, chime picker + volume (preview plays), launch at login, Quit.
- `ChimePlayer`, `LoginItem`, `scripts/bundle.sh`, `Makefile`.
- Expose `StatsWindowController.show()` and `SettingsWindowController.show()` for the notch shell.

## Message board (delegates ↔ coordinator)

Location: **`/Users/paiarchit/random-musing/melete/.board/`** (absolute path, outside the worktrees, gitignored). Every agent uses this same path.

```
.board/
  BOARD.md          # append-only log. Never edit or delete old entries.
  status/opus.md    # your current status. Overwrite freely.
  status/sol.md
  reviews/          # review files: <reviewer>-on-<branch>-<n>.md
```

Entry format in `BOARD.md`:

```
## 2026-11-16 14:05 · opus → sol · question
Text. Reference files as path:line and commits by short SHA.
```

Types: `status`, `question`, `answer`, `contract-change` (to coord), `review-request`, `review`, `blocker`, `decision` (coord only).

Rules:
- Read the board when you start, before each commit, and before you finish.
- Append with `cat >> … <<'EOF'` so you do not overwrite other entries.
- The coordinator has the last word. A `decision` entry from coord overrides other entries.
- If you are blocked, write a `blocker` entry and continue with the next task you can do.

## Phases

1. **Scaffold** (coord): package, contract stubs, `swift build` green, board created. Commit to `main`, push.
2. **Build** (parallel): opus and sol in separate worktrees from `main`.
3. **Cross-review**: opus reviews `feat/core-windows`, sol reviews `feat/notch-shell`. Reviews go to `.board/reviews/`. Each owner fixes or answers every finding.
4. **Merge** (coord): merge both into `main`, fix integration, `make test`, `make app`.
5. **User test**: the user runs `make run` with the manual checklist below.

## Manual test checklist (phase 5)

- Idle notch looks normal. Hover → Start. Click → full panel.
- Start focus → collapsed B: dots, time, bar. Pause → pause icon, blink. Break → cup, dashed bar.
- Session end: panel opens, chime, choices; no answer → closes after 30 s → "Done" blinks.
- External monitor: tab follows pointer screen; idle = nothing, hover zone opens it.
- Fullscreen video: hidden; shows at session end; 1 s hover shows it.
- Tasks: add, select, count goes up, mark done, count past plan.
- Stats window and Settings window open from the panel icons. Quit from Settings.
- Sleep the Mac mid-session → time is correct after wake.
- Activity Monitor: idle CPU ≈ 0 %.
