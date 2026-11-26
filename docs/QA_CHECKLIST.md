# QA checklist

Author: Binoy Shah

Copy into the PR's QA comment and mark each item ✅ pass, ❌ fail or n/a.

## Build and tests
- [ ] CI "Build and test" green on the latest commit
- [ ] CI "Content QA" green on the latest commit
- [ ] New or changed logic has unit tests; no test skipped or weakened

## Correctness
- [ ] Acceptance criteria in the issue are all met
- [ ] Edge cases: no data yet, a source offline, empty calendar, first launch
- [ ] Each data source fails on its own and shows a clear message; the rest still loads
- [ ] Dates use the Mac's time zone; weeks start Monday; units are miles, min/mile, °F, mph

## Security and privacy
- [ ] No credentials, tokens or personal data in code, logs, commits or test fixtures (no built-in home, goal, race date or plan)
- [ ] Keys only read from and written to the keychain
- [ ] Strava use is read only
- [ ] Network calls only to: strava.com, api.open-meteo.com, athletedata, eutils.ncbi.nlm.nih.gov, Google sign-in and Calendar (accounts.google.com, oauth2.googleapis.com, www.googleapis.com), place search (geocoding-api.open-meteo.com), trusted media hosts
- [ ] Google Calendar use is read only (calendar.events.readonly and calendar.calendarlist.readonly scopes)

## Health content
- [ ] Every exercise and running rule cites a real source (PMID and DOI resolve)
- [ ] The claim in the app matches what the cited paper found (no overstating)
- [ ] Warning symptoms route to "Get it checked"; the disclaimer is visible
- [ ] Photos and videos come from the trusted source page, not copied into the app

## UI
- [ ] Light and dark mode readable
- [ ] Widgets render in every supported size, including with no data
- [ ] Text fits at the minimum window size

## Manual smoke test on the Mac (after merge)
- [ ] `./setup.sh` builds and installs
- [ ] App opens, ⌘R refreshes, Settings saves and tests connections
- [ ] Widgets appear in Edit Widgets and update
- [ ] Recovery: add a check-in → plan appears; "Photos & video" opens; "Check now" lists papers
