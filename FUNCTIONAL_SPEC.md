# MyTime - Functional Specification

macOS Time Tracking Tray Application

## Executive Summary

MyTime is a lightweight, minimalistic app that lives in the system tray (top-right area of macOS menu bar) for tracking time spent on client work. It provides idle detection, smart notifications, quick access to recent timers, and CSV-based data storage for easy integration with spreadsheet tools.

## Key Characteristics

**Tray-only application**:

- No dock icon, lives entirely in system tray:
- Able to autostart on boot
- No window shown on startup
- App continues running when last window closed, unless Quit is pressed

**Minimal UI**:

- Lightweight and elegant, non-intrusive, non-distracting dialogs for easy input and control
- Minimlistic app icon should remind of clock or timer
- When timer active show elapsed time (00:00:00) live (refreshed every 1 second) in tray next to the app icon
- When timer paused show pause with current elapsed time (⏸ 00:00:00 ) next to app icon
- Clicking it in tray displays Main Menu

## Storage of Time tracking data

All files stored under `~/.config/mytime/` (auto-created on first run).
Time values are local in ISO date/time format without timezone. CSV files
use RFC-4180-style escaping (quotes, commas, newlines in fields).

- **journal.csv** — append-only history of FINALIZED timers only.
  - Header row on first creation; every subsequent write is an append.
  - Format: `DATE, CLIENT, ACTIVITY, DURATION_SECONDS`
  - `DATE` is the local calendar day (`YYYY-MM-DD`) on which the timer
    started. `DURATION_SECONDS` is the worked time at close
    (`END_TIME − START_TIME − PAUSED_SECONDS`, clamped to ≥ 0).
  - Nothing is mutated after append. Files written by an earlier
    6-column format are migrated on first read (each row collapses to
    its start-date + duration).
- **current.csv** — single-row view of the in-flight timer.
  - Exists while a timer is ACTIVE or PAUSED; deleted when the timer stops.
  - Format: `START_TIME, CLIENT, ACTIVITY, STATUS, END_TIME, PAUSED_SECONDS`
    where `STATUS` is `active` or `paused`, `END_TIME` is the last-known
    alive moment (start, last tick, heartbeat, pause, or resume), and
    `PAUSED_SECONDS` accumulates while paused.
  - Rewritten on start, pause, resume, heartbeat, and midnight-split.
- **config.json** — settings; created with defaults if missing, human-editable.
  - Fields: `remindTrackingMinutes`, `idleToPauseMinutes`, `pomodoroEnabled`,
    `pomodoroWorkMinutes`, `launchAtLogin`, `heartbeatMinutes`.

## Crash-recovery heartbeat

To prevent wrong time calculations after a crash or power loss, while a
timer is ACTIVE the app periodically refreshes `current.csv` with the
latest `END_TIME` (and, while paused, advances `PAUSED_SECONDS`). The
interval is configurable (`heartbeatMinutes`, default 60, range 1…60).
Journal.csv is never touched by a heartbeat — heartbeats only extend the
single `current.csv` row.

### Boot-time consistency check

On every launch, MyTime inspects `current.csv`:

