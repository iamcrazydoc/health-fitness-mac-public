import Foundation

/// A trip worked out from the calendar. Runs on these days are shown as "away".
struct Trip: Codable, Identifiable, Hashable {
    enum Mode: String, Codable { case outdoor, treadmill, none }

    let id: String
    let start: String
    let end: String
    let place: String
    let mode: Mode
    /// What it was found from, e.g. ["flight", "hotel"]. Optional so older snapshots still decode.
    var basis: [String]? = nil

    func covers(_ day: String) -> Bool { day >= start && day <= end }

    var modeText: String {
        switch mode {
        case .outdoor: return "running outside"
        case .treadmill: return "treadmill only"
        case .none: return "no running"
        }
    }
}

/// One travel-related calendar event, classified. The dashboard's cal_trips loader uses the same rules.
struct TravelItem: Equatable {
    enum Kind: String { case flight, hotel }

    let kind: Kind
    let start: String
    let end: String
    /// Flights: departure and arrival as airport codes or city names, when the event says.
    var from: String = ""
    var to: String = ""
    /// Hotels: the city or name.
    var place: String = ""
    var mode: Trip.Mode? = nil
    var title: String = ""
}

/// Finds flights and hotel stays in calendar events, then joins them into trips using home.
/// Only flights and hotel bookings make a trip; online meetings never do.
enum TripParser {
    static let hotelWords = ["hotel", "inn", "resort", "suites", "lodge", "motel", "hostel", "airbnb", "vrbo", "marriott", "hilton",
                             "hyatt", "sheraton", "westin", "hampton", "courtyard", "doubletree", "embassy suites", "residence inn",
                             "four seasons", "ritz-carlton", "best western", "radisson", "wyndham", "ihg", "kimpton", "hotel reservation"]
    /// Words that, next to a flight number in a Gmail event, show it really is a flight.
    static let flightWords = ["flight", "airline", "airlines", "airways", "boarding", "departure", "depart", "arrival", "gate"]
    /// Online meeting links and words: an event with any of these is never a trip.
    static let meetingHosts = ["zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com",
                               "gotomeeting.com", "goto.com", "whereby.com", "bluejeans.com", "chime.aws", "ringcentral.com",
                               "skype.com", "facetime.apple.com", "meet.jit.si"]
    static let meetingWords = ["zoom", "meeting", "meetings", "webinar", "google meet", "microsoft teams", "teams meeting", "webex", "conference call",
                               "video call", "call", "standup", "stand-up", "huddle", "1:1", "one-on-one", "seminar", "grand rounds",
                               "journal club", "lecture", "office hours"]
    static let notHotel = ["restaurant", "table for", "dinner", "lunch", "brunch", "opentable", "resy", "ticket", "concert", "game",
                           "car rental", "rental car", "hertz", "avis", "enterprise", "budget", "uber", "lyft", "train", "amtrak", "bus"]

    // MARK: Classify one event

    static func classify(_ e: CalEvent) -> TravelItem? {
        if e.travelIgnored || PlanParser.isPlanTitle(e.title) || isMeeting(e) { return nil }
        let title = e.title
        let low = (title + " " + e.notes).lowercased()
        if isFlight(e) {
            let (from, to) = flightEnds(e)
            return TravelItem(kind: .flight, start: e.date, end: e.date, from: from, to: to, mode: mode(in: e.notes), title: title)
        }
        if isHotel(e, low: low) {
            let place = city(fromAddress: e.location) ?? hotelName(title) ?? "Hotel"
            // A hotel event that is only the check-in or check-out day still counts as that day.
            return TravelItem(kind: .hotel, start: e.date, end: max(e.date, e.endDate), place: place, mode: mode(in: e.notes), title: title)
        }
        return nil   // anything else (trips you name, restaurants, tickets, car rentals) isn't a booking we count
    }

    /// An online meeting: a video link anywhere in the event, or a meeting word in the title.
    static func isMeeting(_ e: CalEvent) -> Bool {
        let all = (e.title + " " + e.location + " " + e.notes).lowercased()
        if meetingHosts.contains(where: { all.contains($0) }) { return true }
        return hasWord(e.title.lowercased(), meetingWords, whole: true)
    }

