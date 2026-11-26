import Foundation

/// Pure helpers for the Training tab (tested).
enum TrainingMath {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = AppConfig.timeZone
        c.firstWeekday = 2
        return c
    }

    /// The Monday of a day's week, as a day key.
    static func monday(of day: String) -> String {
        guard let d = Fmt.date(day) else { return day }
        let c = calendar
        let wd = c.component(.weekday, from: d)          // 1 = Sunday
        let back = (wd + 5) % 7                           // Monday -> 0, Sunday -> 6
        return Fmt.key(c.date(byAdding: .day, value: -back, to: d) ?? d)
    }

    static func add(_ day: String, _ n: Int) -> String {
        guard let d = Fmt.date(day) else { return day }
        return Fmt.key(calendar.date(byAdding: .day, value: n, to: d) ?? d)
    }

    /// A month as rows of 7 cells, Monday first; nil cells pad the first and last weeks.
    static func monthGrid(year: Int, month: Int) -> [[String?]] {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = 1
        let c = calendar
        guard let first = c.date(from: comps), let range = c.range(of: .day, in: .month, for: first) else { return [] }
        let lead = (c.component(.weekday, from: first) + 5) % 7
        var cells: [String?] = Array(repeating: nil, count: lead)
        for d in range { cells.append(Fmt.key(c.date(byAdding: .day, value: d - 1, to: first)!)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    struct WeekMiles: Identifiable, Equatable {
        let monday: String
        let actual: Double
        let planned: Double
        var id: String { monday }
    }

    /// Miles run (Strava) and planned per Monday-to-Sunday week, for `count` weeks starting at `firstMonday`.
    static func weeklyMiles(runs: [Run], plan: [PlannedRun], firstMonday: String, count: Int) -> [WeekMiles] {
        (0..<count).map { i in
            let s = add(firstMonday, i * 7), e = add(s, 6)
            let a = runs.filter { $0.date >= s && $0.date <= e }.reduce(0) { $0 + $1.miles }
            let p = plan.filter { $0.date >= s && $0.date <= e }.reduce(0) { $0 + ($1.miles ?? 0) }
            return WeekMiles(monday: s, actual: (a * 10).rounded() / 10, planned: (p * 10).rounded() / 10)
        }
    }

    /// Whole Monday-to-Sunday weeks from the Monday of `a` to the Monday of `b`.
    static func weeksBetween(_ a: String, _ b: String) -> Int {
        guard let x = Fmt.date(monday(of: a)), let y = Fmt.date(monday(of: b)) else { return 0 }
        return max(0, Int((y.timeIntervalSince(x) / 86400 / 7).rounded()))
    }

    /// Planned runs before today, and how many of them have a Strava run on the same day.
    static func adherence(plan: [PlannedRun], runs: [Run], today: String) -> (done: Int, due: Int) {
        let ran = Set(runs.map(\.date))
        let due = plan.filter { $0.date < today }
        return (due.filter { ran.contains($0.date) }.count, due.count)
    }
}

extension Derived {
    /// Runs for the whole plan, from the calendar's run events.
    var fullPlan: [PlannedRun] { snap.plan.sorted { $0.date < $1.date } }

    /// The first planned run, used as the start of the plan.
    var planStart: String? { fullPlan.first?.date }

    func plannedRuns(on day: String, in plan: [PlannedRun]) -> [PlannedRun] { plan.filter { $0.date == day } }
    func runs(on day: String) -> [Run] { snap.runs.filter { $0.date == day } }

    var daysToRace: Int? { profile.daysToRace(from: todayKey) }

    /// Longest run in the last 28 days.
    var longestRecent: Run? {
        let from = TrainingMath.add(todayKey, -28)
        return snap.runs.filter { $0.date >= from }.max { $0.distanceM < $1.distanceM }
    }
}
