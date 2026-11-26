import Foundation

/// Read-only Strava access with your own Strava API app (client ID and secret kept in the keychain).
enum Strava {
    static var hasApp: Bool { Keychain.get(.stravaClientID) != nil && Keychain.get(.stravaClientSecret) != nil }
    static var isConnected: Bool { Keychain.get(.stravaRefresh) != nil }

    static func authorizeURL() -> URL? {
        guard let id = Keychain.get(.stravaClientID) else { return nil }
        var c = URLComponents(string: "https://www.strava.com/oauth/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "redirect_uri", value: AppConfig.oauthRedirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "read,activity:read_all"),
        ]
        return c.url
    }

    static func exchange(code: String) async throws {
        try await token(["grant_type": "authorization_code", "code": code])
    }

    static func disconnect() {
        Keychain.set(nil, for: .stravaAccess)
        Keychain.set(nil, for: .stravaRefresh)
        Keychain.set(nil, for: .stravaExpires)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_at: Int
    }

    private static func token(_ extra: [String: String]) async throws {
        guard let id = Keychain.get(.stravaClientID), let secret = Keychain.get(.stravaClientSecret) else {
            throw HFError.notConfigured("Strava")
        }
        var params = extra
        params["client_id"] = id
        params["client_secret"] = secret
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
        var req = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw HFError.http("Strava sign-in", code) }
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        Keychain.set(t.access_token, for: .stravaAccess)
        Keychain.set(t.refresh_token, for: .stravaRefresh)
        Keychain.set(String(t.expires_at), for: .stravaExpires)
    }

    private static func accessToken() async throws -> String {
        guard let refresh = Keychain.get(.stravaRefresh) else { throw HFError.notConnected("Strava") }
        let exp = Int(Keychain.get(.stravaExpires) ?? "0") ?? 0
        if let a = Keychain.get(.stravaAccess), exp > Int(Date().timeIntervalSince1970) + 120 { return a }
        try await token(["grant_type": "refresh_token", "refresh_token": refresh])
        guard let a = Keychain.get(.stravaAccess) else { throw HFError.notConnected("Strava") }
        return a
    }

    struct Activity: Decodable {
        let id: Int
        let name: String
        let sport_type: String?
        let type: String?
        let distance: Double
        let moving_time: Double
        let start_date_local: String
        let average_heartrate: Double?
        let trainer: Bool?
        let manual: Bool?
        let start_latlng: [Double]?
    }

    /// All activities after a date (up to 500).
    static func activities(after: Date) async throws -> [Activity] {
        let tok = try await accessToken()
        var all: [Activity] = []
        for page in 1...5 {
            var c = URLComponents(string: "https://www.strava.com/api/v3/athlete/activities")!
            c.queryItems = [
                URLQueryItem(name: "after", value: String(Int(after.timeIntervalSince1970))),
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page)),
            ]
            var req = URLRequest(url: c.url!)
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw HFError.http("Strava", code) }
            let batch = try JSONDecoder().decode([Activity].self, from: data)
            all += batch
            if batch.count < 100 { break }
        }
        return all
    }

    /// Clean runs only: running sports, at least a mile, a believable pace, not typed in by hand.
    static func runs(from acts: [Activity]) -> [Run] {
        acts.compactMap { a in
            let sport = a.sport_type ?? a.type ?? ""
            guard ["Run", "TrailRun", "VirtualRun"].contains(sport), !(a.manual ?? false), a.distance >= 1609, a.moving_time > 0 else { return nil }
            let secPerKm = a.moving_time / (a.distance / 1000)
            guard secPerKm >= 210, secPerKm <= 720 else { return nil }
            let outdoor = !(a.trainer ?? false) && sport != "VirtualRun" && (a.start_latlng?.count ?? 0) == 2
            return Run(id: a.id, name: a.name, date: String(a.start_date_local.prefix(10)), distanceM: a.distance,
                       movingS: a.moving_time, avgHR: a.average_heartrate, outdoor: outdoor)
        }
        .sorted { $0.date > $1.date }
    }
}
