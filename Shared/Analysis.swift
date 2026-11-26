import Foundation

/// Numbers the app and widgets show, worked out from the cached snapshot.
struct Derived {
    let snap: Snapshot
    var profile: Profile = .current

    var todayKey: String { Fmt.key(Date()) }

    // MARK: Recovery (athletedata only)
    /// Watch-data features (rings, readiness hints, steps) show only when athletedata is connected.
    var hasWatchData: Bool { snap.watchConnected ?? !snap.recovery.isEmpty }

    var latestRecovery: RecoveryDay? {
        guard hasWatchData else { return nil }
        return snap.recovery.last(where: { $0.date == todayKey && ($0.readiness != nil || $0.sleepH != nil) })
            ?? snap.recovery.last(where: { $0.readiness != nil || $0.sleepH != nil })
    }

    var yesterdaySteps: (steps: Double, date: String)? {
        guard hasWatchData else { return nil }
        let y = Fmt.key(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        if let r = snap.recovery.first(where: { $0.date == y }), let s = r.steps { return (s, r.date) }
        if let r = snap.recovery.last(where: { $0.steps != nil && $0.date < todayKey }), let s = r.steps { return (s, r.date) }
        return nil
    }

    struct Ring: Identifiable {
        let id: String
        let label: String
        let value: String
        let sub: String
        let fraction: Double?
        let tone: Tone
    }

    enum Tone { case good, caution, low, none }

    /// Empty without athletedata, so views hide the rings.
    var rings: [Ring] {
        guard hasWatchData else { return [] }
        let r = latestRecovery
        let need = r?.sleepNeedH ?? 7.5
        func tone(_ f: Double?) -> Tone { guard let f else { return .none }; return f >= 0.85 ? .good : f >= 0.65 ? .caution : .low }
        let readiness = r?.readiness
        let rTone: Tone = readiness == nil ? .none : readiness! >= 70 ? .good : readiness! >= 45 ? .caution : .low
        let hrvF: Double? = (r?.hrv != nil && (r?.hrvBase ?? 0) > 0) ? r!.hrv! / r!.hrvBase! : nil
        let hTone: Tone = hrvF == nil ? .none : hrvF! >= 0.95 ? .good : hrvF! >= 0.88 ? .caution : .low
        let st = yesterdaySteps
        return [
            Ring(id: "ready", label: "Readiness", value: readiness.map { String(Int($0)) } ?? "—",
                 sub: (r?.verdict ?? "").replacingOccurrences(of: "_", with: " "), fraction: readiness.map { $0 / 100 }, tone: rTone),
            Ring(id: "sleep", label: "Sleep", value: r?.sleepH.map { String(format: "%.1fh", $0) } ?? "—",
                 sub: String(format: "need %.1fh", need), fraction: r?.sleepH.map { $0 / need }, tone: tone(r?.sleepH.map { $0 / need })),
            Ring(id: "hrv", label: "HRV", value: r?.hrv.map { String(Int($0)) } ?? "—",
                 sub: r?.hrvBase.map { "usual \(Int($0))" } ?? "", fraction: hrvF.map { min(1, $0 / 1.15) }, tone: hTone),
            Ring(id: "steps", label: "Steps", value: st.map { $0.steps >= 1000 ? String(format: "%.1fk", $0.steps / 1000) : String(Int($0.steps)) } ?? "—",
                 sub: "yesterday", fraction: st.map { $0.steps / 10000 }, tone: tone(st.map { $0.steps / 8000 })),
        ]
    }

    // MARK: Trips (from the calendar)
    func trip(on day: String) -> Trip? { (snap.trips ?? []).first { $0.covers(day) } }

    /// Trips that haven't ended yet, soonest first.
    var upcomingTrips: [Trip] { (snap.trips ?? []).filter { $0.end >= todayKey }.sorted { $0.start < $1.start } }

    // MARK: Plan
    var nextRun: PlannedRun? {
        let done = Set(snap.runs.map(\.date))
        return snap.plan.filter { $0.date > todayKey || ($0.date == todayKey && !done.contains(todayKey)) }.min { $0.date < $1.date }
    }

    func weather(for run: PlannedRun) -> (day: DayWeather?, hour: HourWeather?) {
        let day = snap.days.first { $0.date == run.date }
        let wd = Fmt.date(run.date).map { Calendar.current.component(.weekday, from: $0) } ?? 2
        let hh = (wd == 1 || wd == 7) ? "08:00" : "18:00"
        let hour = snap.hours.first { $0.time == "\(run.date)T\(hh)" }
        return (day, hour)
    }

    var weekStartKey: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = AppConfig.timeZone
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return Fmt.key(start)
    }

    var weekEndKey: String {
        let s = Fmt.date(weekStartKey) ?? Date()
        return Fmt.key(Calendar.current.date(byAdding: .day, value: 6, to: s) ?? s)
    }

    var weekMiles: Double { snap.runs.filter { $0.date >= weekStartKey && $0.date <= weekEndKey }.reduce(0) { $0 + $1.miles } }

    var weekPlanMiles: Double? {
        let p = snap.plan.filter { $0.date >= weekStartKey && $0.date <= weekEndKey }
        return p.isEmpty ? nil : p.reduce(0) { $0 + ($1.miles ?? 0) }
    }

    var weekPlan: [PlannedRun] { snap.plan.filter { $0.date >= weekStartKey && $0.date <= weekEndKey }.sorted { $0.date < $1.date } }

    // MARK: Half goal (set in Settings > Goal)
    var predicted: Double? { snap.predictedHalfS }
    var goal: Double? { profile.goalHalfSeconds }
    var gapToGoal: Double? { guard let g = goal else { return nil }; return predicted.map { $0 - g } }
    var bestHalf: Double? { snap.halfBest.map { $0.movingS * AppConfig.halfMeters / $0.distanceM } }

    /// 0 = where the best half was, 1 = the goal.
    var progressToGoal: Double? {
        guard let g = goal, let p = predicted, let b = bestHalf, b > g else { return nil }
        return max(0, min(1, (b - p) / (b - g)))
    }

    var daysSinceRun: Int? {
        guard let last = snap.runs.first?.date, let d = Fmt.date(last), let t = Fmt.date(todayKey) else { return nil }
        return Calendar.current.dateComponents([.day], from: d, to: t).day
    }
}

enum Predictor {
    /// Riegel (exponent 1.06) from outdoor runs of 3+ miles in the last 6 weeks; the best one counts.
    static func predict(_ runs: [Run]) -> (Double, Run)? {
        let cutoff = Fmt.key(Calendar.current.date(byAdding: .day, value: -42, to: Date())!)
        let pool = runs.filter { $0.outdoor && $0.distanceM >= 4828 && $0.date >= cutoff }
        return pool.map { ($0.movingS * pow(AppConfig.halfMeters / $0.distanceM, 1.06), $0) }.min { $0.0 < $1.0 }
    }

    static func bestHalf(_ runs: [Run], previous: Run?) -> Run? {
        let halves = runs.filter { $0.distanceM >= 20900 && $0.distanceM <= 21800 }
        let all = halves + (previous.map { [$0] } ?? [])
        return all.min { $0.movingS * AppConfig.halfMeters / $0.distanceM < $1.movingS * AppConfig.halfMeters / $1.distanceM }
    }
}
