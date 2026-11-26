import Foundation

/// One calendar event, from Google or the Mac's Calendar. `endDate` is the last day it covers (inclusive).
struct CalEvent: Equatable {
    var date: String
    var endDate: String
    var title: String
    var notes: String = ""
    var location: String = ""
    var fromGmail: Bool = false
    /// From a holiday, sports, birthday, moon-phase or other subscribed calendar: never a trip.
    var travelIgnored: Bool = false
}

/// What the app reads from a calendar: the training plan and any trips.
struct CalendarRead: Equatable {
    var plan: [PlannedRun]
    var trips: [Trip]
    /// Something the reader should know, e.g. that Google needs a reconnect.
    var note: String? = nil

    init(events: [CalEvent]) {
        plan = PlanParser.runs(from: events)
        trips = TripParser.trips(from: events, home: .current)
    }

    init(events: [CalEvent], home: HomeSettings) {
        plan = PlanParser.runs(from: events)
        trips = TripParser.trips(from: events, home: home)
    }

    init(plan: [PlannedRun], trips: [Trip]) {
        self.plan = plan
        self.trips = trips
    }
}

/// Turns calendar events into planned runs. Only events whose titles start with 🏃 (run) or 🏁 (race) count.
enum PlanParser {
    static func isPlanTitle(_ title: String) -> Bool { title.hasPrefix("🏃") || title.hasPrefix("🏁") }

    /// "🏃 Long run · 8 mi" -> 8
    static func miles(in title: String) -> Double? {
        guard let r = title.range(of: #"([0-9]+(\.[0-9]+)?) mi"#, options: .regularExpression) else { return nil }
        return Double(title[r].replacingOccurrences(of: " mi", with: ""))
    }

    /// Drops the dashboard link and footer lines, and simple HTML that Google adds to descriptions.
    static func clean(_ notes: String) -> String {
        var s = notes
        for br in ["<br>", "<br/>", "<br />", "</p>", "</div>"] { s = s.replacingOccurrences(of: br, with: "\n", options: .caseInsensitive) }
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        return s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("Dashboard:") && !$0.hasPrefix("Added by Claude") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One planned run per (day, title), sorted by day. Non-plan titles are skipped.
    static func runs(from events: [CalEvent]) -> [PlannedRun] {
        var seen = Set<String>()
        var out: [PlannedRun] = []
        for e in events where isPlanTitle(e.title) {
            let id = e.date + "|" + e.title
            guard seen.insert(id).inserted else { continue }
            out.append(PlannedRun(id: id, date: e.date, title: e.title, notes: clean(e.notes), miles: miles(in: e.title)))
        }
        return out.sorted { ($0.date, $0.title) < ($1.date, $1.title) }
    }
}

/// Where the plan and trips come from: Google Calendar when it's connected, otherwise the Mac's Calendar.
enum PlanSource {
    /// `google` is nil when Google isn't connected. `local` is nil when the Mac's Calendar wasn't read (widgets).
    static func pick(google: Result<CalendarRead, Error>?, local: CalendarRead?) -> (read: CalendarRead?, problem: String?) {
        switch google {
        case .success(let r)?: return (r, nil)
        case .failure(let e)?: return (local, "Google Calendar: \(e.localizedDescription)")
        case nil: return (local, nil)
        }
    }
}

/// The days read from the calendar: a week back (to mark runs done) and about three months ahead (for trips).
enum PlanWindow {
    static func range(now: Date = Date()) -> (Date, Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = AppConfig.timeZone
        let today = cal.startOfDay(for: now)
        return (cal.date(byAdding: .day, value: -7, to: today)!, cal.date(byAdding: .day, value: 91, to: today)!)
    }
}
