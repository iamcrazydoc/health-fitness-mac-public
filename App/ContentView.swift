import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let d = model.derived
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if needsSetup { setupCard }
                TodayCard(d: d)
                HStack(alignment: .top, spacing: 18) {
                    NextWorkoutCard(d: d)
                    GoalCard(d: d)
                }
                WeekCard(d: d)
                if !d.upcomingTrips.isEmpty { TripsCard(d: d) }
                RecentRunsCard(d: d)
                if !model.snap.problems.isEmpty { problemsCard }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await model.refresh() } } label: {
                    if model.refreshing { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                .help("Refresh now (⌘R)")
                if let url = model.derived.profile.dashboardURL {
                    Button { NSWorkspace.shared.open(url) } label: { Label("Dashboard", systemImage: "safari") }
                        .help("Open your web dashboard")
                }
                Button { openSettings() } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
    }

    private var needsSetup: Bool { !Strava.isConnected || !hasPlanSource }

    private var hasPlanSource: Bool { model.calendarAccess || GoogleCalendar.isConnected }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Health and Fitness").font(.system(size: 28, weight: .semibold, design: .rounded))
            Spacer()
            if let u = model.snap.updated {
                Text("Updated \(u.formatted(date: .omitted, time: .shortened))").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var setupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Finish setting up", systemImage: "wrench.and.screwdriver").font(.headline)
                if !Strava.isConnected { Text("• Connect Strava for runs, best half and the prediction.") }
                if !hasPlanSource { Text("• Connect Google Calendar, or allow Calendars access, so your planned runs show.") }
                Button("Open Settings") { openSettings() }.buttonStyle(.borderedProminent)
                if !Athletedata.isConfigured {
                    Text("Optional: add athletedata in Settings for readiness, sleep, HRV and steps from your watch.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let m = model.message { Text(m).font(.callout).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var problemsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.snap.problems, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

struct CardTitle: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.caption).fontWeight(.semibold).tracking(0.8).foregroundStyle(.secondary) }
}

struct TodayCard: View {
    let d: Derived
    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle(text: "Today")
                    Text(headline).font(.title2.weight(.semibold))
                    Text(detail).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if !d.rings.isEmpty {
                    HStack(spacing: 14) { ForEach(d.rings) { RingView(ring: $0, size: 70) } }
                }
            }
        }
    }

    private var todayRun: PlannedRun? { d.snap.plan.first { $0.date == d.todayKey } }
    private var ranToday: Bool { d.snap.runs.contains { $0.date == d.todayKey } }

    private var headline: String {
        if let r = todayRun { return ranToday ? "Done: \(r.shortTitle)" : r.shortTitle + (r.miles.map { " · \(Fmt.miles($0)) mi" } ?? "") }
        return "Rest day from running"
    }

    private var detail: String {
        let rec = d.latestRecovery
        var parts: [String] = []
        if let v = rec?.verdict { parts.append("Watch says \(v.replacingOccurrences(of: "_", with: " ").lowercased()).") }
        if let hrv = rec?.hrv, let base = rec?.hrvBase, base > 0, hrv / base < 0.88, todayRun != nil, !ranToday {
            parts.append("HRV is well under your usual, so keep today's run easy.")
        }
        if let n = d.nextRun, todayRun == nil { parts.append("Next: \(n.shortTitle) \(Fmt.relativeDay(n.date).lowercased()).") }
        if parts.isEmpty { return d.hasWatchData ? "Recovery rings come from your watch." : lastRunLine }
        return parts.joined(separator: " ")
    }

    private var lastRunLine: String {
        guard let r = d.snap.runs.first else { return "Runs come from Strava." }
        return "Last run: \(Fmt.miles(r.miles)) mi \(Fmt.relativeDay(r.date).lowercased())."
    }
}

