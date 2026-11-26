import Charts
import SwiftUI

/// The training plan as a month calendar, with training metrics and weekly miles.
struct TrainingView: View {
    @EnvironmentObject var model: AppModel
    @State private var month: (year: Int, month: Int) = TrainingView.initialMonth()
    @State private var selected: String?

    var body: some View {
        let d = model.derived
        let plan = d.fullPlan
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(d)
                if plan.isEmpty {
                    Label("No planned runs yet. Add all-day events starting with 🏃 (runs) or 🏁 (races) to your calendar, then connect Google Calendar or allow Calendars access in Settings.",
                          systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                MetricsRow(d: d, plan: plan)
                WeeklyMilesCard(d: d, plan: plan)
                calendarCard(d, plan: plan)
                if let s = selected { DayDetailCard(d: d, day: s, plan: plan) }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private static func initialMonth() -> (year: Int, month: Int) {
        let c = TrainingMath.calendar
        let day = Date()
        return (c.component(.year, from: day), c.component(.month, from: day))
    }

    private func header(_ d: Derived) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Training").font(.system(size: 28, weight: .semibold, design: .rounded))
            Spacer()
            if let s = d.planStart, d.todayKey < s {
                Text("Plan starts \(Fmt.shortDay(s))").font(.callout).foregroundStyle(.secondary)
            }
            if let n = d.daysToRace, n >= 0 {
                Text("\(d.profile.raceTitle): \(n) days").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var monthTitle: String {
        var comps = DateComponents(); comps.year = month.year; comps.month = month.month; comps.day = 1
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; f.timeZone = AppConfig.timeZone
        return TrainingMath.calendar.date(from: comps).map { f.string(from: $0) } ?? ""
    }

    private func shift(_ n: Int) {
        var m = month.month + n, y = month.year
        while m < 1 { m += 12; y -= 1 }
        while m > 12 { m -= 12; y += 1 }
        month = (y, m)
    }

    private func calendarCard(_ d: Derived, plan: [PlannedRun]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardTitle(text: "Plan calendar")
                    Spacer()
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.help("Previous month")
                    Text(monthTitle).font(.headline).frame(minWidth: 130)
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.help("Next month")
                    Button("Today") { month = TrainingView.initialMonth(); selected = d.todayKey }
                }
                .buttonStyle(.borderless)
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                    }
                    ForEach(Array(TrainingMath.monthGrid(year: month.year, month: month.month).enumerated()), id: \.offset) { _, week in
                        GridRow {
                            ForEach(0..<7, id: \.self) { i in
                                if let day = week[i] {
                                    DayCell(d: d, day: day, plan: plan, selected: selected == day)
                                        .onTapGesture { selected = (selected == day ? nil : day) }
                                } else {
                                    Color.clear.frame(maxWidth: .infinity, minHeight: 74)
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 14) {
                    ForEach([PlannedRun.Kind.easy, .workout, .long, .race], id: \.self) { k in
                        Label(k.label, systemImage: k.symbol).foregroundStyle(k.color)
                    }
                    Label("Strength", systemImage: "dumbbell").foregroundStyle(.secondary)
                    Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(Derived.Tone.good.color)
                    Label("Trip", systemImage: "airplane").foregroundStyle(.orange)
                }
                .font(.caption)
            }
        }
    }
}

private extension PlannedRun.Kind {
    var label: String {
        switch self {
        case .easy: return "Easy"
        case .workout: return "Workout"
        case .long: return "Long"
        case .race: return "Race or trial"
        }
    }
}

private struct DayCell: View {
    let d: Derived
    let day: String
    let plan: [PlannedRun]
    let selected: Bool

    var body: some View {
        let planned = d.plannedRuns(on: day, in: plan)
        let ran = d.runs(on: day)
        let past = day < d.todayKey
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(String(Int(day.suffix(2)) ?? 0)).font(.caption.weight(day == d.todayKey ? .bold : .regular))
                    .foregroundStyle(day == d.todayKey ? Color.accentColor : Color.secondary)
                Spacer(minLength: 0)
                if d.trip(on: day) != nil { Image(systemName: "airplane").font(.caption2).foregroundStyle(.orange) }
            }
            ForEach(planned) { p in
                HStack(spacing: 3) {
                    Image(systemName: p.kind.symbol)
                    Text(p.miles.map { "\(Fmt.miles($0)) mi" } ?? p.shortTitle).lineLimit(1)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(p.kind.color.opacity(past && ran.isEmpty ? 0.45 : 1))
            }
            if !ran.isEmpty {
                Label("\(Fmt.miles(ran.reduce(0) { $0 + $1.miles })) mi", systemImage: "checkmark.circle.fill")
                    .font(.caption2).foregroundStyle(Derived.Tone.good.color).lineLimit(1)
            } else if past && !planned.isEmpty {
                Text("missed").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(day == d.todayKey ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .help(planned.map(\.shortTitle).joined(separator: ", "))
    }
}

private struct DayDetailCard: View {
    let d: Derived
    let day: String
    let plan: [PlannedRun]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(text: Fmt.relativeDay(day))
                if let t = d.trip(on: day) {
                    Label("Away: \(t.place), \(t.modeText)", systemImage: "airplane").foregroundStyle(.orange)
                }
                let planned = d.plannedRuns(on: day, in: plan)
                ForEach(planned) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(p.shortTitle + (p.miles.map { " · \(Fmt.miles($0)) mi" } ?? ""), systemImage: p.kind.symbol)
                            .font(.headline).foregroundStyle(p.kind.color)
                        if !p.notes.isEmpty { Text(p.notes).font(.callout).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                ForEach(d.runs(on: day)) { r in
                    Label("\(r.name): \(Fmt.miles(r.miles)) mi at \(Fmt.pace(r.movingS / r.miles))" + (r.avgHR.map { ", HR \(Int($0))" } ?? ""),
                          systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(Derived.Tone.good.color)
                }
                if planned.isEmpty && d.runs(on: day).isEmpty {
                    Text("Rest day.").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MetricsRow: View {
    let d: Derived
    let plan: [PlannedRun]

    var body: some View {
        let adh = TrainingMath.adherence(plan: plan, runs: d.snap.runs, today: d.todayKey)
        HStack(alignment: .top, spacing: 12) {
            Metric(title: "This week", value: "\(Fmt.miles(d.weekMiles)) mi",
                   sub: d.weekPlanMiles.map { "of \(Fmt.miles($0)) planned" } ?? "no runs planned")
            Metric(title: "Plan runs done", value: adh.due == 0 ? "—" : "\(adh.done) of \(adh.due)",
                   sub: adh.due == 0 ? (d.planStart.map { "starts \(Fmt.shortDay($0))" } ?? "no plan yet") : "\(Int((Double(adh.done) / Double(adh.due) * 100).rounded()))%")
            Metric(title: "Predicted half", value: d.predicted.map { Fmt.hms($0) } ?? "—",
                   sub: d.predicted == nil ? "needs a 3+ mi outdoor run"
                       : d.gapToGoal.map { $0 > 0 ? "\(Fmt.hms($0)) to goal" : "under goal" } ?? "set a goal in Settings")
            Metric(title: "Best half", value: d.bestHalf.map { Fmt.hms($0) } ?? "—", sub: d.goal.map { "goal \(Fmt.hms($0))" } ?? "no goal set")
            Metric(title: "Longest run, 4 wks", value: d.longestRecent.map { "\(Fmt.miles($0.miles)) mi" } ?? "—",
                   sub: d.longestRecent.map { Fmt.shortDay($0.date) } ?? "")
        }
    }
}

private struct Metric: View {
    let title: String
    let value: String
    let sub: String
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                CardTitle(text: title)
                Text(value).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WeeklyMilesCard: View {
    let d: Derived
    let plan: [PlannedRun]

    var body: some View {
        // Four weeks before the plan (or before today) through the last planned run or race day.
        let start = min(d.planStart ?? d.todayKey, d.todayKey)
        let first = TrainingMath.add(TrainingMath.monday(of: start), -28)
        let end = [plan.last?.date, d.profile.raceDate, TrainingMath.add(d.todayKey, 28)].compactMap { $0 }.max() ?? d.todayKey
        let count = min(60, max(8, TrainingMath.weeksBetween(first, end) + 1))
        let weeks = TrainingMath.weeklyMiles(runs: d.snap.runs, plan: plan, firstMonday: first, count: count)
        let thisMonday = TrainingMath.monday(of: d.todayKey)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CardTitle(text: "Weekly miles")
                    Spacer()
                    Text("Bars: run (Strava) · Line: planned").font(.caption).foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(weeks) { w in
                        BarMark(x: .value("Week", Fmt.date(w.monday) ?? Date(), unit: .weekOfYear), y: .value("Run", w.actual))
                            .foregroundStyle(w.monday == thisMonday ? Color.accentColor : Color.accentColor.opacity(0.55))
                    }
                    ForEach(weeks) { w in
                        LineMark(x: .value("Week", Fmt.date(w.monday) ?? Date(), unit: .weekOfYear), y: .value("Planned", w.planned))
                            .foregroundStyle(.orange)
                            .interpolationMethod(.stepCenter)
                    }
                    if let t = Fmt.date(thisMonday) {
                        RuleMark(x: .value("This week", t, unit: .weekOfYear)).foregroundStyle(.secondary.opacity(0.4))
                    }
                }
                .chartYAxisLabel("mi")
                .frame(height: 180)
            }
        }
    }
}
