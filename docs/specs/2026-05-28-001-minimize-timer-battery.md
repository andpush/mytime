# Solution Design Spec

**Title:** Minimize battery impact of always-on timers
**Date:** 2026-05-28
**Status:** Done (2026-05-28)
**Target:** `TimerController`, `StatusItemController`, `AppDelegate`

## Goal

Make MyTime's CPU wakeups negligible when not actively tracking, and reduce
them while active — without changing tracking accuracy. Today three 1-second
`Timer`s run on the main run loop *always* (even inactive), which keeps the CPU
waking 3×/second for no benefit and shows up as Energy Impact / App Nap
throttling on battery. This directly serves the "unobtrusive, local-first" and
KISS/YAGNI stance in [PRODUCT.md](../../PRODUCT.md) and the main-run-loop
concurrency model in [ARCHITECTURE.md](../../ARCHITECTURE.md).

The three offenders:

1. `TimerController.ticker` (`TimerController.swift:23`) fires every 1s to set
   `@Published tickDate` — **dead code**: `TimerController` is never observed as
   an `ObservableObject` (the menu uses its own timer; SwiftUI views take
   `journal`). Zero subscribers.
2. `StatusItemController.uiTimer` (`StatusItemController.swift:43`) — 1s tray
   title refresh. The only timer that drives the visible elapsed clock.
3. `AppDelegate.pomodoroWatch` (`AppDelegate.swift:67`) — 1s pomodoro threshold
   check.

### Constraints & assumptions

- Tracking **accuracy must not change**: durations are always recomputed from
  wall-clock `endTime`/`now` deltas (`TimerController.displayElapsed`), never
  accumulated from tick counts — so a coarser tick affects only display
  smoothness and pomodoro stop precision, not recorded time.
- Pomodoro auto-stop may overshoot its threshold by up to one tick (≤5s).
  Acceptable.
- Tray title only changes while a timer is **active**: when paused,
  `displayElapsed` is frozen at `endTime`; when inactive, the title is empty.
- KISS: 5s tick is hardcoded; **no new setting** (decided with user).

### Non-goals

- No new config field / Settings UI change (rejected `displayRefreshSeconds`).
- Idle (60s), reminder (~30s), and heartbeat (minutes) timers are **unchanged** —
  already coarse and cheap; folding them onto the fine timer would make it do
  useless work.
- No change to journal/current/config file formats or the timer state machine.

## Solution

### Description

1. **Delete the dead ticker.** Remove `TimerController.ticker`, its
   `startTicker()`, and the `@Published var tickDate` (and the 1s `Timer` it
   drives). Verify no remaining reference to `tickDate` exists.
2. **Single active-only display timer.** `StatusItemController` owns one
   repeating `Timer` at a `5.0`s interval that refreshes the tray title **and**
   runs the pomodoro check. It is created when the timer transitions to
   `.active` and invalidated on `.paused`/`.inactive` (and on stop). When not
   active, no fine-grained timer exists.
3. **Move the pomodoro check onto that tick.** `AppDelegate.pomodoroWatch` and
   `checkPomodoro()`'s standalone 1s timer go away; the pomodoro threshold check
   runs from the same 5s tick (only meaningful while active). The existing
   stop-and-notify behavior is preserved; `AppDelegate` still owns the policy
   (config + notification), invoked via a callback from the tick.

The driver of "active-only" is the existing state transitions
(`startNew`/`resume` → active; `pause`/`stop`/day-boundary close → not active).
`StatusItemController.refreshTitle()` is already called on every menu action; we
add timer start/stop alongside it so the timer's lifetime tracks `.active`.

### Architecture

No structural/boundary change. Timer ownership before/after:

```text
BEFORE (always firing, even when INACTIVE):
  TimerController.ticker      1s  → tickDate (nobody listens)      [DEAD]
  StatusItemController.uiTimer 1s → refreshTitle()
  AppDelegate.pomodoroWatch   1s  → checkPomodoro()
  + idle 60s, reminder 30s, heartbeat Nmin   (unchanged)

AFTER:
  StatusItemController.tickTimer 5s → refreshTitle() + pomodoro check
        └─ exists ONLY while state == .active; nil otherwise
  + idle 60s, reminder 30s, heartbeat Nmin   (unchanged)

  INACTIVE/PAUSED → zero fine-grained timers.
```

