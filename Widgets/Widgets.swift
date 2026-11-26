import SwiftUI
import WidgetKit

// MARK: - Timeline

struct HFEntry: TimelineEntry {
    let date: Date
    let snap: Snapshot
    var d: Derived { Derived(snap: snap) }
}

/// Every widget shares one provider: it shows the cached snapshot, and pulls fresh data
/// itself when the cache is older than AppConfig.widgetMaxAge, so widgets stay live even
/// when the app is closed.
struct HFProvider: TimelineProvider {
    func placeholder(in context: Context) -> HFEntry { HFEntry(date: Date(), snap: Sample.snapshot) }

    func getSnapshot(in context: Context, completion: @escaping (HFEntry) -> Void) {
        let s = Store.load()
        completion(HFEntry(date: Date(), snap: (context.isPreview && s.updated == nil) ? Sample.snapshot : s))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HFEntry>) -> Void) {
        Task {
            var s = Store.load()
            let stale = s.updated.map { Date().timeIntervalSince($0) > AppConfig.widgetMaxAge } ?? true
            if stale { s = await Refresher.refresh(plan: nil, reloadWidgets: false) }
            let entry = HFEntry(date: Date(), snap: s)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }
}

enum Sample {
    static var snapshot: Snapshot {
        var s = Snapshot()
        s.updated = Date()
        let today = Fmt.key(Date())
        s.recovery = [RecoveryDay(date: today, readiness: 72, verdict: "ready", sleepH: 7.2, sleepNeedH: 7.8, hrv: 58, hrvBase: 60, restingHR: 52, steps: 9400)]
        s.plan = [PlannedRun(id: "x", date: today, title: "🏃 Easy run · 2.5 mi", notes: "Easy, conversational. 4 x 20 s strides at the end.", miles: 2.5)]
        s.predictedHalfS = 7650
        s.watchConnected = true
        return s
    }
}

// MARK: - Shared bits

private struct Updated: View {
    let snap: Snapshot
    var body: some View {
        if let u = snap.updated {
            Text(u, style: .relative).font(.system(size: 9)).foregroundStyle(.tertiary) + Text(" ago").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}

private struct Header: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

// MARK: - Today (recovery rings)

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: HFEntry

    var body: some View {
        let rings = entry.d.rings
        VStack(alignment: .leading, spacing: 6) {
            HStack { Header(title: "Today", symbol: "heart.circle"); Spacer(); Updated(snap: entry.snap) }
            if rings.count < 4 {
                TodayRunOnly(d: entry.d)
            } else if family == .systemSmall {
                Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow { RingView(ring: rings[0], size: 46, line: 5, showLabels: false); RingView(ring: rings[1], size: 46, line: 5, showLabels: false) }
                    GridRow { RingView(ring: rings[2], size: 46, line: 5, showLabels: false); RingView(ring: rings[3], size: 46, line: 5, showLabels: false) }
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 10) {
                    ForEach(rings) { RingView(ring: $0, size: 58, line: 6) }
                }
                .frame(maxWidth: .infinity)
                if let n = entry.d.nextRun {
                    Label("\(Fmt.relativeDay(n.date)): \(n.shortTitle)\(n.miles.map { " · \(Fmt.miles($0)) mi" } ?? "")", systemImage: n.kind.symbol)
                        .font(.caption).foregroundStyle(n.kind.color).lineLimit(1)
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

/// Today without athletedata: the plan for today and the last Strava run.
private struct TodayRunOnly: View {
    let d: Derived
    var body: some View {
        let today = d.snap.plan.first { $0.date == d.todayKey }
        let ran = d.snap.runs.contains { $0.date == d.todayKey }
        VStack(alignment: .leading, spacing: 4) {
            if let t = today {
                Label(ran ? "Done: \(t.shortTitle)" : t.shortTitle + (t.miles.map { " · \(Fmt.miles($0)) mi" } ?? ""), systemImage: t.kind.symbol)
                    .font(.headline).foregroundStyle(t.kind.color).lineLimit(2)
            } else {
                Text("Rest day from running").font(.headline)
                if let n = d.nextRun {
                    Text("Next: \(n.shortTitle) \(Fmt.relativeDay(n.date).lowercased())")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let r = d.snap.runs.first {
                Text("Last run \(Fmt.miles(r.miles)) mi · \(Fmt.relativeDay(r.date))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayRings", provider: HFProvider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("Today")
            .description("Today’s run, plus readiness, sleep, HRV and steps when athletedata is connected.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Next workout

struct NextWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: HFEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Header(title: "Next run", symbol: "figure.run"); Spacer(); Updated(snap: entry.snap) }
            if let n = entry.d.nextRun {
                let w = entry.d.weather(for: n)
                Text(Fmt.relativeDay(n.date)).font(.caption).foregroundStyle(.secondary)
                Label(n.shortTitle, systemImage: n.kind.symbol)
                    .font(.headline).foregroundStyle(n.kind.color).lineLimit(1)
                if let m = n.miles { Text("\(Fmt.miles(m)) mi").font(.title3.weight(.semibold)).monospacedDigit() }
                if family != .systemSmall, !n.notes.isEmpty {
                    Text(n.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if let t = entry.d.trip(on: n.date) {
                    Label("Away: \(t.place)", systemImage: "airplane").font(.caption).foregroundStyle(.orange).lineLimit(1)
                } else if let h = w.hour, let f = h.feelsF ?? h.tempF {
                    let desc = Weather.describe(h.code ?? w.day?.code ?? 0)
                    HStack(spacing: 4) {
                        Image(systemName: desc.symbol)
                        Text("\(Int(f.rounded()))°")
                        if family != .systemSmall {
                            Text("· " + Weather.wear(feelsF: f, precip: h.precipProb ?? 0)).lineLimit(1)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Spacer()
                Text("No run planned").font(.headline).foregroundStyle(.secondary)
                Text("Open the app to load your calendar.").font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct NextWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextWorkout", provider: HFProvider()) { NextWidgetView(entry: $0) }
            .configurationDisplayName("Next run")
            .description("Your next planned run with the weather for it.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Half goal progress

struct GoalWidgetView: View {
    let entry: HFEntry

    var body: some View {
        let d = entry.d
        VStack(alignment: .leading, spacing: 5) {
            HStack { Header(title: "Half goal", symbol: "flag.checkered"); Spacer() }
            if let p = d.predicted {
                Text(Fmt.hms(p)).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                Text("predicted").font(.caption2).foregroundStyle(.secondary)
                if let g = d.gapToGoal {
                    Text(g > 0 ? "\(Fmt.hms(g)) to go" : "\(Fmt.hms(-g)) under goal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(g > 0 ? Derived.Tone.caution.color : Derived.Tone.good.color)
                }
            } else {
                Text("—").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Needs a 3+ mile outdoor run in the last 6 weeks").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let prog = d.progressToGoal { GoalBar(progress: prog) }
            if let n = d.daysToRace, n >= 0, let r = d.profile.raceDate {
                Text("\(Fmt.shortDay(r)) · \(n) days").font(.caption2).foregroundStyle(.tertiary)
            } else if d.goal == nil {
                Text("Set a goal in Settings").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct GoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HalfGoal", provider: HFProvider()) { GoalWidgetView(entry: $0) }
            .configurationDisplayName("Half goal")
            .description("Predicted half marathon time against the goal you set.")
            .supportedFamilies([.systemSmall])
    }
}

// MARK: - Bundle

@main
struct HealthFitnessWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        NextWorkoutWidget()
        GoalWidget()
    }
}
