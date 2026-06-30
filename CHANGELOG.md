# Changelog

User-facing notes for each release. Bullets are curated — not a 1:1
mapping of commits.

## v0.4.1 — 2026-06-30

### Fixes
- The agenda's day labels (TODAY / TOMORROW) no longer get stuck on the
  previous day's wording after midnight — the header now refreshes the
  date when you reopen the popup, so today reads "TODAY".

## v0.4.0 — 2026-06-29

### New
- Search your agenda: a search field scans a wide window of events and
  lists every match in chronological order, with a TODAY divider so past
  and upcoming results stay oriented.
- Create events from the agenda: each day has a + button that opens
  Calendar to add a new event on that day.

### Improvements
- The agenda's video-call button now shows a clear hover state — a soft
  accent pill and a pointing-hand cursor — so it reads as clickable.
- App icon cleanup: dropped the coloured glow behind the glyph dots for a
  crisper look.

## v0.3.0 — 2026-06-19

### New
- Hover any event in the agenda — or an all-day pill — for an Apple
  Calendar-style detail popover: title, location, the date with its
  recurrence and alert, attendees with their response status, notes,
  and a map of the location with the local temperature.
- Hover a day in the month grid to preview that day's agenda without
  leaving the grid.
- The popover is interactive: Join a video call, open links, or click
  the map to open the location in Apple Maps.
- Collapsed all-day count pills ("Calendar · 3") preview their hidden
  events on hover.

### Improvements
- Auto-update: Upcoming keeps itself up to date. It checks
  automatically, or on demand from Settings → About → Check for Updates.