- If it doesn't exist, the previous session stopped cleanly — nothing to do.
- If the entry spans midnight (its `START_TIME` is on a calendar day
  earlier than `now`, or `END_TIME` has drifted past `START_TIME`'s day),
  close it (see below) and go INACTIVE.
- Otherwise, recover in PAUSED state, preserving `START_TIME`,
  `END_TIME`, and `PAUSED_SECONDS`. The user can resume (away time is
  added to `PAUSED_SECONDS`) or stop.

Heartbeats advance `END_TIME` only while the timer is ACTIVE. While paused
the row is untouched by heartbeats, except for the day-boundary close
described below.

### Day-boundary close on boot and heartbeat

Every journal row is attributed to a single calendar day. To enforce
this, both boot recovery and every heartbeat check whether the current
entry spans a day boundary. If so, the entry is closed:

1. Append one row to `journal.csv` with `DATE = start-of-day(START_TIME)`
   and `DURATION_SECONDS = max(0, END_TIME − START_TIME − PAUSED_SECONDS)`.
2. Delete `current.csv`. The timer goes INACTIVE.

Semantics per state:

- **PAUSED**: `END_TIME` is the pause moment — no time is lost.
- **ACTIVE**: `END_TIME` is the last heartbeat moment. Anything between
  the last heartbeat and midnight is not counted — the timer is treated
  as having stopped at the last known alive moment. Up to one heartbeat
  interval of tracking is lost around midnight.

## Main Menu Structure

```ui
⏸ Pause ClientName - Label   (only when timer running; toggles to "▶ Resume ..." when paused)
⏹ Stop ClientName - Label    (only when timer running)
─────────────────────
▶ Start New Timer...          (always visible; opens input dialog; auto-stops running timer)
─────────────────────         (quick start: 5 most recent client+label combos)
  ▶ Start ClientA - Development (examples of recent timers for quick start)
  ▶ Start ClientB - Meeting
  ▶ Start ClientC - Support
─────────────────────
Show Journal
View Reports
─────────────────────
Settings...
Quit
```

### Start New Timer

NOTE: Only one timer can be active at any given time.

**Behavior:**

1. If there is already running or paused timer - auto-stop it imlicitly with all due calculations and journal updates.
2. Show lightweight dialog with input fields:
    - **Client** (required) - Text field with autocomplete from existing clients
    - **Activity** (optional) - Text field with autocomplete
3. Write new `current.csv` with `STATUS=active`, `END_TIME=START_TIME`, `PAUSED_SECONDS=0`
4. Update app state to reflect running timer

### Pause Timer

NOTE: Pause Time can be triggered from the menu or automatically when computer is idle for some time (see below) or computer getting put on sleep (entering hibernation) either by timeout or by closing macbook cover.

**Behavior:**
    - Advance `END_TIME` to now and rewrite `current.csv` with `STATUS=paused`
    - App enters PAUSED TIMER state

### Resume Timer

- Add (now − `END_TIME`) to `PAUSED_SECONDS`
- Set `END_TIME = now`, `STATUS=active` and rewrite `current.csv`
- App enters ACTIVE TIMER state
- Timer can be paused/resumed multiple times

### Stop Timer

- Stops currently active timer immediately
- Paused timer first resumed and then immediately stopped
- Appends a finalized row to `journal.csv`:
  `END_TIME=now`, `DURATION_SECONDS = END_TIME − START_TIME − PAUSED_SECONDS`
- Deletes `current.csv`
- App enters INACTIVE TIMER state
- Updates menu to reflect new state and recent timers list

### Recent items list for quick start

Menu displays 5 most recent client+Label combinations

**Behavior:**

- Clicking item starts timer with that combination without showing dialog

### Settings Dialog

Lightweight dilog with user editable configuration:

1. Pomodoro Mode:
    - Auto-stop timer after work interval
    - Fields: enabled=false (default), work interval=25 minutes (default)

2. Time to remind about time tracking [remindTrackingMinutes]:
    - 15 minutes default, min 1 minute
    - Period of time no timer were active, before reminding about starting time tracking

3. Idle time to auto-pause [idleToPauseMinutes]:
    - 15 minutes default, min 1 minute
    - Period of time computer is not in use, before pausing currently active timer

4. Launch at login:
    - Off by default. When on, installs a per-user LaunchAgent so MyTime
      starts automatically when the user logs in.

5. Heartbeat interval [heartbeatMinutes]:
    - 60 minutes default, range 1…60.
    - How often the last-known-alive time is persisted to the journal while a
      timer is active, so it can be recovered after a crash or power loss.

---

## Notifications

Below is the list of notifications with buttons to process user reaction. In order notifications to work user should provide permissions.
Until then, special line with yellow notification icon should be visible in the drop down menu with a link to the relevant macos setting.

Notifications UI:

- UI should be lightweight yet noticable.
- Should be titled "MyTime" and have app icon, to make the origin clear for the user
- The notification should not automatically disappear, since we expect user reaction.

### Remind to track notification

**Purpose:** Remind user to start tracking in INACTIVE or PAUSED timer state.

**Behavior:**
    - If no timer in ACTIVE state for [remindTrackingMinutes] minutes, show the notification reminding to use time tracking.
    - User may ignore the notification, in that case it will continue showing up in [remindTrackingMinutes] minutes after user close the previous one.

**UI:**
    - **Message:** "Start tracking your time!"
    - **Action:** Just a close button.

### Auto-pause notification

**Purpose:** Notify user that timer paused becuase system was idle for some time [idleToPauseMinutes] or computer was put on sleep.

**Message (IDLE):** - Time tracking has been paused, because you were idle for NN min,  Action buttons: `Back to work (Resume)`, `Stop timer ClientName - Activity`

**Message (SLEEP):** - Time tracking has been paused because computer went asleep. Action buttons: `Back to work (Resume)`, `Stop timer ClientName - Activity`

**Behavior:**
    - Idle detection polls system every minute, notification triggered when detected specified [idleToPauseMinutes] ilde minutes in a row
    - This notification is not automatically disappear, until user clicks one of the two actions above
    - When user comes back and see the notification, they should click one of the two actions above, causing transitioning from PAUSED to ACTIVE or INACTIVE state with all due calculations and journal updates

### Pomodoro interval finished notification

When Pomodoro enabled in settings, after passing the specified work interval the timer auto-stops and record registered and notification is shown that the work interval is over.

---

## Show Journal

Open CSV in default app.

## Reports Window

**Window Properties:**
    - Size: 800x600 or responsive
    - Shows when opened, hides when closed
    - Not in taskbar (skip taskbar flag)

**Filters:**

**Period Selection:**
    - Day (today)
    - Week (last 7 days)
    - Month (last 30 days)
    - Year (last 365 days)
    - Custom (date picker range)

**Grouping Options:**
    - By Client
    - By Label
    - By Day of Week (Mon…Sun, aggregated across the filtered period)
    - By Day (one row per calendar day, e.g. `2026-04-18 (Sat)`)
    - By Week (one row per ISO week, e.g. `2026-W16 (Apr 13–19)`)
    - By Month (one row per calendar month, e.g. `2026-04 (April)`)
    - By Year (one row per calendar year, e.g. `2026`)

**Display:**
    - Side-by-side layout: table on the left, pie chart on the right
    - Table/list view with:
      - Colored swatch matching the slice in the pie chart
      - Group name
      - Total duration (HH:MM:SS)
      - Percentage of total time
      - Visual progress bar (same color as the matching pie slice)
    - Pie chart:
      - One slice per group, colors deterministic per group label so the
        legend (table) and chart always agree
      - Slices laid out clockwise from 12 o'clock, in the same order as table rows
      - Shows "No data" placeholder when filtered range is empty
    - Row ordering:
      - Calendar-bucket groupings (Day/Week/Month/Year) sort chronologically ascending
      - All other groupings sort by duration descending
    - Summary footer:
      - Total entries count
      - Total time tracked
      - Total time discarded (if any)


---

## Architecure

- Use SwiftUI to make native macOS app.
- Generate functional tests covering main functionality
- Stick to KISS and YAGNI principles, this is simple app, don't overengineer.
