import XCTest

final class LibraryTests: XCTestCase {
    func testLibraryLoadsAndEveryCitationExists() {
        let lib = RecoveryLibrary.shared
        XCTAssertGreaterThan(lib.parts.count, 5, "library didn't load")
        let known = Set(lib.refs.map(\.pmid))
        for p in lib.parts {
            XCTAssertFalse(p.exercises.isEmpty, p.id)
            for r in p.run_refs { XCTAssertTrue(known.contains(r), "\(p.id) run ref \(r)") }
            for e in p.exercises {
                XCTAssertFalse(e.refs.isEmpty, "\(e.id) has no source")
                for r in e.refs { XCTAssertTrue(known.contains(r), "\(e.id) ref \(r)") }
                XCTAssertNotNil(e.mediaURL, e.id)
                XCTAssertTrue(["calm", "build", "return"].contains(e.phase), e.id)
            }
        }
        for r in lib.refs { XCTAssertFalse(r.doi.isEmpty, r.pmid) }
    }
}

@MainActor
final class RecoveryPlanTests: XCTestCase {
    private func model(_ entries: [BodyEntry]) -> RecoveryModel {
        let m = RecoveryModel()
        m.entries = entries
        return m
    }

    func testPhases() {
        let today = Fmt.key(Date())
        XCTAssertEqual(model([BodyEntry(date: today, part: "calf", feel: "Tight", severity: 2)]).plans.first?.phase, .build)
        XCTAssertEqual(model([BodyEntry(date: today, part: "calf", feel: "Pain", severity: 3)]).plans.first?.phase, .calm)
        XCTAssertEqual(model([BodyEntry(date: today, part: "calf", feel: "Better", severity: 1)]).plans.first?.phase, .return)
        XCTAssertEqual(model([BodyEntry(date: today, part: "shin", feel: "Sore", severity: 2, symptoms: ["Pain in one spot on the bone"])]).plans.first?.phase, .seeDoctor)
        XCTAssertTrue(model([BodyEntry(date: today, part: "knee_front", feel: "Recovered", severity: 1)]).plans.isEmpty)
    }

    func testOldMildIssueDropsOff() {
        let old = Fmt.key(Calendar.current.date(byAdding: .day, value: -20, to: Date())!)
        XCTAssertTrue(model([BodyEntry(date: old, part: "hip", feel: "Tight", severity: 2)]).plans.isEmpty)
        XCTAssertFalse(model([BodyEntry(date: old, part: "hip", feel: "Pain", severity: 4)]).plans.isEmpty)
    }
}

final class AnalysisTests: XCTestCase {
    func testRiegelPrediction() {
        let d = Fmt.key(Date())
        // 10 km in 60:00 → Riegel 1.06 half ≈ 2:12:4x
        let r = Run(id: 1, name: "t", date: d, distanceM: 10000, movingS: 3600, avgHR: nil, outdoor: true)
        let p = Predictor.predict([r])
        XCTAssertNotNil(p)
        XCTAssertEqual(p!.0, 3600 * pow(21097.5 / 10000, 1.06), accuracy: 1)
    }

    func testFormatting() {
        XCTAssertEqual(Fmt.hms(7200), "2:00:00")
        XCTAssertEqual(Fmt.pace(551), "9:11 /mi")
    }
}

final class PubMedParsingTests: XCTestCase {
    func testParseSearch() throws {
        let json = #"{"header":{},"esearchresult":{"count":"2","idlist":["40000001","40000002"]}}"#
        XCTAssertEqual(try PubMed.parseSearch(Data(json.utf8)), ["40000001", "40000002"])
    }

    func testParseSearchRejectsGarbage() {
        XCTAssertThrowsError(try PubMed.parseSearch(Data("{}".utf8)))
    }

