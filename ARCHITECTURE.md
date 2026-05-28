# Architecture

**Status:** Current
**Updated:** 2026-05-28

## Overview

MyTime is a single-process, menu-bar-only macOS app (SwiftUI + AppKit) that tracks one timer at a time and persists to plain files under `~/.config/mytime/`. There is no server, no database, no network. See [PRODUCT.md](PRODUCT.md) for the why.

## Components

| Component | Location | Responsibility | Tech Stack | Entry point |
|---|---|---|---|---|
| App bootstrap | `Sources/MyTime/main.swift` | Create `NSApplication` as `.accessory` (no dock icon), install `AppDelegate` | AppKit | `app.run()` |
| App coordinator | `AppDelegate.swift` | Wire all components, own coarse timers (reminder, heartbeat), route menu/notification/idle/sleep events; run pomodoro check from the status item's tick | AppKit | `applicationDidFinishLaunching` |
| Timer engine | `TimerController.swift` | The state machine (inactive/active/paused), boot recovery, day-boundary close, derived elapsed, recent combos | Foundation, Combine (`ObservableObject`) | `start/pause/resume/stop/heartbeat` |
| Domain models | `Models.swift` | `TimerState`, `TimerEntry`, `CurrentEntry`, `AppConfig`, `PauseReason` | Foundation, Codable | — |
| Persistence | `Storage.swift` | File paths, local-ISO date formatting, RFC-4180 CSV escape/parse, `Journal` / `CurrentStore` / `ConfigStore` I/O + legacy migration | Foundation | — |
| Menu bar UI | `StatusItemController.swift` | `NSStatusItem` title (live elapsed), build/rebuild menu, 5s tick (title refresh + `onTick`) that runs only while active | AppKit | `rebuildMenu` |
| Dialogs | `Dialogs.swift` | Start-timer & settings forms, autocomplete field, dialog window host | SwiftUI | `DialogWindow.show` |
| Reports model | `Reports.swift` | Period filters, groupings, aggregation into `ReportResult`/`ReportRow` | Foundation | — |
| Reports UI | `ReportsWindow.swift` | Reports window: table + pie chart | SwiftUI | `ReportsWindowController.show` |
| Idle monitor | `IdleMonitor.swift` | Poll system idle seconds (CGEventSource) every 60s | CoreGraphics | `start` / `onTick` |
| Sleep monitor | `SleepMonitor.swift` | Observe sleep/wake/screen-sleep workspace notifications | AppKit | `start` / `onWillSleep` |
| Notifications | `NotificationManager.swift` | Request auth, post remind/auto-pause/pomodoro notifications with action buttons | UserNotifications | `postRemind` etc. |
| Autostart | `AutostartManager.swift` | Install/remove per-user LaunchAgent plist in `~/Library/LaunchAgents` | Foundation | `apply(enabled:)` |

## System Architecture

```
                     ┌──────────────────────────────────────────┐
                     │              AppDelegate                   │
                     │  (coordinator: owns timers, routes events) │
                     └──────────────────────────────────────────┘
        callbacks ▲      │ commands        ▲ events        │ commands
                  │      ▼                 │               ▼
   ┌────────────────────────┐   ┌──────────────────┐   ┌─────────────────────┐
   │  StatusItemController   │   │  IdleMonitor     │   │   TimerController    │
   │  Dialogs / ReportsWin   │   │  SleepMonitor    │──▶│  (state machine)     │
   │  NotificationManager    │   │  (poll/observe)  │   └─────────────────────┘
   └────────────────────────┘   └──────────────────┘             │ reads/writes
                  │ reads                                          ▼
                  └──────────────────────────────────▶ ┌─────────────────────┐
                                                        │  Storage layer       │
                                                        │  Journal/Current/    │
                                                        │  Config (CSV+JSON)   │
                                                        └─────────────────────┘
                                                                  │
                                                        ~/.config/mytime/*
```

UI and monitor components are decoupled from the coordinator via closures (`onTick`, `openStart`, `onResumeTapped`, …) — no component calls another directly except through `TimerController` and the storage layer. The dependency graph is acyclic: everything depends on `TimerController`/`Storage`/`Models`; those depend on nothing in the app.

### Timer state machine

