import Foundation

/// The runner's own goal, race and dashboard link, set in Settings > Goal.
/// Nothing is built in: until these are set, the app shows hints instead of numbers.
struct Profile: Codable, Equatable {
    var goalHalfSeconds: Double?   // goal time for the half marathon
    var raceDate: String?          // yyyy-MM-dd
    var raceName: String?
    var dashboardLink: String?     // optional web dashboard opened from the toolbar

    static let empty = Profile()

    var raceTitle: String {
        let n = (raceName ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Race day" : n
    }

    var dashboardURL: URL? {
        guard let s = dashboardLink?.trimmingCharacters(in: .whitespaces), s.hasPrefix("https://") else { return nil }
        return URL(string: s)
    }

    /// Days from `today` to the race, or nil when no race date is set.
    func daysToRace(from today: String) -> Int? {
        guard let r = raceDate, let rd = Fmt.date(r), let t = Fmt.date(today) else { return nil }
        return Calendar.current.dateComponents([.day], from: t, to: rd).day
    }

    /// "1:59:59", "2:05" (h:mm) or "125" (minutes) -> seconds. Nil for anything else.
    static func parseTime(_ s: String) -> Double? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        let p = parts.map { $0! }
        let secs: Int
        switch p.count {
        case 1: secs = p[0] * 60
        case 2: secs = p[0] * 3600 + p[1] * 60
        case 3: secs = p[0] * 3600 + p[1] * 60 + p[2]
        default: return nil
        }
        return secs > 0 ? Double(secs) : nil
    }

    /// A yyyy-MM-dd date, or nil.
    static func parseDate(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count == 10, Fmt.date(t) != nil else { return nil }
        return t
    }

    // MARK: Saved next to the snapshot, so the widgets see it too.
    private static var url: URL { Store.url.deletingLastPathComponent().appendingPathComponent("profile.json") }

    static var current: Profile {
        guard let d = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(Profile.self, from: d) else { return .empty }
        return p
    }

    static func save(_ p: Profile) {
        if let d = try? JSONEncoder().encode(p) { try? d.write(to: url, options: .atomic) }
    }
}
