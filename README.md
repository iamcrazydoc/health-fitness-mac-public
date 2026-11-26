# Health and Fitness for Mac

Author: Binoy Shah

A small Mac app, menu bar item and desktop widgets for half marathon training. It pulls live data
every time you open it, every 15 minutes while it runs, and when you press ⌘R. Widgets refresh
themselves when their data is more than 25 minutes old, even with the app closed.

## Where the data comes from

| What | Source | Live? |
|---|---|---|
| Runs, best half, predicted time | Strava API (your own API app) | Yes |
| Readiness, sleep, HRV, steps | athletedata (Garmin) with your API key | Yes |
| Weather and kit | Open-Meteo, for the home you set in Settings | Yes |
| Plan (next run, this week) | The 🏃/🏁 events in Google Calendar ([setup](docs/GOOGLE_CALENDAR.md)) or the Mac's Calendar | Yes (with Google, the widgets too; with the Mac's Calendar, the app only) |

If you keep a web dashboard, add its link in Settings > Goal; ⇧⌘D opens it.

## Training tab

Your plan as a month calendar: each day shows the planned run (color by type), the miles you
actually ran (from Strava), trips and races. Click a day for the session, its target pace and your
run. Above it: this week's miles, plan runs done, predicted and best half, your longest recent run,
and a weekly miles chart (run vs planned). The plan comes from the 🏃/🏁 events in your calendar;
nothing is built into the app.

## Goal

Set your half marathon goal time, race date and race name in Settings > Goal. They drive the goal
card, the Half goal widget and the race countdown. Until they're set, the app shows hints instead.

## Recovery tab

- **Check in** (top right): body part, how it feels (Tight, Sore, Pain, Injury, Better, Recovered),
  severity 1–5, symptoms and a note. Saved on your Mac.
- **Plan**: each active or watched body part gets a phase (Get it checked, Calm it down, Build
  strength, Return), a running rule, and exercises with dose and steps. Warning symptoms such as
  pain at night, bone tenderness, numbness or swelling switch the plan to "Get it checked".
- **Photos & video**: opens the NHS inform exercise page for that exercise inside the app.
- **Sources**: every exercise and running rule cites the PubMed paper behind it (PubMed and DOI links).
- **Weekly research check**: once a week the app searches PubMed for new systematic reviews,
  meta-analyses, trials and guidelines for each body part and lists them with links.
  "Check now" runs it on demand. New papers are shown for reading; the exercise library only
  changes when it's reviewed and updated.

Not medical advice. See a physio or doctor for severe, worsening or lingering pain.

> **No athletedata?** The app works with Strava alone (for example Garmin → Strava). See
> [docs/STRAVA_ONLY.md](docs/STRAVA_ONLY.md) for what works and how to set it up.

## Install

1. Install Xcode from the App Store and open it once.
2. Xcode > Settings > Accounts: add your Apple ID (a free one works).
3. In Terminal: `cd` to this folder, then `./setup.sh`.

The app lands in `~/Applications/Health and Fitness.app` and opens.

## Connect your accounts (in the app, ⌘,)

- **Strava**: at strava.com/settings/api make an app with Authorization Callback Domain
  `localhost`. Paste its Client ID and Client Secret, click Save, then Connect. Approve in the
  browser and it comes back to the app.
- **athletedata**: paste your athletedata MCP URL and API key from your athletedata account,
  then click Save and test.
- **Google Calendar** (recommended): follow [docs/GOOGLE_CALENDAR.md](docs/GOOGLE_CALENDAR.md), then click Connect Google in Settings.
- **Calendar**: or click Allow so the app reads the run events from the Mac's Calendar app.

### Trips and home
Set your home city and airports in Settings > Home. The app then finds trips in all your
calendars: flights (Gmail flight events, flight numbers, JFK → SFO), hotel stays (Gmail
reservations and hotel names, city from the address), and events you title with ✈️, 🧳, trip,
travel or vacation. A flight from home starts a trip and a flight home ends it. Add `run: treadmill`
or `run: none` to an event's notes if you can't run outside. The weather follows your home city.

## Widgets

Right-click the desktop > Edit Widgets > search "Health and Fitness":
Today (rings), Next run (with weather), Half goal (prediction vs your goal).

## Rebuilding

Run `./setup.sh` again after any change. `project.yml` is the XcodeGen spec; the generated
`.xcodeproj` and `build/` can be deleted at any time.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for how changes are planned, built, tested and reviewed.

## License

[MIT](LICENSE) © 2026 Binoy Shah
