# Upcoming — wensenlijst

Eigen menu bar calendar app ter vervanging van Dato (lelijk) + Fantastical (overbodig zodra dit werkt).
Naam: **Upcoming** (gekozen 2026-06-11; naamcheck: alleen een Apple TV-only app "Upcoming - a simple calendar" op de App Store en het allang ter ziele Upcoming.org — geen macOS/menu bar collision).
Status: v0.1.0-skelet gebouwd (2026-06-11); dit document blijft de levende wensenlijst.

## Vaststaand (uit gesprek 2026-06-11)

- **Databron: EventKit, en niets anders.** Leest alles wat Calendar.app al synct — inclusief het Microsoft 365-account van de klant. Geen eigen account-setup, geen OAuth.
- **Design: heel dicht bij Fantastical** (screenshot 2026-06-11), maar **niet** de twee-tonen split — gewoon light. **Koerswijziging 2026-06-12: design volgt voortaan Apple Calendar waar dat afwijkt van Fantastical** — maar als richting, geen pixel-kloon: dicht bij Calendar qua look & feel, eigen vertaling waar onze vorm (lijst i.p.v. blokken-grid) daarom vraagt. Eerste toepassingen:
  - Maand-header: maand bold + jaartal light in dezelfde kleur (niet meer jaartal-rood), ‹ Today ›-cluster rechts met ronde grijze chevron-knoppen en een Today-capsule (springt grid + lijst terug naar vandaag).
  - All-day pills: capsule-vorm, kleuren pixel-identiek aan Calendar. Voor de gemeten kalenderkleuren (blauw 0/136/255, bruin 172/127/94, geel 255/204/0) zijn Apple's exacte pill-kleuren als **Display P3-waardes** vastgepind (`measuredPills`; het scherm rendert P3, dus alleen zo wordt het byte-gelijk — sRGB-formules blijven er net naast zitten). Ongemeten kleuren vallen terug op de HSB-fit — light: fill = verzadiging ×0,22 + helderheid naar 1−(1−b)×0,33, tekst = verzadiging ×1,3 + helderheid ×0,5; dark: fill = verzadiging ×0,85 + helderheid ×0,33, tekst = verzadiging ×0,85 + helderheid ×1,1. Opaak, geen alpha — een doorzichtige tint zakt in het panel-materiaal. Geen leading icoon-blokje zoals Calendar (bewust, besloten 2026-06-12). Light én dark zijn voor de drie gepinde kalenders per-pixel geverifieerd tegen native captures (2026-06-12).
  - Herhaal-icoon `arrow.trianglehead.2.clockwise` (SF 6, runtime-fallback naar `arrow.triangle.2.circlepath` op macOS 14) inline in pills en trailing bij getimede events.
  - Weekdagkoppen grid: enkele letters (M T W T F S S), stil grijs, geen highlight op huidige weekdag.
  - Agenda-dagkoppen: TODAY in expliciet diep rood (systemRed wast onder vibrancy uit naar zalm), overige dagen grijs, datum natuurlijk ("12 June 2026").
  - Onbeantwoorde uitnodigingen (participant-status pending of unknown — Exchange/Google leveren "needs action" als unknown, empirisch 2026-06-12): grijze 45°-arcering (opgemeten uit Calendar-screenshot: streep en gat elk ~4,5pt, veld ~4% + strepen ~4% erbovenop) over rij én pill, titel in grijs, balk/tekstkleur blijven vol — Calendar's behandeling vertaald naar de lijstvorm.
  - Tentative (Maybe geantwoord): arcering in de kalender-tint i.p.v. grijs, zoals Calendar — veld = pill-fill 33% naar wit, streep = pill-fill 9% naar de basiskleur (light; per-pixel geverifieerd), dark = fill 13%/29% naar zwart (binnen enkele waarden); titel houdt kleur (light: pill-tekstkleur, dark: de kale kalenderkleur).
  - Getimede rijen: gekleurd linker-balkje (3pt, afgerond) over de rijhoogte i.p.v. een dot — Calendar's blok-balkje vertaald naar de lijst (2026-06-12). De dots in het maandgrid blijven.
  - Vandaag-marker in de grid: gevuld **rood** afgerond vierkant (Apple's systemRed, gedeeld met de TODAY-kop via `Color.todayRed`); de kijkpositie-ring en het bijbehorende weeknummer zijn ook rood (2026-06-12, was blauw). Vervangt het eerdere blauwe vandaag-blok.
  - Maandgrid bovenin: weeknummer-kolom (zonder kolomkop — het "CW"-label bleek cryptisch, weg per 2026-06-11), week start op maandag, per dag gekleurde dots per agenda die die dag items heeft, vandaag = gevulde rode afgeronde rechthoek (rood per koerswijziging 2026-06-12, was blauw), de week-rij van de kijkpositie (niet per se vandaag) subtiel gehighlight en beweegt mee met lijst-scroll (zoals Fantastical), ‹ › maandnavigatie.
- **Klik op event (lijst: getimed, pill of verjaardag) → opent het event in Calendar.app** via `ical://ekevent/<EKEvent-identifier>?method=show&options=more`, identifier **volledig percent-encoded** (subscription-UID's bevatten complete URL's met `#`); popup sluit daarbij. Empirisch vastgesteld 2026-06-11: de MeetingBar-variant met occurrence-timestamp is een doodlopende weg (UTC: geen navigatie; lokale tijd: verkeerde maand) — dus occurrences van recurring events zijn niet gericht aanstuurbaar, Calendar kiest zelf welke hij toont. Eigen detail-popover blijft een mogelijke latere fase (HoverDetailWindow-patroon van Uncommitted ligt klaar).
  - Agenda-lijst onderin: begint bij vandaag, gegroepeerd per dag (TODAY / TOMORROW / weekdag + datum), all-day events als pill in de kalenderkleur van hun agenda, getimede events met gekleurde dot, tijdrange, titel en locatie.
  - Lijst scrollt **onbeperkt in beide richtingen** — omhoog het verleden in, omlaag de toekomst in (events lazy laden per datumvenster).
  - **Grid volgt de lijst:** de dag die bovenaan de lijst staat krijgt een **blauwe afgeronde-rechthoek-ring** in het maandgrid (vierkant, niet rond: de onderkant van een cirkel raakt de dot-rij) (vandaag = blauw gevuld; gevuld = vandaag, ring = kijkpositie — vallen samen als de lijst op vandaag staat; gekozen boven Fantastical's omkering, besloten 2026-06-11). Scrollen door de lijst beweegt die ring mee.
  - Gedimd zijn **alleen de events van vandaag die al geweest zijn** — een "dit is al gebeurd"-cue binnen vandaag. Dagen in het verleden (gisteren en eerder) tonen gewoon op volle kleur.
  - De licht-boven/donker-onder split is typisch Fantastical en geen must. **Appearance volgt het systeem** (besloten 2026-06-11: dark mode beviel direct) — let op: titels/accenten die vibrancy omzeilen moeten expliciet per appearance kleuren (maandtitel: zwart in light, wit in dark).
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
- **≥2 all-day events van één kalender op één dag vouwen samen tot één telling-pill** ("kalendernaam · N", kalenderkleur). Klik klapt uit voor die dag (reset bij heropenen), hover toont de titels als tooltip. Raakt alleen ruizige kalenders — losse pills blijven altijd los. Globale toggle in Settings → General ("Combine multiple all-day events from the same calendar"), default aan; per-kalender granulariteit pas als de praktijk erom vraagt (besloten 2026-06-11).
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

- **Andere weergaven:** alleen maandgrid, of ook week/dag?

## Wensen (aanvullen)

- …