struct NextWorkoutCard: View {
    let d: Derived
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(text: "Next workout")
                if let r = d.nextRun {
                    HStack(spacing: 8) {
                        Image(systemName: r.kind.symbol).foregroundStyle(r.kind.color)
                        Text(r.shortTitle).font(.title3.weight(.semibold))
                        if let m = r.miles { Text("\(Fmt.miles(m)) mi").foregroundStyle(.secondary) }
                    }
                    Text(Fmt.relativeDay(r.date)).font(.callout).foregroundStyle(.secondary)
                    let away = d.trip(on: r.date)
                    if let t = away {
                        Label("Away: \(t.place), \(t.modeText)", systemImage: "airplane").font(.callout).foregroundStyle(.orange)
                    }
                    if !r.notes.isEmpty { Text(r.notes).font(.callout).fixedSize(horizontal: false, vertical: true) }
                    let w: (day: DayWeather?, hour: HourWeather?) = away == nil ? d.weather(for: r) : (nil, nil)
                    if let h = w.hour ?? nil {
                        let desc = Weather.describe(h.code)
                        Divider()
                        HStack(spacing: 6) {
                            Image(systemName: desc.symbol)
                            Text("\(desc.text), \(Int(h.tempF ?? 0))°F, feels \(Int(h.feelsF ?? 0))°, wind \(Int(h.windMph ?? 0)) mph, rain \(Int(h.precipProb ?? 0))%")
                        }
                        .font(.callout)
                        Text(Weather.wear(feelsF: h.feelsF, precip: h.precipProb)).font(.callout).foregroundStyle(.secondary)
                    } else if let day = w.day {
                        let desc = Weather.describe(day.code)
                        Divider()
                        Label("\(desc.text), \(Int(day.minF ?? 0))–\(Int(day.maxF ?? 0))°F", systemImage: desc.symbol).font(.callout)
                    }
                } else {
                    Text("No planned run found in your calendar.").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct GoalCard: View {
    let d: Derived
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(text: "Half goal")
                if let p = d.predicted {
                    Text(Fmt.hms(p)).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    if let g = d.gapToGoal {
                        Text(g <= 0 ? "Predicted under your \(Fmt.hms(d.goal ?? 0)) goal by \(Fmt.hms(-g))" : "\(Fmt.hms(g)) to go")
                            .foregroundStyle(g <= 0 ? Derived.Tone.good.color : .secondary)
                    }
                    if d.goal == nil {
                        Text("Set a goal time in Settings > Goal.").font(.callout).foregroundStyle(.secondary)
                    }
                    if let pr = d.progressToGoal { GoalBar(progress: pr) }
                    if let f = d.snap.predictedFrom {
                        Text("From \(Fmt.miles(f.miles)) mi on \(Fmt.shortDay(f.date)) at \(Fmt.pace(f.paceSecPerMile))").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("—").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Needs an outdoor run of 3+ miles in the last 6 weeks.").font(.callout).foregroundStyle(.secondary)
                }
                if let b = d.bestHalf, let r = d.snap.halfBest {
                    Divider()
                    Text("Best half \(Fmt.hms(b)) · \(Fmt.shortDay(r.date))").font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WeekCard: View {
    let d: Derived
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardTitle(text: "This week")
                    Spacer()
                    Text("\(Fmt.miles(d.weekMiles)) mi" + (d.weekPlanMiles.map { " of \(Fmt.miles($0)) planned" } ?? ""))
                        .font(.callout).foregroundStyle(.secondary)
                }
                if d.weekPlan.isEmpty {
                    Text("No planned runs this week.").foregroundStyle(.secondary)
                } else {
                    ForEach(d.weekPlan) { p in
                        let done = d.snap.runs.contains { $0.date == p.date }
                        HStack(spacing: 10) {
                            Image(systemName: done ? "checkmark.circle.fill" : (p.date < d.todayKey ? "xmark.circle" : "circle"))
                                .foregroundStyle(done ? Derived.Tone.good.color : (p.date < d.todayKey ? Derived.Tone.low.color : .secondary))
                            Text(Fmt.shortDay(p.date)).frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
                            Image(systemName: p.kind.symbol).foregroundStyle(p.kind.color)
                            Text(p.shortTitle)
                            if let t = d.trip(on: p.date) {
                                Label(t.place, systemImage: "airplane").font(.caption).foregroundStyle(.orange).lineLimit(1)
                                    .help("Away: \(t.place), \(t.modeText)")
                            }
                            Spacer()
                            if let m = p.miles { Text("\(Fmt.miles(m)) mi").monospacedDigit().foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }
}

struct TripsCard: View {
    let d: Derived
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CardTitle(text: "Trips")
                    Spacer()
                    Text("From your calendar").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(d.upcomingTrips.prefix(5)) { t in
                    let runs = d.snap.plan.filter { t.covers($0.date) }
                    HStack(spacing: 10) {
                        Image(systemName: "airplane").foregroundStyle(.orange)
                        Text(t.start == t.end ? Fmt.shortDay(t.start) : "\(Fmt.shortDay(t.start)) to \(Fmt.shortDay(t.end))")
                            .frame(width: 190, alignment: .leading).foregroundStyle(.secondary)
                        Text(t.place).lineLimit(1)
                        Spacer()
                        Text(t.modeText + (runs.isEmpty ? "" : " · \(runs.count) run\(runs.count == 1 ? "" : "s")"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text("Trips come from flights and hotel bookings in your calendars, like the ones Gmail adds or an event titled \"Flight to Denver\" or \"🏨 Hilton Denver\". Online meetings are never trips. Put \"run: treadmill\" or \"run: none\" in an event's notes if you can't run outside.")
                    .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct RecentRunsCard: View {
    let d: Derived
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CardTitle(text: "Recent runs")
                    Spacer()
                    if let n = d.daysSinceRun { Text(n == 0 ? "Ran today" : "Last run \(n) day\(n == 1 ? "" : "s") ago").font(.callout).foregroundStyle(.secondary) }
                }
                ForEach(d.snap.runs.prefix(8)) { r in
                    HStack {
                        Text(Fmt.shortDay(r.date)).frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
                        Text(r.name).lineLimit(1)
                        if !r.outdoor { Image(systemName: "house").font(.caption).foregroundStyle(.secondary).help("Indoor or no GPS") }
                        Spacer()
                        Text("\(Fmt.miles(r.miles)) mi").monospacedDigit()
                        Text(Fmt.pace(r.paceSecPerMile)).monospacedDigit().foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                        Text(r.avgHR.map { "\(Int($0)) bpm" } ?? "").monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                    }
                    .font(.callout)
                }
                if d.snap.runs.isEmpty { Text("Connect Strava to see your runs.").foregroundStyle(.secondary) }
            }
        }
    }
}
