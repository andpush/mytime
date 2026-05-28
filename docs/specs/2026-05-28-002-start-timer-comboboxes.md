# Solution Design Spec

**Title:** Start New Timer — native combo-box dropdowns for prior client/activity values
**Date:** 2026-05-28
**Status:** Ready to build
**Target:** Dialogs (`Dialogs.swift`), Timer engine (`TimerController.swift`), App coordinator (`AppDelegate.swift`)

## Goal

Make starting a repeat timer faster and more discoverable. Today the Start New Timer
dialog uses a custom `AutocompleteField` that renders an always-visible suggestion list
under each text field — it permanently consumes vertical space, shows at most 5 contains-matches,
and has no way to browse the *full* set of prior values or navigate by keyboard.

Replace both fields with native macOS combo boxes (`NSComboBox`): a text field you can still
type a brand-new value into, plus a chevron that drops the full list of prior values, with
built-in inline autocomplete and keyboard navigation. The Activity dropdown is scoped to the
selected client (activities previously paired with that client first), matching the
client+activity combo model the app already tracks for quick-start.

Value: fewer keystrokes and less recall for repeat work (reinforces the "two clicks or fewer
for repeat work" success signal in [PRODUCT.md](../../PRODUCT.md)), using the idiomatic
platform control instead of bespoke UI.

### Constraints & assumptions

- macOS native, SwiftUI dialog hosted in AppKit (per [ARCHITECTURE.md](../../ARCHITECTURE.md));
  `NSComboBox` is reached via `NSViewRepresentable`.
- KISS/YAGNI — one dialog, no new persistence, no config, no schema change.
- A brand-new client/activity (not in history) must remain enterable — free text, not a fixed picker.
- Client stays required; Activity stays optional. Start behavior (`controller.startNew`) is unchanged.
- Suggestion ordering source stays the journal, most-recent-first, as the existing
  `knownClients()` / `knownActivities()` already derive.

### Non-goals

- No change to the in-menu quick-start list of 5 recent combos (already covers the fastest path).
- No fuzzy/ranked search beyond `NSComboBox`'s built-in prefix completion.
- No styling tokens / theming work; this is interaction, not a visual redesign.

## Solution

### Description

1. Add a reusable `ComboBoxField` (`NSViewRepresentable` wrapping `NSComboBox`) in
   `Dialogs.swift`: bound `text`, a `suggestions: [String]` list, `completes = true`,
   `usesDataSource = false`. The coordinator bridges `controlTextDidChange` and combo-box
   selection back into the SwiftUI `@Binding`. Delete the old `AutocompleteField`.
2. `StartTimerView` uses `ComboBoxField` for Client and Activity. The Client field is first
   responder on open. The Activity field's `suggestions` are recomputed from the current
   `client` value via an injected closure, so picking/typing a client re-scopes activities live.
3. Add `TimerController.knownActivities(forClient:)` — activities used with the given client
   (most-recent-first, de-duped), then the remaining known activities appended (so the full
   set is still browsable). Empty/unknown client → same as `knownActivities()`. This keeps the
   scoping logic in the engine (testable), not the view.
4. `AppDelegate.showStartDialog` passes `clients`, the initial `activities`, and an
   `activitiesForClient: (String) -> [String]` closure backed by the controller.

### Architecture

No structural change. Data flow within the existing dialog path:

```text
AppDelegate.showStartDialog
   ├─ clients              = controller.knownClients()
   ├─ activities           = controller.knownActivities()
   └─ activitiesForClient  = { controller.knownActivities(forClient: $0) }
                 │
                 ▼
        StartTimerView (SwiftUI)
   client ─ ComboBoxField(suggestions: clients)
   activity ─ ComboBoxField(suggestions: activitiesForClient(client))
                 │ onStart(client, activity)
                 ▼
        controller.startNew(client:activity:)   (unchanged)
```

### Key decisions & rejected approaches

- **Native `NSComboBox` via `NSViewRepresentable`** over a SwiftUI custom popover or polishing
  the inline list. It is the idiomatic macOS control, gives free-text + full dropdown +
  autocomplete + keyboard nav for the least bespoke code, and removes the permanent vertical
  list. Rejected: SwiftUI `Picker`/`Menu` (no free-text entry for new clients); custom popover
  (more code to own for no platform benefit).
- **Activity scoped to selected client** (used-with-client first, then the rest) over a flat
  global list — matches the client+activity combo model and surfaces the right repeats, while
  still allowing any activity. Scoping lives in `TimerController` so it is unit-testable.

### Affected components & files

- **Dialogs** (`Sources/MyTime/Dialogs.swift`)
  - Add `ComboBoxField: NSViewRepresentable` (+ `Coordinator`); remove `AutocompleteField`.
  - Update `StartTimerView`: combo boxes, Client first-responder, live activity re-scoping via
    injected `activitiesForClient` closure.
- **Timer engine** (`Sources/MyTime/TimerController.swift`)
  - Add `func knownActivities(forClient client: String) -> [String]`.
- **App coordinator** (`Sources/MyTime/AppDelegate.swift`)
  - `showStartDialog`: pass `activitiesForClient` closure into `StartTimerView`.
- **Tests** (`Tests/MyTimeTests/`)
  - Add cases for `knownActivities(forClient:)`.

### UI changes

Start New Timer dialog: two labeled combo boxes (Client required, Activity optional) replacing
the two text-field-plus-inline-list widgets. Empty closed state is more compact (no
always-on list). Chevron opens the full prior-values list; typing filters via inline completion.
Cancel/Start buttons and keyboard shortcuts (Esc / Return) unchanged; Start stays disabled
until Client is non-empty.

### Error handling

- Empty/whitespace Client → Start disabled (existing guard retained); values trimmed before
  `startNew`.
- Unknown client typed → activity suggestions fall back to the full known-activities list.
- No history at all → both combo boxes are empty but fully usable as plain text fields.

### Testing approach

Per repo convention, UI (`Dialogs.swift`) is not unit-tested; the new *engine* logic is.
Unit-test `TimerController.knownActivities(forClient:)` against a `Journal` backed by a temp
file (the pattern existing `TimerController`/`Journal` tests already use):

- activities used with the client come first, most-recent-first, de-duplicated;
- activities never used with the client are still present, appended after;
- unknown/empty client returns the same as `knownActivities()`;
- empty activities (client-only rows) are excluded.

Manual smoke (not automated): build the app, open Start New Timer, confirm chevron lists prior
values, typing autocompletes, choosing a client re-scopes the activity list, a new client name
can still be entered and started.

## Verification

### Acceptance criteria

- [ ] Start New Timer shows Client and Activity as native combo boxes; each opens a dropdown of
      prior values via its chevron and supports inline autocomplete while typing.
- [ ] A brand-new client and/or activity not present in history can still be typed and started.
- [ ] The Client field holds keyboard focus when the dialog opens.
- [ ] Selecting/typing a client re-scopes the Activity dropdown: activities previously used with
      that client appear first (most-recent-first), with the remaining known activities still
      listed after.
- [ ] `TimerController.knownActivities(forClient:)` returns client-scoped-first ordering, excludes
      empty activities, and falls back to the full list for an unknown/empty client — covered by tests.
- [ ] Start remains disabled until Client is non-empty; trimmed client/activity reach `startNew`;
      existing start/auto-stop behavior is unchanged.
- [ ] `swift test` green.

### Definition of Done

The build is done only when **every** box below holds.

- [ ] Tests written for `knownActivities(forClient:)` and passing — `swift test` green.
- [ ] All acceptance criteria above met.
- [ ] No duplication, no dead code (old `AutocompleteField` removed), no obvious issues; consistent with `ARCHITECTURE.md`.
- [ ] Memory updated: `FUNCTIONAL_SPEC.md` Start New Timer section updated to describe combo-box dropdowns + client-scoped activities; `ARCHITECTURE.md`/`README.md` only if they drift. No new ADR required unless an architectural choice emerges during build.
- [ ] Spec `Status` flipped to `Done (YYYY-MM-DD)` — the final act.
- [ ] Changes committed with proper message.