    func testParseSummary() throws {
        let json = #"""
        {"result":{"uids":["40000001","40000002"],
          "40000001":{"uid":"40000001","title":"A trial of calf loading.","source":"Br J Sports Med","pubdate":"2026 Nov",
            "authors":[{"name":"Smith A"},{"name":"Jones B"}],
            "articleids":[{"idtype":"pubmed","value":"40000001"},{"idtype":"doi","value":"10.1136/x.1"}],
            "pubtype":["Journal Article","Randomized Controlled Trial"]},
          "40000002":{"uid":"40000002","error":"cannot get document summary"}}}
        """#
        let papers = try PubMed.parseSummary(Data(json.utf8), ids: ["40000001", "40000002"])
        XCTAssertEqual(papers.count, 1, "entries without a title are skipped")
        let p = papers[0]
        XCTAssertEqual(p.title, "A trial of calf loading.")
        XCTAssertEqual(p.authors, "Smith A et al.")
        XCTAssertEqual(p.doi, "10.1136/x.1")
        XCTAssertEqual(p.journal, "Br J Sports Med")
        XCTAssertTrue(p.types.contains("Randomized Controlled Trial"))
        XCTAssertEqual(p.url.absoluteString, "https://pubmed.ncbi.nlm.nih.gov/40000001/")
    }
}

final class GoogleCalendarTests: XCTestCase {
    func testPKCEChallengeIsS256Base64URL() {
        // SHA-256 of the RFC 7636 example verifier, base64url without padding.
        let p = GoogleCalendar.PKCE(verifier: "dBjftJeZ4CVP-mJ92K9qcTFl_4sDN2Lir3SDE8pB7eM")
        XCTAssertEqual(p.challenge, "S1uA3qxA1RnfthgFwYIVdjmtk3kRCxN3JVdLxvXVaa0")
        let fresh = GoogleCalendar.PKCE()
        XCTAssertGreaterThanOrEqual(fresh.verifier.count, 43)
        XCTAssertNil(fresh.verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        XCTAssertNotEqual(fresh.verifier, GoogleCalendar.PKCE().verifier)
    }

    func testAuthorizeURL() throws {
        let url = try XCTUnwrap(GoogleCalendar.authorizeURL(clientID: "abc.apps.googleusercontent.com",
                                                            redirect: "http://127.0.0.1:50123", state: "s1", challenge: "ch"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ n: String) -> String? { items.first(where: { $0.name == n })?.value }
        XCTAssertEqual(url.host, "accounts.google.com")
        XCTAssertEqual(v("client_id"), "abc.apps.googleusercontent.com")
        XCTAssertEqual(v("redirect_uri"), "http://127.0.0.1:50123")
        XCTAssertEqual(v("scope"), "https://www.googleapis.com/auth/calendar.events.readonly https://www.googleapis.com/auth/calendar.calendarlist.readonly")
        XCTAssertEqual(v("code_challenge_method"), "S256")
        XCTAssertEqual(v("code_challenge"), "ch")
        XCTAssertEqual(v("access_type"), "offline")
        XCTAssertEqual(v("state"), "s1")
        XCTAssertEqual(v("response_type"), "code")
    }

    func testParseCallback() {
        XCTAssertEqual(GoogleCalendar.parseCallback(request: "GET /?state=s1&code=4/0Ab-c&scope=x HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"),
                       .code("4/0Ab-c", state: "s1"))
        XCTAssertEqual(GoogleCalendar.parseCallback(request: "GET /?error=access_denied&state=s1 HTTP/1.1\r\n"), .error("access_denied"))
        XCTAssertNil(GoogleCalendar.parseCallback(request: "GET /favicon.ico HTTP/1.1\r\n"))
        XCTAssertNil(GoogleCalendar.parseCallback(request: "GET / HTTP/1.1\r\n"))
        XCTAssertNil(GoogleCalendar.parseCallback(request: "POST /?code=x&state=y HTTP/1.1\r\n"))
        XCTAssertNil(GoogleCalendar.parseCallback(request: ""))
    }

    func testParseToken() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let first = try GoogleCalendar.parseToken(Data(#"{"access_token":"a1","expires_in":3599,"refresh_token":"r1","token_type":"Bearer"}"#.utf8), now: now)
        XCTAssertEqual(first, .init(access: "a1", refresh: "r1", expiresAt: 1_003_599))
        let refreshed = try GoogleCalendar.parseToken(Data(#"{"access_token":"a2","expires_in":3599}"#.utf8), now: now)
        XCTAssertNil(refreshed.refresh, "Google leaves out the refresh token on refresh; the stored one is kept")
        XCTAssertThrowsError(try GoogleCalendar.parseToken(Data(#"{"error":"invalid_grant"}"#.utf8)))
    }

    func testEventsBecomePlan() throws {
        let json = #"""
        {"items":[
          {"status":"confirmed","summary":"🏃 Long run · 8 mi","description":"Easy pace<br>Dashboard: https://x","start":{"date":"2026-12-06"}},
          {"status":"confirmed","summary":"🏃 Tempo · 4 mi","start":{"dateTime":"2026-12-08T07:00:00-05:00"}},
          {"status":"confirmed","summary":"🏃 Late run · 3 mi","start":{"dateTime":"2026-12-09T03:30:00Z"}},
          {"status":"cancelled","summary":"🏃 Old run · 5 mi","start":{"date":"2026-12-07"}},
          {"status":"confirmed","summary":"Dentist","start":{"date":"2026-12-07"}},
          {"status":"confirmed","summary":"🏁 New Year 5K","start":{"date":"2027-01-01"}},
          {"status":"confirmed","summary":"🏃 Long run · 8 mi","start":{"date":"2026-12-06"}}
        ],"nextPageToken":"p2"}
        """#
        let page = try GoogleCalendar.parseEvents(Data(json.utf8))
        XCTAssertEqual(page.next, "p2")
        let plan = PlanParser.runs(from: page.events)
        // A timed event lands on the Mac's local day, whatever the time zone.
        let lateDay = Fmt.key(try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-12-09T03:30:00Z")))
        XCTAssertEqual(plan.map(\.date), ["2026-12-06", "2026-12-08", lateDay, "2027-01-01"].sorted())
        XCTAssertEqual(plan[0].miles, 8)
        XCTAssertEqual(plan[0].notes, "Easy pace", "HTML and the dashboard link are removed")
        XCTAssertEqual(plan.first { $0.shortTitle == "Late run" }?.date, lateDay, "a UTC time is shown on the local day")
        XCTAssertEqual(plan.first { $0.shortTitle == "Tempo" }?.miles, 4)
        XCTAssertEqual(plan[3].kind, .race)
        XCTAssertThrowsError(try GoogleCalendar.parseEvents(Data("nope".utf8)))
    }

    func testPlanSourcePick() {
        let g = CalendarRead(plan: [PlannedRun(id: "g", date: "2026-12-06", title: "🏃 Long run · 8 mi", notes: "", miles: 8)], trips: [])
        let l = CalendarRead(plan: [PlannedRun(id: "l", date: "2026-12-06", title: "🏃 Long run · 7 mi", notes: "", miles: 7)], trips: [])
        XCTAssertEqual(PlanSource.pick(google: .success(g), local: l).read, g)
        let failed = PlanSource.pick(google: .failure(HFError.http("Google Calendar", 500)), local: l)
        XCTAssertEqual(failed.read, l)
        XCTAssertNotNil(failed.problem)
        XCTAssertEqual(PlanSource.pick(google: nil, local: l).read, l)
        XCTAssertNil(PlanSource.pick(google: nil, local: nil).read, "widgets keep the last plan when Google isn't connected")
    }
}

final class WatchDataGatingTests: XCTestCase {
    private func snap(watch: Bool?) -> Snapshot {
        var s = Snapshot()
        s.recovery = [RecoveryDay(date: Fmt.key(Date()), readiness: 30, verdict: "rest", sleepH: 5, sleepNeedH: 8,
                                  hrv: 40, hrvBase: 60, restingHR: 55, steps: 8000)]
        s.watchConnected = watch
        return s
    }

    func testWatchFeaturesShowWithAthletedata() {
        let d = Derived(snap: snap(watch: true))
        XCTAssertTrue(d.hasWatchData)
        XCTAssertEqual(d.rings.count, 4)
        XCTAssertNotNil(d.latestRecovery)
    }

    func testWatchFeaturesHiddenWithStravaOnly() {
        let d = Derived(snap: snap(watch: false))
        XCTAssertFalse(d.hasWatchData)
        XCTAssertTrue(d.rings.isEmpty)
        XCTAssertNil(d.latestRecovery)
        XCTAssertNil(d.yesterdaySteps)
        XCTAssertNil(RecoveryModel.generalAdviceText(d), "no 'your watch shows' note without athletedata")
    }

    func testOlderSnapshotsFallBackToSavedData() throws {
        XCTAssertTrue(Derived(snap: snap(watch: nil)).hasWatchData)
        var empty = Snapshot()
        empty.watchConnected = nil
        XCTAssertFalse(Derived(snap: empty).hasWatchData)
        // A snapshot saved before 1.4.0 has no watchConnected key and still decodes.
        let old = try JSONEncoder.hf.encode(Snapshot())
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        obj.removeValue(forKey: "watchConnected")
        let back = try JSONDecoder.hf.decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(back.watchConnected)
    }
}

final class TripTests: XCTestCase {
    private let home = HomeSettings(city: "Columbus, OH", airports: ["CMH", "LCK"], latitude: 39.96, longitude: -83.0)

    private func ev(_ title: String, _ start: String, _ end: String? = nil, notes: String = "", location: String = "",
                    gmail: Bool = false, ignored: Bool = false) -> CalEvent {
        CalEvent(date: start, endDate: end ?? start, title: title, notes: notes, location: location, fromGmail: gmail, travelIgnored: ignored)
    }

    func testFlightsOutAndBackMakeOneTripAndHotelNamesThePlace() {
        let trips = TripParser.trips(from: [
            ev("Flight to San Francisco (UA 1234)", "2027-01-14", location: "Columbus CMH", gmail: true),
            ev("Hilton San Francisco Union Square", "2027-01-14", "2027-01-16", notes: "Your hotel reservation. Check-in 3 PM",
               location: "333 O'Farrell St, San Francisco, CA 94102, USA", gmail: true),
            ev("Flight to Columbus (UA 567)", "2027-01-17", location: "San Francisco SFO", gmail: true),
        ], home: home)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].start, "2027-01-14")
        XCTAssertEqual(trips[0].end, "2027-01-17", "away until the flight home")
        XCTAssertEqual(trips[0].place, "San Francisco")
        XCTAssertEqual(trips[0].basis, ["flight", "hotel"])
        XCTAssertEqual(trips[0].mode, .outdoor)
    }

    func testAirportPairsAndHomeAirports() {
        let trips = TripParser.trips(from: [
            ev("✈️ CMH → DEN", "2027-02-03"),
            ev("✈️ DEN → CMH", "2027-02-06"),
            ev("LCK-CMH shuttle flight", "2027-02-10"),
        ], home: home)
        XCTAssertEqual(trips.map(\.start), ["2027-02-03"], "a flight between two home airports isn't a trip")
        XCTAssertEqual(trips.first?.end, "2027-02-06")
        XCTAssertEqual(trips.first?.place, "DEN")
    }

    func testHotelAloneAndHotelAtHome() {
        let trips = TripParser.trips(from: [
            ev("🏨 Stay at The Inn at Stowe", "2027-03-05", "2027-03-07", notes: "run: treadmill", location: "Stowe, VT"),
            ev("Hampton Inn Columbus", "2027-03-20", "2027-03-21", location: "501 N High St, Columbus, OH 43215", gmail: true),
        ], home: home)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].place, "Stowe")
        XCTAssertEqual(trips[0].end, "2027-03-07")
        XCTAssertEqual(trips[0].mode, .treadmill)
    }

    func testThingsThatAreNotTrips() {
        let trips = TripParser.trips(from: [
            ev("Dinner at Bistro du Midi", "2027-01-09", notes: "Reservation for 2 via OpenTable", gmail: true),
            ev("Celtics at Heat", "2027-01-10", ignored: true),
            ev("Strip mall opening", "2027-01-11"),
            ev("Innovation day", "2027-01-12"),
            ev("Business review", "2027-01-13"),
            ev("🏃 Long run · 8 mi", "2027-01-17", notes: "trip"),
            ev("Flight to somewhere", "2027-01-20", ignored: true),
        ], home: home)
        XCTAssertTrue(trips.isEmpty, "\(trips)")
    }

    func testTripWordsStillWork() throws {
        let trips = TripParser.trips(from: [
            ev("Family vacation", "2027-02-20", "2027-02-28", notes: "Running: none", location: "Goa, India"),
            ev("✈️ Trip to Denver", "2027-01-14", "2027-01-17"),
        ], home: home)
        XCTAssertEqual(trips.map(\.place), ["Denver", "Goa"])
        XCTAssertEqual(trips[1].mode, Trip.Mode.none)
    }

    func testGoogleParsingKeepsGmailAndExclusiveEnd() throws {
        let json = #"""
        {"items":[
          {"summary":"Stay at Hilton","eventType":"fromGmail","location":"Chicago, IL","start":{"date":"2027-03-05"},"end":{"date":"2027-03-08"}},
          {"summary":"Flight to Chicago (UA 512)","eventType":"fromGmail","start":{"dateTime":"2027-03-05T07:10:00-05:00"},"end":{"dateTime":"2027-03-05T09:05:00-06:00"}}
        ]}
        """#
        let events = try GoogleCalendar.parseEvents(Data(json.utf8)).events
        let trips = TripParser.trips(from: events, home: home)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].start, "2027-03-05")
        XCTAssertEqual(trips[0].end, "2027-03-07", "Google's all-day end date is exclusive")
        XCTAssertEqual(trips[0].place, "Chicago")
    }

    func testHelpers() {
        XCTAssertEqual(TripParser.city(fromAddress: "123 Main St, Denver, CO 80202, USA"), "Denver")
        XCTAssertEqual(TripParser.city(fromAddress: "Chicago"), "Chicago")
        XCTAssertEqual(TripParser.city(fromAddress: "Shibuya, Tokyo"), "Tokyo")
        XCTAssertNil(TripParser.city(fromAddress: ""))
        XCTAssertTrue(home.isHome("Columbus CMH"))
        XCTAssertTrue(home.isHome("Columbus Regional Airport"))
        XCTAssertFalse(home.isHome("San Francisco SFO"))
        XCTAssertEqual(HomeSettings.parseAirports("cmh, lck ,day x"), ["CMH", "LCK", "DAY"])
        XCTAssertEqual(TripParser.mode(in: "RUN: NO"), Trip.Mode.none)
        XCTAssertNil(TripParser.mode(in: ""))
        XCTAssertTrue(GoogleCalendar.ignoresTravel(id: "en.usa#holiday@group.v.calendar.google.com", summary: "Holidays in United States"))
        XCTAssertTrue(GoogleCalendar.ignoresTravel(id: "x@group.calendar.google.com", summary: "Phases of the Moon"))
        XCTAssertFalse(GoogleCalendar.ignoresTravel(id: "family123@group.calendar.google.com", summary: "Family"))
    }

    func testDerivedTripHelpers() {
        var s = Snapshot()
        let today = Fmt.key(Date())
        let past = Fmt.key(Date(timeIntervalSinceNow: -20 * 86400))
        s.trips = [Trip(id: "a", start: past, end: past, place: "Old", mode: .outdoor),
                   Trip(id: "b", start: today, end: today, place: "Now", mode: .none)]
        let d = Derived(snap: s)
        XCTAssertEqual(d.upcomingTrips.map(\.place), ["Now"])
        XCTAssertEqual(d.trip(on: today)?.place, "Now")
        XCTAssertNil(Derived(snap: Snapshot()).trip(on: today), "snapshots without trips still work")
    }

    func testCalendarListParsing() throws {
        let json = #"{"items":[{"id":"me@gmail.com","summary":"Me","primary":true},{"id":"en.usa#holiday@group.v.calendar.google.com","summary":"Holidays in United States"}]}"#
        let cals = try GoogleCalendar.parseCalendars(Data(json.utf8))
        XCTAssertEqual(cals.map(\.id), ["me@gmail.com", "en.usa#holiday@group.v.calendar.google.com"])
        XCTAssertEqual(cals.map(\.ignoreTravel), [false, true])
    }
}

final class TrainingTests: XCTestCase {
    func testProfileParsing() {
        XCTAssertEqual(Profile.parseTime("1:59:59"), 7199)
        XCTAssertEqual(Profile.parseTime("2:05"), 7500)
        XCTAssertEqual(Profile.parseTime("125"), 7500)
        XCTAssertNil(Profile.parseTime(""))
        XCTAssertNil(Profile.parseTime("fast"))
        XCTAssertNil(Profile.parseTime("1:-5:00"))
        XCTAssertEqual(Profile.parseDate("2027-05-02"), "2027-05-02")
        XCTAssertNil(Profile.parseDate("May 2"))
        XCTAssertNil(Profile.empty.dashboardURL)
        XCTAssertNil(Profile(dashboardLink: "http://example.com").dashboardURL, "https only")
        XCTAssertEqual(Profile.empty.raceTitle, "Race day")
    }

    func testGoalNeedsAProfile() {
        var s = Snapshot()
        s.predictedHalfS = 7500
        let none = Derived(snap: s, profile: .empty)
        XCTAssertNil(none.goal)
        XCTAssertNil(none.gapToGoal, "no goal is built in")
        XCTAssertNil(none.daysToRace)
        let set = Derived(snap: s, profile: Profile(goalHalfSeconds: 7200, raceDate: "2027-05-02"))
        XCTAssertEqual(set.gapToGoal, 300)
        XCTAssertEqual(set.profile.daysToRace(from: "2027-04-25"), 7)
    }

    func testHomeIsNotBuiltIn() {
        XCTAssertFalse(HomeSettings.unset.hasLocation)
        XCTAssertFalse(HomeSettings.unset.isHome("Anywhere, USA"))
    }

    func testPlanComesFromTheCalendar() {
        var s = Snapshot()
        XCTAssertTrue(Derived(snap: s, profile: .empty).fullPlan.isEmpty, "no plan is built in")
        s.plan = [PlannedRun(id: "b", date: "2026-12-06", title: "🏃 Long run · 3.7 mi", notes: "", miles: 3.7),
                  PlannedRun(id: "a", date: "2026-12-02", title: "🏃 Easy run · 2.5 mi", notes: "", miles: 2.5)]
        let d = Derived(snap: s, profile: .empty)
        XCTAssertEqual(d.fullPlan.map(\.date), ["2026-12-02", "2026-12-06"])
        XCTAssertEqual(d.planStart, "2026-12-02")
        XCTAssertEqual(TrainingMath.weeksBetween("2026-12-02", "2026-12-20"), 2)
    }

    func testMonthGridStartsMonday() {
        let dec = TrainingMath.monthGrid(year: 2026, month: 12)
        XCTAssertEqual(dec.first?[0], nil, "Dec 1 2026 is a Tuesday")
        XCTAssertEqual(dec.first?[1], "2026-12-01")
        XCTAssertTrue(dec.allSatisfy { $0.count == 7 })
        XCTAssertEqual(dec.flatMap { $0 }.compactMap { $0 }.count, 31)
        XCTAssertEqual(dec.last?.compactMap { $0 }.last, "2026-12-31")
        let feb = TrainingMath.monthGrid(year: 2027, month: 2)
        XCTAssertEqual(feb.first?[0], "2027-02-01", "Feb 1 2027 is a Monday")
        XCTAssertEqual(feb.count, 4)
    }

    func testWeeklyMilesAndAdherence() {
        XCTAssertEqual(TrainingMath.monday(of: "2026-12-06"), "2026-11-30")
        XCTAssertEqual(TrainingMath.monday(of: "2026-11-30"), "2026-11-30")
        let runs = [Run(id: 1, name: "a", date: "2026-12-02", distanceM: 4023.36, movingS: 1800, avgHR: nil, outdoor: true),
                    Run(id: 2, name: "b", date: "2026-12-09", distanceM: 8046.72, movingS: 3600, avgHR: nil, outdoor: true)]
        let plan = [PlannedRun(id: "1", date: "2026-12-02", title: "🏃 Easy run · 2.5 mi", notes: "", miles: 2.5),
                    PlannedRun(id: "2", date: "2026-12-06", title: "🏃 Long run · 3.7 mi", notes: "", miles: 3.7),
                    PlannedRun(id: "3", date: "2026-12-08", title: "🏃 Easy run · 3.1 mi", notes: "", miles: 3.1)]
        let w = TrainingMath.weeklyMiles(runs: runs, plan: plan, firstMonday: "2026-11-30", count: 2)
        XCTAssertEqual(w.map(\.monday), ["2026-11-30", "2026-12-07"])
        XCTAssertEqual(w[0].actual, 2.5)
        XCTAssertEqual(w[0].planned, 6.2)
        XCTAssertEqual(w[1].actual, 5.0)
        let a = TrainingMath.adherence(plan: plan, runs: runs, today: "2026-12-08")
        XCTAssertEqual(a.done, 1)
        XCTAssertEqual(a.due, 2)
    }
}

final class ClaudeTests: XCTestCase {
    private func derived() -> Derived {
        var s = Snapshot()
        let today = Fmt.key(Date())
        s.runs = [Run(id: 1, name: "Morning Run", date: TrainingMath.add(today, -2), distanceM: 8046.72, movingS: 3000, avgHR: 150, outdoor: true),
                  Run(id: 2, name: "Old Run", date: TrainingMath.add(today, -60), distanceM: 5000, movingS: 1800, avgHR: nil, outdoor: true)]
        s.plan = [PlannedRun(id: "p", date: TrainingMath.add(today, 3), title: "🏃 Long run · 6 mi", notes: "Easy\nconversational", miles: 6)]
        s.predictedHalfS = 7400
        return Derived(snap: s, profile: Profile(goalHalfSeconds: 7199, raceDate: TrainingMath.add(today, 30), raceName: "Spring Half"))
    }

    func testSummaryHasGoalRunsAndPlan() {
        let home = HomeSettings(city: "Columbus, OH", airports: ["CMH"], latitude: 39.96, longitude: -83.0)
        let s = ClaudeContext.summary(derived(), bodyNotes: ["2026-12-01: Calf, tight 2/5"], home: home)
        XCTAssertTrue(s.contains("Half marathon goal: 1:59:59"))
        XCTAssertTrue(s.contains("Spring Half on"))
        XCTAssertTrue(s.contains("(30 days away)"))
        XCTAssertTrue(s.contains("5.0 mi at 10:00 /mi, avg HR 150"))
        XCTAssertFalse(s.contains("Old Run"), "only the last 6 weeks")
        XCTAssertTrue(s.contains("🏃 Long run · 6 mi (Easy; conversational)"))
        XCTAssertTrue(s.contains("Home: Columbus, OH (airports CMH)"))
        XCTAssertTrue(s.contains("Calf, tight 2/5"))
        XCTAssertFalse(s.contains("Watch, last 7 days"), "no watch section without athletedata")
    }

    func testSummaryWithNothingSet() {
        let s = ClaudeContext.summary(Derived(snap: Snapshot(), profile: .empty), home: .unset)
        XCTAssertTrue(s.contains("- Not set yet"))
        XCTAssertTrue(s.contains("No planned runs"))
    }

    func testHandoffText() {
        let t = ClaudeContext.handoff(.plan, question: "  Can I run 3 days a week? ", summary: "DATA")
        XCTAssertTrue(t.hasPrefix(ClaudeAsk.plan.prompt))
        XCTAssertTrue(t.contains("My question: Can I run 3 days a week?"))
        XCTAssertTrue(t.hasSuffix("DATA"))
        XCTAssertEqual(ClaudeContext.handoff(nil, question: "", summary: "DATA"), "DATA")
        XCTAssertTrue(ClaudeAsk.dashboard.prompt.contains("🏃"))
    }

    func testChatRequestBody() throws {
        let body = ClaudeChat.body(context: "CTX", turns: [.user("Hi")])
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "medium")
        let system = try XCTUnwrap((body["system"] as? [[String: Any]])?.first)
        XCTAssertTrue((system["text"] as? String ?? "").contains("<runner_data>\nCTX\n</runner_data>"))
        let msgs = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.first?["role"] as? String, "user")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testChatResponseParsing() throws {
        let ok = #"{"content":[{"type":"thinking","thinking":"","signature":"s"},{"type":"text","text":"Run easy."}],"stop_reason":"end_turn"}"#
        let turn = try ClaudeChat.parse(Data(ok.utf8))
        XCTAssertEqual(turn.role, "assistant")
        XCTAssertEqual(turn.text, "Run easy.")
        XCTAssertEqual(turn.content.count, 2, "thinking blocks are kept to send back")
        let refused = #"{"content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","explanation":"no"}}"#
        XCTAssertThrowsError(try ClaudeChat.parse(Data(refused.utf8)))
        XCTAssertThrowsError(try ClaudeChat.parse(Data("nope".utf8)))
    }
}