```
        startNew                pause / idle / sleep
INACTIVE ───────▶ ACTIVE ◀──────────────────────────▶ PAUSED
   ▲                │  ◀── resume ──────────────────────┘
   │                │
   └─── stop / day-boundary close / pomodoro ───────────┘
       (finalize → append journal row, delete current.csv)
```

Boot recovery: a leftover `current.csv` on the same day → recover as PAUSED; crossing midnight → finalize and go INACTIVE.

## Data model

Three files under `~/.config/mytime/` (local ISO times, no timezone):

- **journal.csv** — append-only, finalized rows only. `DATE,CLIENT,ACTIVITY,DURATION_SECONDS`. One row per close, attributed to the timer's start day. Legacy 6-column rows migrated on first read.
- **current.csv** — at most one in-flight row. `START_TIME,CLIENT,ACTIVITY,STATUS,END_TIME,PAUSED_SECONDS`. Written on start/pause/resume/heartbeat; deleted on stop or day-boundary close. `END_TIME` is the last-known-alive moment (crash recovery).
- **config.json** — `AppConfig` (pretty-printed, sorted keys), human-editable, missing keys default on decode.

## Directory layout

```
mytime/
├── Package.swift            SwiftPM manifest (executable + test target, macOS 13)
├── build-app.sh             Build release binary → MyTime.app bundle + ad-hoc sign
├── Sources/MyTime/          All app code (flat, one file per component above)
├── Tests/MyTimeTests/       CSV, Journal, Reports, TimerController tests
├── Resources/Info.plist     LSUIElement=true (tray-only)
├── PRODUCT.md / FUNCTIONAL_SPEC.md / README.md
└── build/                   Output bundle (gitignored)
```

## Dev / test / deploy

- Build app bundle: `./build-app.sh` then `open build/MyTime.app`
- Run tests: `swift test`
- Deploy: drag `build/MyTime.app` to `~/Applications`; enable autostart via Settings (LaunchAgent) or System Settings → Login Items. Distribution is local/manual; ad-hoc codesigned, not notarized.

## Non-functional requirements

- **Accuracy under failure:** heartbeat persistence + boot consistency check + day-boundary close bound time lost to crashes/midnight to ≤ one heartbeat interval.
- **Local-first / privacy:** no network, no telemetry, no account; data is user-owned plaintext.
- **Unobtrusive:** menu-bar only, ≤ two clicks to start a repeat timer.
- **Single timer invariant:** only one active timer; starting auto-stops any running one.

## Crosscutting aspects

- **Concurrency:** all work on the main run loop; `Timer`s added in `.common` mode; no background queues. To keep battery impact negligible, the only fine-grained (5s) timer — the tray display tick, which also drives the pomodoro check — exists solely while a timer is `.active`; when inactive/paused, just coarse timers run (idle 60s, reminder ~30s, heartbeat in minutes).
- **Time:** all timestamps local ISO without timezone via `LocalISO`/`LocalDate`; day attribution via `Calendar.current.startOfDay`.
- **Persistence durability:** atomic writes for current/config; journal appends via `FileHandle` with atomic-rewrite fallback.
- **Permissions:** notifications degrade gracefully (in-menu warning) until granted.
- No caching, scaling, or observability concerns — single local process.

## Rules and Conventions

- **KISS / YAGNI** (from PRODUCT.md): deliberately simple; don't add layers, queues, or abstractions the single-process local app doesn't need.
- **One file per component**, flat under `Sources/MyTime/`; file name matches the primary type.
- **Decoupling via closures**: monitors and UI controllers expose `var onX: (() -> Void)?` callbacks set by `AppDelegate`; components don't reference each other directly.
- **Storage isolation**: only `Storage.swift` knows file formats/paths; `AutostartManager` is the exception (it owns `~/Library/LaunchAgents`, not `~/.config/mytime`) and is deliberately kept separate.
- **Testable time**: domain methods take `now: Date = Date()` so tests inject time; keep this pattern for any new time-dependent logic.
- **Backward-compatible persistence**: tolerate legacy/missing fields on read (`decodeIfPresent`, legacy CSV migration); never break existing user files.
- **CSV**: always go through `CSV.escape`/`CSV.parseAll` (RFC-4180) — never hand-format fields.
- **Tests** (`swift test`): cover domain/IO logic (CSV, Journal, Reports, TimerController), not UI.