    /// `whole`: the word must end there too ("inn", not "inner"); otherwise it only has to start a word ("travelling").
    static func hasWord(_ text: String, _ words: [String], whole: Bool = false) -> Bool {
        words.contains { w in
            text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: w))" + (whole ? "\\b" : ""), options: .regularExpression) != nil
        }
    }

    /// "UA 512", "B6 1123", "DL123": a two-character airline code and a number.
    static let flightNumber = #"\b([A-Z][A-Z0-9]|[A-Z0-9][A-Z])\s?\d{1,4}\b"#
    /// "JFK → SFO", "JFK-SFO", "JFK to SFO".
    static let airportPair = #"\b([A-Z]{3})\s*(?:→|->|–|—|-|to)\s*([A-Z]{3})\b"#

    static func isFlight(_ e: CalEvent) -> Bool {
        let t = e.title
        if hasWord(t.lowercased(), ["flight"]) { return true }
        if t.range(of: airportPair, options: .regularExpression) != nil { return true }
        // Gmail flight events carry the flight number; insist the event also talks about flying.
        if e.fromGmail, t.range(of: flightNumber, options: .regularExpression) != nil,
           !hasWord(t.lowercased(), hotelWords, whole: true),
           hasWord((t + " " + e.notes).lowercased(), flightWords, whole: true) { return true }
        return false
    }

    static func isHotel(_ e: CalEvent, low: String) -> Bool {
        if e.title.hasPrefix("🏨") { return true }
        let titleLow = e.title.lowercased()
        if hasWord(titleLow, notHotel, whole: true) { return false }
        if hasWord(titleLow, hotelWords, whole: true) { return true }
        // Gmail stays often say only the property name; the notes mention the hotel or the check-in.
        return e.fromGmail && hasWord(low, hotelWords, whole: true) && !hasWord(low, notHotel, whole: true)
    }

    /// Departure and arrival from "JFK → SFO", or "Flight to Denver", or "Flight from New York to Denver".
    static func flightEnds(_ e: CalEvent) -> (String, String) {
        for text in [e.title, e.location, e.notes] {
            if let r = text.range(of: airportPair, options: .regularExpression) {
                let s = String(text[r])
                let codes = s.matches(of: #/[A-Z]{3}/#).map { String($0.output) }
                if codes.count >= 2 { return (codes[0], codes[codes.count - 1]) }
            }
        }
        var to = "", from = ""
        let t = e.title.replacingOccurrences(of: #"\(.*?\)"#, with: "", options: .regularExpression)
        if let m = t.firstMatch(of: #/(?i)\bto\s+(.+)$/#) { to = String(m.1).trimmingCharacters(in: .whitespaces) }
        if let m = t.firstMatch(of: #/(?i)\bfrom\s+(.+?)(?:\s+to\b|$)/#) { from = String(m.1).trimmingCharacters(in: .whitespaces) }
        if from.isEmpty { from = e.location.trimmingCharacters(in: .whitespaces) }
        to = to.replacingOccurrences(of: flightNumber, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return (from, to)
    }

    /// "123 Main St, Denver, CO 80202, USA" -> "Denver"; "Chicago" -> "Chicago".
    static func city(fromAddress address: String) -> String? {
        let countries: Set<String> = ["usa", "us", "united states", "united states of america", "canada", "uk", "united kingdom", "india"]
        var parts = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        while let last = parts.last, countries.contains(last.lowercased()) { parts.removeLast() }
        guard !parts.isEmpty else { return nil }
        if parts.count == 1 { return parts[0].first?.isNumber == true ? nil : parts[0] }
        // The last part is usually "CO 80202" or a state; the city sits just before it.
        let last = parts[parts.count - 1]
        let isState = last.range(of: #"^[A-Z]{2}(\s+\d{5}(-\d{4})?)?$"#, options: .regularExpression) != nil
            || last.range(of: #"\d{4,}"#, options: .regularExpression) != nil
        let c = isState ? parts[parts.count - 2] : last
        return c.first?.isNumber == true ? nil : c
    }

    static func hotelName(_ title: String) -> String? {
        var t = title.replacingOccurrences(of: #"^[^\p{L}\p{N}]+"#, with: "", options: .regularExpression)
        for p in ["stay at ", "hotel reservation at ", "reservation at ", "check-in: ", "check in at "] where t.lowercased().hasPrefix(p) {
            t = String(t.dropFirst(p.count))
        }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    static func mode(in notes: String) -> Trip.Mode? {
        let n = notes.lowercased()
        guard let m = n.firstMatch(of: #/run(?:ning)?\s*:\s*(none|no|treadmill|outdoor|outside)\b/#) else { return nil }
        switch m.1 {
        case "none", "no": return Trip.Mode.none
        case "treadmill": return .treadmill
        default: return .outdoor
        }
    }

    // MARK: Join into trips

    static func trips(from events: [CalEvent], home: HomeSettings = .current) -> [Trip] {
        build(events.compactMap(classify), home: home)
    }

    /// Flights from home open a trip and flights back home close it; hotels away from home
    /// join the trip they touch or make their own. Anything at home is ignored.
    static func build(_ items: [TravelItem], home: HomeSettings) -> [Trip] {
        struct Draft { var start: String; var end: String; var place: String; var mode: Trip.Mode?; var basis: [String] }
        var drafts: [Draft] = []
        var open: Draft?
        let sorted = items.sorted { ($0.start, $0.kind == .flight ? 0 : 1) < ($1.start, $1.kind == .flight ? 0 : 1) }

        for f in sorted where f.kind == .flight {
            let toHome = home.isHome(f.to), fromHome = home.isHome(f.from)
            if toHome && fromHome { continue }
            if var o = open {
                if toHome {                              // flying back: the trip ends that day
                    o.end = max(o.end, f.start); o.basis.append("flight")
                    drafts.append(o); open = nil
                } else if fromHome {                     // a new outbound before a return we saw: close the old one
                    drafts.append(o)
                    open = Draft(start: f.start, end: f.start, place: f.to, mode: f.mode, basis: ["flight"])
                } else {                                 // a leg between away places
                    o.end = max(o.end, f.start)
                    if o.place.isEmpty { o.place = f.to }
                    o.basis.append("flight"); open = o
                }
            } else if !toHome {
                open = Draft(start: f.start, end: f.start, place: f.to, mode: f.mode, basis: ["flight"])
            } else {                                     // a flight home with no outbound in view: away until that day
                drafts.append(Draft(start: f.start, end: f.start, place: f.from, mode: f.mode, basis: ["flight"]))
            }
        }
        if let o = open { drafts.append(o) }

        for h in sorted where h.kind != .flight {
            if home.isHome(h.place) { continue }
            let kind = h.kind.rawValue
            if let i = drafts.firstIndex(where: { h.start <= TrainingMath.add($0.end, 1) && h.end >= TrainingMath.add($0.start, -1) }) {
                drafts[i].start = min(drafts[i].start, h.start)
                drafts[i].end = max(drafts[i].end, h.end)
                if drafts[i].place.isEmpty || drafts[i].place.count == 3 && h.kind == .hotel { drafts[i].place = h.place }
                if drafts[i].mode == nil { drafts[i].mode = h.mode }
                drafts[i].basis.append(kind)
            } else {
                drafts.append(Draft(start: h.start, end: h.end, place: h.place, mode: h.mode, basis: [kind]))
            }
        }

        // Join trips that overlap after the hotels stretched them.
        drafts.sort { $0.start < $1.start }
        var merged: [Draft] = []
        for d in drafts {
            if var last = merged.last, d.start <= last.end {
                last.end = max(last.end, d.end)
                if last.mode == nil { last.mode = d.mode }
                last.basis += d.basis
                merged[merged.count - 1] = last
            } else {
                merged.append(d)
            }
        }
        return merged.map { d in
            let place = d.place.isEmpty ? "Away" : d.place
            var seen = Set<String>()
            let basis = d.basis.filter { seen.insert($0).inserted }
            return Trip(id: d.start + "|" + place, start: d.start, end: d.end, place: place, mode: d.mode ?? .outdoor, basis: basis)
        }
    }
}
