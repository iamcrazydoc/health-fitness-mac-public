import Foundation

struct Run: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let date: String          // yyyy-MM-dd, local
    let distanceM: Double
    let movingS: Double
    let avgHR: Double?
    let outdoor: Bool

    var miles: Double { distanceM / 1609.344 }
    var paceSecPerMile: Double { miles > 0 ? movingS / miles : 0 }
}

struct RecoveryDay: Codable, Hashable {
    let date: String
    var readiness: Double?
    var verdict: String?
    var sleepH: Double?
    var sleepNeedH: Double?
    var hrv: Double?
    var hrvBase: Double?
    var restingHR: Double?
    var steps: Double?
}

struct PlannedRun: Codable, Identifiable, Hashable {
    let id: String
    let date: String
    let title: String
    let notes: String
    let miles: Double?

    var kind: Kind {
        let t = title.lowercased()
        if title.hasPrefix("🏁") || t.contains("race") { return .race }
        if t.contains("time trial") { return .race }
        if t.contains("long") { return .long }
        if t.contains("easy") { return .easy }
        return .workout
    }

    enum Kind: String { case easy, workout, long, race }

    /// Title without the emoji and distance suffix, e.g. "Long run".
    var shortTitle: String {
        var t = title
        for p in ["🏃 ", "🏁 ", "🏃", "🏁"] where t.hasPrefix(p) { t.removeFirst(p.count) }
        if let r = t.range(of: " · ") { t = String(t[..<r.lowerBound]) }
        return t.trimmingCharacters(in: .whitespaces)
    }
}

struct DayWeather: Codable, Hashable {
    let date: String
    let maxF: Double?
    let minF: Double?
    let feelsMinF: Double?
    let precipProb: Double?
    let windMph: Double?
    let code: Int?
}

struct HourWeather: Codable, Hashable {
    let time: String   // yyyy-MM-ddTHH:mm local
    let tempF: Double?
    let feelsF: Double?
    let precipProb: Double?
    let windMph: Double?
    let code: Int?
}

struct Snapshot: Codable {
    var updated: Date?
    var runs: [Run] = []
    var halfBest: Run?
    var predictedHalfS: Double?
    var predictedFrom: Run?
    var recovery: [RecoveryDay] = []
    var plan: [PlannedRun] = []
    var planUpdated: Date?
    var days: [DayWeather] = []
    var hours: [HourWeather] = []
    var problems: [String] = []
    /// athletedata was set up at the last refresh. Watch-data features show only when true.
    /// nil in snapshots saved before 1.4.0; then any saved watch data counts.
    var watchConnected: Bool?
    /// Trips from the calendar (1.5.0+).
    var trips: [Trip]?
    /// Set by 1.6.x when the built-in plan was shown. The plan is no longer built in; kept so old snapshots load.
    var planBuiltIn: Bool?
}

extension JSONDecoder {
    static var hf: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

extension JSONEncoder {
    static var hf: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}

/// The cached snapshot lives in the App Group so the widgets can read it.
enum Store {
    static var url: URL {
        let fm = FileManager.default
        let base: URL
        if !AppConfig.appGroup.isEmpty, let g = fm.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup) {
            base = g
        } else {
            base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HealthFitness")
        }
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("snapshot.json")
    }

    static func load() -> Snapshot {
        guard let d = try? Data(contentsOf: url), let s = try? JSONDecoder.hf.decode(Snapshot.self, from: d) else { return Snapshot() }
        return s
    }

    static func save(_ s: Snapshot) {
        if let d = try? JSONEncoder.hf.encode(s) { try? d.write(to: url, options: .atomic) }
    }
}
