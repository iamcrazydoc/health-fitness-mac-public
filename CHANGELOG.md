# Changelog

All notable changes to this app. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.8.0] - 2026-11-26
### Changed
- Nothing personal is built in any more (#19). The goal time, race date and name and an optional dashboard link move to a new Settings > Goal section; the home city has no default (set it in Settings > Home to get the weather). Dates follow the Mac's time zone.
- The goal widget is now called "Half goal". Remove the old one and add it again from Edit Widgets.
### Removed
- The training plan built into the app. The plan comes from the 🏃/🏁 events in your calendar.

## [1.7.0] - 2026-11-26
### Added
- Reads every calendar on your Google account, not just one (needs a one-time Reconnect Google). Holiday, sports, birthday and moon-phase calendars are ignored for trips (#17).
- Flights and hotel stays are recognized: Gmail flight and hotel events, flight numbers, airport pairs like JFK → SFO, hotel words and chains; the hotel's city comes from its address. Restaurant and ticket reservations are ignored.
- Settings > Home: your city and home airports. A flight from home starts a trip and a flight home ends it; hotels away from home join it. The weather follows your home city.
### Changed
- Docs name Binoy Shah as author; the app's copyright is Binoy Shah.

## [1.6.0] - 2026-11-26
### Added
- Training tab (#15): the plan as a month calendar (runs, strength days, done runs from Strava, trips; click a day for the session, target and your run), training metrics (this week, plan runs done, predicted and best half, longest recent run), and a weekly miles chart of run vs planned.
- The 20-week plan now ships with the app, so the plan shows even with no calendar connected. Calendar events still win, since they carry moved runs.

## [1.5.0] - 2026-11-26
### Added
- Trips from your calendar (#12): events starting with ✈️ or 🧳, events with trip, travel, vacation or flight in the title, and flights and hotel stays Gmail adds to Google Calendar. Shown in a Trips card, on This week, on Next workout and on the Next run widget (home weather is hidden while you're away). "run: treadmill" or "run: none" in the event notes sets how running works on the trip. Read through Google Calendar or the Mac's Calendar, about three months ahead.

## [1.4.0] - 2026-11-26
### Changed
- Watch-data features (recovery rings, readiness and HRV hints, steps, the Recovery tab's "your watch shows" note) appear only when athletedata is connected (#11). With Strava only, the Today card and widget show today's run and your last run, the setup card lists athletedata as optional, and there's no "Watch data isn't set up" note.

## [1.3.0] - 2026-11-26
### Added
- Direct Google Calendar link (#9): Settings > Google Calendar signs in with your own Google Desktop client (PKCE, read-only scope) and reads the 🏃/🏁 run events straight from Google. The widgets now refresh the plan too. The Mac's Calendar stays as the fallback. Setup guide: docs/GOOGLE_CALENDAR.md.

## [1.2.0] - 2026-11-26
### Changed
- athletedata connects with your server URL and API key again (Settings > Save and test). The 1.1.0 OAuth sign-in was reverted because athletedata does issue API keys (#5).

## [1.1.0] - 2026-11-26
### Fixed
- athletedata connected with an OAuth sign-in instead of an API key (#3). Reverted in 1.2.0.

## [1.0.0] - 2026-11-26
### Added
- Mac app with Overview tab: recovery rings, next run with weather and kit, half prediction, this week, recent runs.
- Live data from Strava (own API app, read only), athletedata, Open-Meteo and calendar run events; refresh on open, every 15 minutes and with ⌘R.
- Menu bar view and Settings with keychain storage for credentials.
- Desktop widgets: Today rings, Next run, Half goal; self-refresh when data is over 25 minutes old.
- Recovery tab: check-ins, phase-based plans, cited exercise library (33 exercises, 9 body parts, 20 PubMed sources), NHS inform photos and videos, warning-symptom routing, weekly PubMed check.
- Unit tests, CI build and test on macOS, content QA for citations and links.
