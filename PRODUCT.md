# Product

**Status:** Current
**Updated:** 2026-05-28

## Purpose

People who bill or account for their time (client work, projects, activities) need an honest record of where the hours went. Heavyweight time trackers are intrusive, cloud-bound, and over-featured; a simple stopwatch loses time to crashes, idle periods, and forgotten timers. MyTime keeps an accurate, local, low-friction record without getting in the way.

## Users

Solo professionals and freelancers on macOS who track time against clients and activities — primarily to bill or report. They want something that lives quietly in the menu bar, owns its data locally, and exports trivially to a spreadsheet. Secondary: anyone wanting personal time accounting (focus, projects) with the same low-ceremony tool.

## Solution

A native macOS menu-bar app that tracks one timer at a time with near-zero ceremony — start in two clicks, see elapsed time live in the tray — while quietly protecting accuracy through idle/sleep auto-pause, crash-recovery heartbeats, and clean per-day attribution. Data is plain CSV the user owns and can open in any spreadsheet.

## Value

- Start, pause, resume, and stop tracking client/activity time from the menu bar without opening a window.
- Trust the recorded total: idle time and sleep auto-pause, and a heartbeat recovers in-flight time after a crash or power loss.
- Re-start the 5 most recent client+activity combos in one click.
- Stay honest about tracking via reminders when no timer is running.
- Review where time went with filterable, grouped reports (table + pie chart).
- Own the data — local CSV, human-editable config, spreadsheet-friendly, no cloud, no account.

## Constraints

- macOS native, menu-bar-only (`LSUIElement` — no dock icon, no startup window).
- SwiftUI; KISS/YAGNI — deliberately simple, not over-engineered.
- Local-only storage under `~/.config/mytime/`; CSV must stay spreadsheet-compatible (RFC-4180 escaping). No cloud, no telemetry.
- One active timer at a time.
- Times stored as local ISO date/time without timezone; every journal row attributed to a single calendar day.
- Notifications require user permission; degrade gracefully (in-menu warning) until granted.

## Scope

### Core Features (MVP)

- Tray timer with live elapsed display; start / pause / resume / stop.
- Start-new-timer dialog with client (required) + activity (optional) autocomplete; auto-stops any running timer.
- Quick-start list of 5 most recent client+activity combos.
- Idle and sleep auto-pause with resume/stop notification; reminder-to-track notification; optional Pomodoro auto-stop.
- Crash-recovery heartbeat, boot consistency check, and day-boundary close.
- Local CSV journal + single-row current-timer file + human-editable config.
- Reports window: period filters, multiple groupings, table + pie chart.
- Launch-at-login via per-user LaunchAgent.

### Out / Later

- Multi-platform (Windows/Linux/mobile), cloud sync, multi-user, accounts.
- Concurrent/multiple simultaneous timers.
- Invoicing, billing rates, or integrations with accounting tools.

## Success signals

- Recorded durations match reality — minimal time lost to crashes, idle, or forgotten timers (at most ~one heartbeat interval lost around midnight on an active timer).
- Tracking a session takes two clicks or fewer for repeat work.
- Users can produce a billing/reporting breakdown from the reports window or by opening the CSV directly.

## References

- [FUNCTIONAL_SPEC.md](FUNCTIONAL_SPEC.md) — full behavioral spec (the WHAT/HOW).
- [README.md](README.md) — build, run, data locations.