### Key decisions & rejected approaches

- **Hardcode 5s, no setting** — chosen over a configurable interval for KISS;
  one fewer config field, and 5s is plenty smooth for a tray clock.
- **Gate on `.active` only (not paused)** — paused elapsed is frozen, so a
  paused refresh would be pure waste.
- **One timer for display + pomodoro, leave idle/reminder/heartbeat alone** —
  consolidate only what shares the fine cadence; coarse timers are already
  negligible and merging them would add useless counter-checks.
- **Delete `tickDate`/`ticker` rather than wire it up** — it has no consumer;
  YAGNI.

### Affected components & files

- **Timer engine**
  - `Sources/MyTime/TimerController.swift` — remove `ticker`, `startTicker()`,
    `tickDate`; ensure `init` no longer starts a ticker.
- **Menu bar UI**
  - `Sources/MyTime/StatusItemController.swift` — replace `uiTimer` (1s,
    always-on) with a 5s `tickTimer` started/stopped by timer state; add a
    `var onTick: (() -> Void)?` (or equivalent) the tick calls so `AppDelegate`
    can run the pomodoro check; start/stop the timer from the state-changing
    actions and `refreshTitle` path.
- **App coordinator**
  - `Sources/MyTime/AppDelegate.swift` — delete `pomodoroWatch` and its
    `scheduledTimer` setup; keep `checkPomodoro()` logic but invoke it from the
    `StatusItemController` tick callback.

### Testing approach

This is partly a refactor (timer plumbing) and partly a behavior change (tick
cadence). Timer firing itself isn't unit-tested today (`AppDelegate`/
`StatusItemController` are UI/AppKit), so:

- **Unit (swift test):** `TimerControllerTests` — confirm `displayElapsed`,
  pomodoro-relevant elapsed, start/pause/resume/stop, and recovery behavior are
  unchanged after removing `ticker`/`tickDate` (these already inject `now:`).
  Add/keep a test asserting elapsed is computed from wall-clock deltas, not tick
  counts (locks the "accuracy independent of cadence" invariant).
- **Manual (cannot unit-test AppKit timers):** run the app and observe —
  tray clock advances ~every 5s while active; pomodoro still auto-stops near its
  threshold; no fine timer activity when inactive/paused (sample CPU / Energy
  Impact shows the menu-bar app effectively idle between coarse timers).

## Verification

### Acceptance criteria

- [ ] `TimerController` no longer declares `ticker`, `startTicker`, or
  `tickDate`; `grep -r tickDate Sources` returns nothing.
- [ ] No `Timer` with `withTimeInterval: 1.0` remains in `Sources/MyTime`
  (`grep -rn "withTimeInterval: 1" Sources` is empty).
- [ ] While a timer is `.active`, the tray title updates on a 5s cadence;
  exactly one fine-grained (≤5s) repeating timer exists.
- [ ] While `.inactive` or `.paused`, no fine-grained (≤5s) repeating timer
  exists; only idle (60s), reminder (~30s), and heartbeat (minutes) remain.
- [ ] Pomodoro still auto-stops the active timer within ~5s of its
  `pomodoroWorkMinutes` threshold and posts the finished notification.
- [ ] Recorded durations are unchanged for identical start/stop times (accuracy
  independent of tick cadence) — `swift test` green.

### Definition of Done

- [ ] Tests written/updated for the changed behavior and passing — `swift test` green.
- [ ] All acceptance criteria above met.
- [ ] No duplication, no dead code, no obvious security issues; consistent with `ARCHITECTURE.md`.
- [ ] Memory updated: `ARCHITECTURE.md` "Crosscutting aspects" (concurrency) and the timer list updated to reflect the single active-only tick timer; deferred ideas (if any) to `IDEAS.md`. No `ADR.md` entry required (no architectural-boundary change).
- [ ] Spec `Status` flipped to `Done (YYYY-MM-DD)` — the final act.
- [ ] Changes committed with proper message.
