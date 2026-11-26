import Foundation

enum AppConfig {
    /// App Group shared by the app and its widgets (set in Info.plist from the build settings).
    static let appGroup: String = {
        let v = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
        return v.contains("$(") ? "" : v
    }()
    /// Keychain group shared by the app and its widgets.
    static let keychainGroup: String? = {
        let v = Bundle.main.object(forInfoDictionaryKey: "KeychainGroup") as? String ?? ""
        return (v.isEmpty || v.contains("$(")) ? nil : v
    }()
    static let googleGuideURL = URL(string: "https://github.com/iamcrazydoc/health-fitness-mac-public/blob/main/docs/GOOGLE_CALENDAR.md")!
    static let stravaSettingsURL = URL(string: "https://www.strava.com/settings/api")!
    /// Dates and weeks follow the Mac's time zone.
    static var timeZone: TimeZone { .current }
    static let halfMeters: Double = 21097.5
    static let oauthRedirect = "healthfitness://localhost/strava"
    /// Data older than this is refreshed when a widget asks for a timeline.
    static let widgetMaxAge: TimeInterval = 25 * 60
}

enum HFError: LocalizedError {
    case notConfigured(String)
    case notConnected(String)
    case http(String, Int)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let what): return "\(what) isn't set up yet. Open Settings."
        case .notConnected(let what): return "\(what) isn't connected. Open Settings."
        case .http(let what, let code): return "\(what) answered with error \(code)."
        case .parse(let what): return "Couldn't read the \(what) data."
        }
    }
}

enum Fmt {
    static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppConfig.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ d: Date) -> String { dayKey.string(from: d) }
    static func date(_ key: String) -> Date? { dayKey.date(from: String(key.prefix(10))) }

    static func hms(_ s: Double) -> String {
        let t = Int(s.rounded())
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func pace(_ secPerMile: Double) -> String {
        let t = Int(secPerMile.rounded())
        return String(format: "%d:%02d /mi", t / 60, t % 60)
    }

    static func miles(_ m: Double) -> String { String(format: m >= 10 ? "%.0f" : "%.1f", m) }

    static func shortDay(_ key: String) -> String {
        guard let d = date(key) else { return key }
        let f = DateFormatter()
        f.timeZone = AppConfig.timeZone
        f.dateFormat = "EEE MMM d"
        return f.string(from: d)
    }

    static func relativeDay(_ key: String) -> String {
        let today = Fmt.key(Date())
        if key == today { return "Today" }
        if let t = Calendar.current.date(byAdding: .day, value: 1, to: Date()), key == Fmt.key(t) { return "Tomorrow" }
        return shortDay(key)
    }
}
