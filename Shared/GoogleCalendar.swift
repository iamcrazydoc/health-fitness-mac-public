import CryptoKit
import Foundation

/// Read-only Google Calendar access with the user's own Google "Desktop app" OAuth client.
/// Sign-in uses PKCE and a loopback redirect (http://127.0.0.1:<port>). Client ID, secret and tokens
/// live only in the shared keychain. See docs/GOOGLE_CALENDAR.md.
enum GoogleCalendar {
    /// Read-only: events, plus the list of calendars so every calendar can be read (1.7.0).
    static let scope = "https://www.googleapis.com/auth/calendar.events.readonly https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    static var hasClient: Bool { Keychain.get(.googleClientID) != nil && Keychain.get(.googleClientSecret) != nil }
    static var isConnected: Bool { Keychain.get(.googleRefresh) != nil }
    static var calendarID: String { Keychain.get(.googleCalendarID) ?? "primary" }

    // MARK: PKCE (RFC 7636, S256)

    struct PKCE {
        let verifier: String
        var challenge: String { GoogleCalendar.challenge(for: verifier) }

        init(verifier: String? = nil) {
            if let verifier { self.verifier = verifier; return }
            var bytes = [UInt8](repeating: 0, count: 32)
            var rng = SystemRandomNumberGenerator()
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255, using: &rng) }
            self.verifier = GoogleCalendar.base64url(Data(bytes))
        }
    }

    static func challenge(for verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: Sign-in

    static func authorizeURL(clientID: String, redirect: String, state: String, challenge: String) -> URL? {
        var c = URLComponents(string: authEndpoint)!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return c.url
    }

    enum Callback: Equatable {
        case code(String, state: String)
        case error(String)
    }

    /// Reads the browser's request to the loopback listener, e.g. "GET /?code=…&state=… HTTP/1.1".
    /// Returns nil for anything that isn't the sign-in callback (like /favicon.ico).
    static func parseCallback(request: String) -> Callback? {
        guard let line = request.split(whereSeparator: \.isNewline).first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let c = URLComponents(string: "http://127.0.0.1" + parts[1]), c.path == "/" || c.path.isEmpty else { return nil }
        let items = c.queryItems ?? []
        func v(_ n: String) -> String? { items.first(where: { $0.name == n })?.value }
        if let e = v("error") { return .error(e) }
        if let code = v("code"), let state = v("state") { return .code(code, state: state) }
        return nil
    }

    struct Token: Equatable {
        let access: String
        let refresh: String?
        let expiresAt: Int
    }

    static func parseToken(_ data: Data, now: Date = Date()) throws -> Token {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = o["access_token"] as? String else { throw HFError.parse("Google sign-in") }
        let expiresIn = (o["expires_in"] as? NSNumber)?.intValue ?? 3600
        return Token(access: access, refresh: o["refresh_token"] as? String, expiresAt: Int(now.timeIntervalSince1970) + expiresIn)
    }

    static func exchange(code: String, verifier: String, redirect: String) async throws {
        try await token(["grant_type": "authorization_code", "code": code, "code_verifier": verifier, "redirect_uri": redirect])
        guard isConnected else { throw HFError.parse("Google sign-in (no refresh token)") }
    }

    /// Forgets the tokens here and asks Google to revoke them (best effort).
    static func disconnect() {
        let tok = Keychain.get(.googleRefresh) ?? Keychain.get(.googleAccess)
        clearTokens()
        guard let tok else { return }
        var req = URLRequest(url: revokeEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form(["token": tok]).data(using: .utf8)
        URLSession.shared.dataTask(with: req).resume()
    }

    private static func clearTokens() {
        Keychain.set(nil, for: .googleAccess)
        Keychain.set(nil, for: .googleRefresh)
        Keychain.set(nil, for: .googleExpires)
    }

    private static func form(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
    }

    private static func token(_ extra: [String: String]) async throws {
        guard let id = Keychain.get(.googleClientID), let secret = Keychain.get(.googleClientSecret) else {
            throw HFError.notConfigured("Google Calendar")
        }
        var params = extra
        params["client_id"] = id
        params["client_secret"] = secret
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form(params).data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            // A revoked or expired refresh token: forget it so Settings shows "Connect" again.
            if extra["grant_type"] == "refresh_token", code == 400 || code == 401,
               String(decoding: data, as: UTF8.self).contains("invalid_grant") {
                clearTokens()
                throw HFError.notConnected("Google Calendar")
            }
            throw HFError.http("Google sign-in", code)
        }
        let t = try parseToken(data)
        Keychain.set(t.access, for: .googleAccess)
        if let r = t.refresh { Keychain.set(r, for: .googleRefresh) }
        Keychain.set(String(t.expiresAt), for: .googleExpires)
    }

    private static func accessToken() async throws -> String {
        guard let refresh = Keychain.get(.googleRefresh) else { throw HFError.notConnected("Google Calendar") }
        let exp = Int(Keychain.get(.googleExpires) ?? "0") ?? 0
        if let a = Keychain.get(.googleAccess), exp > Int(Date().timeIntervalSince1970) + 120 { return a }
        try await token(["grant_type": "refresh_token", "refresh_token": refresh])
        guard let a = Keychain.get(.googleAccess) else { throw HFError.notConnected("Google Calendar") }
        return a
    }

    // MARK: Reading the plan

    /// The 🏃/🏁 run events and trips in the read window, from every calendar on the account.
    static func upcoming(now: Date = Date(), home: HomeSettings = .current) async throws -> CalendarRead {
        let tok = try await accessToken()
        let listed = try await calendars(token: tok)
        let cals: [GCal] = listed ?? [GCal(id: calendarID, summary: "", ignoreTravel: false)]
        let found = try await withThrowingTaskGroup(of: [CalEvent].self) { group in
            for c in cals { group.addTask { try await Self.events(in: c, token: tok, now: now) } }
            var all: [CalEvent] = []
            for try await e in group { all += e }
            return all
        }
        var read = CalendarRead(events: found, home: home)
        if listed == nil { read.note = "Reconnect Google in Settings so the app can read all your calendars (only one is read now)." }
        return read
    }

    struct GCal: Equatable {
        let id: String
        let summary: String
        let ignoreTravel: Bool
    }

    /// Calendars that never hold trips: holidays, sports, birthdays, moon phases, week numbers.
    static func ignoresTravel(id: String, summary: String) -> Bool {
        let i = id.lowercased(), s = summary.lowercased()
        if ["#holiday@", "#sports@", "#contacts@", "#weeknum@", "#weather@"].contains(where: { i.contains($0) }) { return true }
        if i.hasSuffix("group.v.calendar.google.com") { return true }
        return ["phases of the moon", "birthdays", "holidays in"].contains { s.hasPrefix($0) }
    }

    /// `calendarList.list`; nil when the sign-in predates the calendar-list permission.
    static func calendars(token: String) async throws -> [GCal]? {
        var c = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        c.queryItems = [URLQueryItem(name: "maxResults", value: "250"), URLQueryItem(name: "minAccessRole", value: "reader")]
        var req = URLRequest(url: c.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 403 || code == 401 { return nil }
        guard code == 200 else { throw HFError.http("Google Calendar list", code) }
        return try parseCalendars(data)
    }

    static func parseCalendars(_ data: Data) throws -> [GCal] {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HFError.parse("Google Calendar list") }
        return (o["items"] as? [[String: Any]] ?? []).compactMap { it in
            guard let id = it["id"] as? String else { return nil }
            let summary = it["summaryOverride"] as? String ?? it["summary"] as? String ?? ""
            return GCal(id: id, summary: summary, ignoreTravel: ignoresTravel(id: id, summary: summary))
        }
    }

    private static func events(in cal: GCal, token: String, now: Date) async throws -> [CalEvent] {
        let (start, end) = PlanWindow.range(now: now)
        let iso = ISO8601DateFormatter()
        var path = CharacterSet.urlPathAllowed
        path.remove(charactersIn: "/#?@+")
        let id = cal.id.addingPercentEncoding(withAllowedCharacters: path) ?? "primary"
        var events: [CalEvent] = []
        var pageToken: String?
        for _ in 0..<5 {
            var c = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(id)/events")!
            var q = [
                URLQueryItem(name: "timeMin", value: iso.string(from: start)),
                URLQueryItem(name: "timeMax", value: iso.string(from: end)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "250"),
            ]
            if let pageToken { q.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            c.queryItems = q
            var req = URLRequest(url: c.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 || code == 403 { return [] }      // a calendar we can't read; the others still load
            guard code == 200 else { throw HFError.http("Google Calendar", code) }
            let page = try parseEvents(data, ignoreTravel: cal.ignoreTravel)
            events += page.events
            pageToken = page.next
            if pageToken == nil { break }
        }
        return events
    }

    /// One page of `events.list`: every event that isn't cancelled.
    static func parseEvents(_ data: Data, ignoreTravel: Bool = false) throws -> (events: [CalEvent], next: String?) {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HFError.parse("Google Calendar") }
        let items = o["items"] as? [[String: Any]] ?? []
        var out: [CalEvent] = []
        for it in items {
            if (it["status"] as? String) == "cancelled" { continue }
            guard let title = it["summary"] as? String, let start = it["start"] as? [String: Any],
                  let day = dayKey(start) else { continue }
            let end = (it["end"] as? [String: Any]).flatMap { lastDay($0) } ?? day
            out.append(CalEvent(date: day, endDate: max(day, end), title: title, notes: it["description"] as? String ?? "",
                                location: it["location"] as? String ?? "", fromGmail: (it["eventType"] as? String) == "fromGmail",
                                travelIgnored: ignoreTravel))
        }
        return (out, o["nextPageToken"] as? String)
    }

    /// The last day an event covers. An all-day "date" end is exclusive in Google, so it's the day before.
    static func lastDay(_ end: [String: Any]) -> String? {
        if let d = end["date"] as? String, let date = Fmt.date(d) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = AppConfig.timeZone
            return Fmt.key(cal.date(byAdding: .day, value: -1, to: date) ?? date)
        }
        return dayKey(end)
    }

    /// All-day events have "date" (already the day); timed ones have "dateTime" with an offset.
    static func dayKey(_ start: [String: Any]) -> String? {
        if let d = start["date"] as? String { return String(d.prefix(10)) }
        guard let dt = start["dateTime"] as? String else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: dt) { return Fmt.key(d) }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: dt) { return Fmt.key(d) }
        return String(dt.prefix(10))
    }
}
