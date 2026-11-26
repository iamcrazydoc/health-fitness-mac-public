# Development process

Author: Binoy Shah

Every new feature and every update goes through the same loop. Nothing reaches `main` without
a passing build, passing tests and a QA review.

```
Plan ──► Stage ──► Develop ──► Test (CI) ──► Error correction ─┐
                                   ▲                           │
                                   └───────── repeat ◄─────────┘
                                   │ green
                                   ▼
                              QA review ──► fixes ──► CI green ──► Merge + release
```

## 1. Plan
Open an issue using **Feature** or **Bug** template. It must state:
- the goal in one sentence, and what is out of scope
- acceptance criteria (checkboxes, each testable)
- the test plan: which unit tests are added or changed, and what is checked by hand

## 2. Stage
Branch from the latest `main`:
- `feature/<issue>-<slug>` for features, `fix/<issue>-<slug>` for bugs, `chore/<slug>` for upkeep.

## 3. Develop
- Small, focused commits with Conventional Commit messages: `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`.
- Add or update unit tests in `Tests/` alongside the change.
- Keep `project.yml` as the source of truth for targets and settings.

## 4. Test (CI quality gates)
Open a **draft PR** early and fill in the template. Every push runs:

| Gate | What it checks |
|---|---|
| **Build and test** (macOS runner) | XcodeGen generates the project; the app and widget extension compile (unsigned); all XCTest unit tests pass |
| **Content QA** (Linux runner) | Recovery library: every exercise and running rule cites a source in the library, every source has a PMID and DOI, media links are https from trusted hosts, no duplicate IDs |

## 5. Error correction
Read the failing step's log (also uploaded as the `logs` artifact), fix the cause, push again.
Repeat until both gates are green. Tests are never skipped, disabled or loosened to get green.

## 6. QA review
A separate review pass against [`docs/QA_CHECKLIST.md`](docs/QA_CHECKLIST.md), posted as a PR
comment with each item marked pass, fail or n/a. Failures become fix commits, and CI must be green again.

## 7. Release
- Mark the PR ready and squash-merge into `main`.
- Add an entry to `CHANGELOG.md` (Keep a Changelog format) and bump `MARKETING_VERSION` in `project.yml`.
- Tag `vX.Y.Z` (semantic versioning: major for breaking changes, minor for features, patch for fixes).
- Install on the Mac: `git pull && ./setup.sh`, then run the manual smoke test from the QA checklist.
