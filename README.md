# MyTime

A lightweight macOS menu bar time-tracking app. See `FUNCTIONAL_SPEC.md`.

## Build & run

```bash
./build-app.sh
open build/MyTime.app
```

The bundle has `LSUIElement=true` — no dock icon, tray only.

## Data

- `~/.config/mytime/journal.csv` — all time entries (CSV, spreadsheet-friendly)
- `~/.config/mytime/config.json` — settings (human-editable)

## Tests

```bash
swift test
```

## Autostart on login

Drag `build/MyTime.app` into `~/Applications`, then:
`System Settings → General → Login Items → Open at Login → +` and add MyTime.

## Notifications

On first launch, allow notifications when prompted, or open
`System Settings → Notifications → MyTime`. Until granted, the menu shows
a warning item that opens the settings pane.
