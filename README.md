# Melete

A minimal Pomodoro timer that lives in the macOS notch.

*Melete* is Greek for study, reflection and practice.

Pure monochrome. No Dock icon, no menu bar icon: the timer grows out of the notch.

## Features

- **Timer in the notch.** Focus, short break and long break. Defaults: 25 / 5 / 15 min, long break after 4 focus sessions (2–6).
  - Running: dots for the cycle at the left, the time at the right, a thin progress bar under the notch.
  - Hover: a peek with the task, a large time and pause / skip / reset.
  - Click: the full panel with mode, time, an intention field and the task list.
- **Session end.** A chime plays and the panel opens with the choices (Break / +5 min / Skip, or Focus / Stop). It closes after 30 s and a blinking "Done" stays until you choose.
- **Tasks.** Planned and done pomodoros per task (for example 2 / 4). Rename, reorder, mark done. Or type a one-off intention.
- **Stats window.** Today, focus time today, streak and this week; a Week / Month / Year chart; time by task; today's history.
- **Settings window.** Durations, cycle length, chime and volume, launch at login, Quit.
- **Screens.** It follows the screen with the pointer. On a screen without a notch it shows a small black tab while a session runs. A fullscreen app hides it on screens without a notch; hover the top center for 1 s to show it. On the notched screen it stays visible in fullscreen.
- **Local only.** Data is stored with SwiftData in `~/Library/Application Support/Melete/`. No network, no account, no telemetry.

## Requirements

- macOS 14 Sonoma or later. Made for MacBooks with a notch; other screens work too.
- **Full Xcode** (not only the Command Line Tools), because SwiftData macros need it:
  `sudo xcode-select -s /Applications/Xcode.app`

## Build and run

There are no releases yet. Build from source:

```sh
git clone https://github.com/architpai/melete.git
cd melete
make run        # release build to build/Melete.app, then open it
```

Other targets:

| Command | What it does |
|---|---|
| `make build` | `swift build` |
| `make test` | Run the tests (Swift Testing) |
| `make app` | Release app bundle in `build/Melete.app` |
| `make debug-app` | Debug app bundle |
| `make debug-run STATE=paused` | Debug app with a forced notch state (see `docs/architecture.md`) |
| `make clean` | Delete build output |

To keep it, copy `build/Melete.app` to `/Applications`. To quit, open Settings (gear icon in the full panel) → **Quit Melete**.

## Known limits

- The app is ad-hoc signed. "Launch at login" can need approval in System Settings → General → Login Items, and it can fail for an unsigned build.
- macOS has no public API to detect a fullscreen space. Melete uses a private SkyLight call (`CGSCopyManagedDisplaySpaces`, loaded at run time) with a public fallback. A future macOS update can break it.
- When the menu bar is full, the timer wings can cover the status item next to the notch.
- In fullscreen, the system menu bar also slides down when the pointer is at the top of the screen.

## Docs

- [docs/spec.md](docs/spec.md): product spec
- [docs/architecture.md](docs/architecture.md): code layout, state machine decisions, manual test checklist
- [docs/research.md](docs/research.md): research on other notch apps
- [docs/mocks](docs/mocks): design mocks

## License

GPL-3.0. See [LICENSE](LICENSE).
