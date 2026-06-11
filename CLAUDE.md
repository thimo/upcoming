# Upcoming

Native macOS menu bar calendar app: Fantastical-style month grid + agenda
list, fed exclusively by EventKit (everything Calendar.app syncs, including
Microsoft 365/Exchange — no own accounts, no OAuth). Replaces Dato (ugly)
and Fantastical (can't reach the client's M365 tenant).

**The spec lives at `docs/spec.md`** — wishlist, decided choices, and open
questions. Read it before adding features, and keep it updated when Thimo
adds wishes.

## Current state

- v0.1.x, generated 2026-06-11 from the Vonk session that wrote the spec;
  running live on the menu bar since the same day, iterating on look &
  feel with Thimo.
- Working: status item (SF Symbol `calendar`, 17.5pt), NSPanel popup,
  month grid with CW column + per-calendar dots + today circle +
  click-day-→-agenda-jumps, agenda list (today → +60 days) with wrapping
  all-day pills (FlowLayout, full titles) / dimmed-past-today /
  video-call icon, declined-meeting filtering, EventKit change refresh,
  async background event fetch (popup must never block on EventKit —
  Exchange fetches take hundreds of ms), Teams links open in the Teams
  app (msteams: rewrite, browser fallback), escape + click-outside +
  Space-switch dismissal, right-click → Settings…/Quit, popup footer
  (gear → Settings, Quit), global hotkey ⌘⇧C (Carbon, recorder in
  Settings), tabbed Settings via the SwiftUI `Settings` scene (General:
  shortcut + launch at login; Calendars: per-calendar toggles grouped by
  account; About). App lifecycle is SwiftUI App (`UpcomingApp.swift`, no
  main.swift) with NSApplicationDelegateAdaptor — Uncommitted's setup.
- Not built yet (spec'd): bidirectional infinite agenda scroll (the +60d
  window is a placeholder), grid-follows-list highlight, notification
  lead-time setting + notifications X min before events with a call link
  (with join action), day-number-in-icon menu bar glyph, app icon.

## Build & install

- `./build.sh` — release build, runs tests, bundles the `.app`, signs with
  **Developer ID** (NOT ad-hoc — TCC keys the Calendars grant to the
  designated requirement; ad-hoc re-signing invalidates it every rebuild),
  installs to `~/Applications/Upcoming.app`. Kills a running instance.
- Tests: `.build/release/UpcomingTests` — plain-Swift runner, no XCTest
  (Command Line Tools toolchain has none).

## Layout

Three SPM targets (pattern copied from `~/src/uncommitted`):

- **`UpcomingCore`** — models (`EventItem`, `DaySection`, `CalendarInfo`,
  `CalendarColor`), `EventGrouping` (day sections + grid dots, multi-day
  spanning), `VideoCallDetector` (Teams/Zoom/Meet/… link in url → location
  → notes order), `CalendarService` (EventKit wrapper, declined filter),
  `AppConfig` (UserDefaults).
- **`Upcoming`** — `main.swift`, `AppDelegate` (status item + `PopupPanel`),
  `ContentView`, `MonthGridView`, `AgendaListView`.
- **`UpcomingTests`** — plain executable test runner.

## Non-obvious choices (inherited scars, don't relitigate)

1. **Popup is a custom NSPanel** (`PopupPanel` in AppDelegate), not
   NSPopover (arrow can't be hidden), not NSMenu (tracking loop breaks
   scrolling — fatal for the infinite agenda list), not MenuBarExtra.
   Uncommitted paid for this lesson; its AppDelegate is the donor. Note:
   Uncommitted's CLAUDE.md claims "NSMenu" — that doc is stale, the code
   is NSPanel.
2. **Developer ID signing from day one** (Clawbridge lesson). See build.sh
   header. Hardened runtime + calendars entitlement are already in place
   so notarization later is no rework.
3. **EventKit only.** Never add provider integrations; macOS Internet
   Accounts does the syncing.
4. **Declined meetings are filtered out** in CalendarService (spec).
5. All-day EKEvents end at the *next* midnight — `EventGrouping` clamps
   with a -1s nudge so they don't leak an extra day. Tests cover this.

## Roadmap (rough order)

1. Run + visually iterate on the popup (compare against the Fantastical
   screenshot in the spec).
2. Settings window: per-calendar toggles, notification lead time.
3. Bidirectional infinite scroll + grid-follows-list highlight.
4. Notifications (UserNotifications) with join action.
5. Menu bar glyph with day number; app icon (make-icon.swift pattern).
6. Distribution via GitHub: reuse Uncommitted's release.sh + Sparkle
   pipeline.

## Conventions

- **Don't push to origin** — Thimo handles all pushes.
- **Commit identity** `thimo@defrog.nl`; messages short (subject + max 1-2
  sentences of why), no Co-Authored-By trailer.
- Match Uncommitted's code style where in doubt.
