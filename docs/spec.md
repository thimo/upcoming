# Upcoming — wensenlijst

Eigen menu bar calendar app ter vervanging van Dato (lelijk) + Fantastical (overbodig zodra dit werkt).
Naam: **Upcoming** (gekozen 2026-06-11; naamcheck: alleen een Apple TV-only app "Upcoming - a simple calendar" op de App Store en het allang ter ziele Upcoming.org — geen macOS/menu bar collision).
Status: v0.1.0-skelet gebouwd (2026-06-11); dit document blijft de levende wensenlijst.

## Vaststaand (uit gesprek 2026-06-11)

- **Databron: EventKit, en niets anders.** Leest alles wat Calendar.app al synct — inclusief het Microsoft 365-account van de klant. Geen eigen account-setup, geen OAuth.
- **Design: heel dicht bij Fantastical** (screenshot 2026-06-11), maar **niet** de twee-tonen split — gewoon light:
  - Maandgrid bovenin: weeknummer-kolom (CW), week start op maandag, per dag gekleurde dots per agenda die die dag items heeft, vandaag = gevulde blauwe cirkel (gehighlight), huidige week-rij subtiel gehighlight, ‹ › maandnavigatie, maand zwart + jaartal rood.
  - Agenda-lijst onderin: begint bij vandaag, gegroepeerd per dag (TODAY / TOMORROW / weekdag + datum), all-day events als pill in de kalenderkleur van hun agenda, getimede events met gekleurde dot, tijdrange, titel en locatie.
  - Lijst scrollt **onbeperkt in beide richtingen** — omhoog het verleden in, omlaag de toekomst in (events lazy laden per datumvenster).
  - **Grid volgt de lijst:** de dag die bovenaan de lijst staat krijgt een highlight in het maandgrid (los van de blauwe vandaag-cirkel). Scrollen door de lijst beweegt die highlight mee.
  - Gedimd zijn **alleen de events van vandaag die al geweest zijn** — een "dit is al gebeurd"-cue binnen vandaag. Dagen in het verleden (gisteren en eerder) tonen gewoon op volle kleur.
  - De licht-boven/donker-onder split is typisch Fantastical en geen must — alles light. (Open: dark mode van het systeem volgen, of altijd light?)
- **Tech: opzet erft van Uncommitted (`~/src/uncommitted`) + Clawbridge (`~/src/clawbridge`).** Niet opnieuw uitvinden:
  - **Popup = custom NSPanel met NSHostingView** (Uncommitted's `PopupPanel` in `AppDelegate.swift`) — NIET SwiftUI MenuBarExtra, NIET NSMenu. Let op: Uncommitted's CLAUDE.md zegt "NSMenu" maar de code is NSPanel — NSMenu's tracking loop breekt scrolling/right-click (fataal voor onze oneindige lijst), NSPopover kan zijn arrow niet kwijt. AppDelegate.swift als sjabloon: rounded-mask vibrancy, click-outside monitors, Space-switch dismiss.
  - **SPM-layout van Uncommitted:** Core-library (testbaar, framework-vrij) + dunne executable-shell + plain-Swift testrunner (geen XCTest op CLT-only toolchain).
  - **build.sh van Uncommitted** (release build, iconset via `make-icon.swift` Big Sur-template, bundle, installeer naar `~/Applications`) — maar signing zoals **Clawbridge**: Developer ID "Theodorus Jansen (SCP9WFJV88)", géén ad-hoc — ad-hoc geeft elke build een nieuwe cdhash en dat invalideert de EventKit TCC-grant.
  - **Sleep/wake-backstop** (NSWorkspace.didWakeNotification + trage timer) uit Uncommitted's RepoStore — zelfde patroon voor kalender-refresh naast `EKEventStoreChanged`.
  - Eventuele detail-popover later: Uncommitted's `HoverDetailWindow` (NSPanel als child window, `CardWithArrowShape`) ligt klaar.
  - macOS 14+ (EventKit `requestFullAccessToEvents`).
- **Menu bar item: alleen icoon** — kalender-icoon met dagnummer, minimale breedte.
- **Read-only.** Kijken + doorklikken; wijzigen doe je in Calendar.app.
- **Geen zoekveld.** Zoeken is Calendar.app's werk.
- **Geen Reminders.** Puur calendar.
- **Declined meetings worden verborgen** — weg uit lijst én grid-dots.
- **Meerdaagse events:** pill op elke dag waarop het event loopt (zoals Fantastical).
- **Verjaardagen (systeem-verjaardagskalender) als rij met cadeau-icoon**, niet als all-day pill — Fantastical's weergave. Tussen de pills en de getimede events.
- **All-day pills: volledige titel, nooit afkappen.** Pills flowen horizontaal en wrappen naar de volgende regel als ze niet op één regel passen (FlowLayout in AgendaListView).
- **Klik op dag in het grid → lijst scrollt naar die dag.** Dagen zonder events landen op de eerstvolgende dag mét events. (Beslist 2026-06-11; stond bij open keuzes.)
- **Notificaties alleen voor events met een video-call link** — meldingen voor meetings waar je moet inbellen, de rest niet.
- **Settings: kalenderlijst met per-kalender aan/uit-toggle.** Eigen selectie, los van Calendar.app's zichtbaarheids-vinkjes. Uitgezette kalenders verdwijnen uit grid-dots én lijst.
- **Notificatie X minuten voor aanvang** van een event (X instelbaar in settings via dropdown, default 1 minuut). Eigen notificaties via UserNotifications, los van de alarms die Calendar.app zelf al doet.
  - Heeft het event een video-call link, dan heeft de notificatie een klikbare join-actie die de juiste app opent (zelfde detectie als het video-icoon in de lijst).
- **Video-call detectie:** events met een video-call link (Teams, Zoom, Meet, …) tonen een video-icoon; klik op het icoon opent de juiste app/link. Link zoeken in URL-veld, locatie en notes van het event.
- **Teams-links openen direct in de Teams-app** via het `msteams:`-scheme (alleen corporate `teams.microsoft.com`-joins; browser-fallback als Teams niet geïnstalleerd is, `teams.live.com` blijft browser).
- **Settings = SwiftUI `Settings`-scene met tabs** (opzet van Uncommitted): General (launch at login via SMAppService, hotkey-recorder), Calendars (per-kalender toggles, gegroepeerd per account), About.
- **Globale hotkey om de popup te togglen, default ⌘⇧C** — Carbon `RegisterEventHotKey` (Uncommitted's HotkeyManager), instelbaar/wisbaar in Settings → General.
- **Footer onderin de popup** (Uncommitted's patroon): gear-icoon → Settings, Quit rechts.

## Later (niet MVP)

- **Distributie: download via GitHub.** Uncommitted's pipeline hergebruiken: release.sh (universal binary, Developer ID, notarization, stapling), Sparkle-appcast voor auto-updates, eventueel Homebrew tap. Betekent wel: vanaf dag één hardened runtime + entitlements meenemen zodat notarization later geen verbouwing is.

## Open keuzes

- **Appearance:** systeemdark volgen, of altijd light?
- **Klik op event in de lijst:** nog onbeslist. Voorstel Vonk: MVP klik → opent event in Calendar.app (`ical://ekevent/...`-route, vrijwel gratis); eigen detail-popover (notes/deelnemers) eventueel als latere fase. Fantastical doet beide.
- **Andere weergaven:** alleen maandgrid, of ook week/dag?

## Wensen (aanvullen)

- …
