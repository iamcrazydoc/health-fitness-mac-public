import SwiftUI
import WebKit

struct RecoveryView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var rec: RecoveryModel
    @State private var showCheckIn = false
    @State private var media: LibExercise?
    @State private var showGeneral = false

    var body: some View {
        let plans = rec.plans
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recovery").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Spacer()
                    Button { showCheckIn = true } label: { Label("Check in", systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderedProminent)
                }
                Text(rec.lib.disclaimer).font(.callout).foregroundStyle(.secondary)

                if let g = rec.generalAdvice(model.derived) {
                    Card { Label(g, systemImage: "heart.text.square").frame(maxWidth: .infinity, alignment: .leading) }
                }

                if plans.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Nothing to work on", systemImage: "checkmark.seal").font(.headline).foregroundStyle(Derived.Tone.good.color)
                            Text("Log a check-in when something feels tight, sore or painful and you'll get a plan for it here.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                ForEach(plans) { PlanCard(plan: $0, media: $media) }

                if let general = rec.lib.part("general"), showGeneral || plans.isEmpty || rec.generalAdvice(model.derived) != nil {
                    PlanCard(plan: PartPlan(part: general, latest: BodyEntry(date: Fmt.key(Date()), part: "general", feel: "Sore", severity: 1),
                                            status: "Anytime", trend: nil, phase: .calm, redFlags: [], exercises: general.exercises),
                             media: $media, showStatus: false)
                } else {
                    Button("Show general recovery options") { showGeneral = true }.buttonStyle(.link)
                }

                LiteratureCard()
                HistoryCard()
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showCheckIn) { CheckInSheet().environmentObject(rec) }
        .sheet(item: $media) { MediaSheet(exercise: $0) }
        .task { await rec.checkLiterature() }
    }
}

// MARK: - Plan card

struct PlanCard: View {
    @EnvironmentObject var rec: RecoveryModel
    let plan: PartPlan
    @Binding var media: LibExercise?
    var showStatus = true

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(plan.part.name, systemImage: plan.part.symbol).font(.title3.weight(.semibold))
                    Spacer()
                    if showStatus {
                        Text("\(plan.latest.feel) \(plan.latest.severity)/5" + (plan.trend.map { " · \($0)" } ?? ""))
                            .font(.callout).foregroundStyle(.secondary)
                        Text(plan.phase.title).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(plan.phase.color.opacity(0.18))).foregroundStyle(plan.phase.color)
                    }
                }
                if plan.phase == .seeDoctor {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Get this checked by a physio or doctor before training through it.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.semibold)).foregroundStyle(Derived.Tone.low.color)
                        if !plan.redFlags.isEmpty { Text("You logged: " + plan.redFlags.joined(separator: ", ")).font(.callout) }
                        if let r = plan.part.redflag { Text(r).font(.callout).foregroundStyle(.secondary) }
                        Text("Until then, only gentle exercises that don't increase pain.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text(plan.part.summary).font(.callout)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "figure.run").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.part.run_rule).font(.callout)
                        Cites(pmids: plan.part.run_refs)
                    }
                }
                Divider()
                ForEach(plan.exercises) { ex in ExerciseRow(ex: ex, media: $media) }
                let fresh = rec.newPapers(plan.part.id)
                if !fresh.isEmpty {
                    Divider()
                    Text("New research this week").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(fresh.prefix(3)) { PaperRow(paper: $0) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ExerciseRow: View {
    let ex: LibExercise
    @Binding var media: LibExercise?
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: ex.symbol).foregroundStyle(.secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.name).font(.headline)
                    Text(ex.dose).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { media = ex } label: { Label("Photos & video", systemImage: "play.rectangle") }
                    .buttonStyle(.bordered).controlSize(.small)
                Button { withAnimation { open.toggle() } } label: { Image(systemName: open ? "chevron.up" : "chevron.down") }
                    .buttonStyle(.borderless)
            }
            if open {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(ex.steps.enumerated()), id: \.offset) { i, s in Text("\(i + 1). \(s)").font(.callout) }
                }
                .padding(.leading, 28)
            }
            Cites(pmids: ex.refs).padding(.leading, 28)
        }
    }
}

/// Inline citations: author, journal, year, linked to PubMed and the DOI.
struct Cites: View {
    @EnvironmentObject var rec: RecoveryModel
    let pmids: [String]
    var body: some View {
        let refs = pmids.compactMap { rec.lib.ref($0) }
        if !refs.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(refs) { r in
                    HStack(spacing: 4) {
                        Text("Source:").foregroundStyle(.tertiary)
                        Link("\(r.short) (\(r.type))", destination: r.pubmedURL).help(r.title)
                        if let d = r.doiURL { Link("DOI", destination: d) }
                    }
                    .font(.caption)
                }
            }
        }
    }
}

struct PaperRow: View {
    let paper: Paper
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Link(paper.title, destination: paper.url).font(.callout)
            HStack(spacing: 4) {
                Text([paper.authors, paper.journal, paper.pubdate].filter { !$0.isEmpty }.joined(separator: " · "))
                if let t = paper.types.first(where: { $0 != "Journal Article" }) { Text("· \(t)") }
                if let d = paper.doiURL { Link("DOI", destination: d) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Literature

struct LiteratureCard: View {
    @EnvironmentObject var rec: RecoveryModel
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Latest research from PubMed", systemImage: "books.vertical").font(.headline)
                    Spacer()
                    if rec.checking { ProgressView().controlSize(.small) }
                    Button("Check now") { Task { await rec.checkLiterature(force: true) } }.disabled(rec.checking)
                }
                Text(rec.literature.lastCheck.map { "Checked \($0.formatted(date: .abbreviated, time: .shortened)). Checks again automatically every week. Only systematic reviews, meta-analyses, trials and guidelines are listed." }
                     ?? "Checks PubMed once a week for new systematic reviews, meta-analyses, trials and guidelines.")
                    .font(.caption).foregroundStyle(.secondary)
                if let e = rec.literature.error { Text(e).font(.caption).foregroundStyle(Derived.Tone.caution.color) }
                ForEach(rec.lib.parts) { part in
                    let papers = rec.literature.byPart[part.id] ?? []
                    if !papers.isEmpty {
                        DisclosureGroup("\(part.name) · \(papers.count)") {
                            VStack(alignment: .leading, spacing: 8) { ForEach(papers) { PaperRow(paper: $0) } }
                                .padding(.vertical, 4)
                        }
                    }
                }
                Text("New papers are shown for you to read. The exercise plans only change when they're reviewed and added to the library.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - History

struct HistoryCard: View {
    @EnvironmentObject var rec: RecoveryModel
    var body: some View {
        if !rec.entries.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Check-in history").font(.headline)
                    ForEach(rec.entries.prefix(30)) { e in
                        HStack {
                            Text(Fmt.shortDay(e.date)).monospacedDigit().frame(width: 90, alignment: .leading)
                            Text(rec.lib.part(e.part)?.name ?? e.part).frame(width: 170, alignment: .leading)
                            Text("\(e.feel) \(e.severity)/5").frame(width: 90, alignment: .leading)
                            Text(([e.note] + e.symptoms).filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Button(role: .destructive) { rec.delete(e) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                        .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Check-in

struct CheckInSheet: View {
    @EnvironmentObject var rec: RecoveryModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var part = "calf"
    @State private var feel = "Sore"
    @State private var severity = 2
    @State private var symptoms: Set<String> = []
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How does your body feel?").font(.title2.weight(.semibold))
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Where", selection: $part) {
                    ForEach(rec.lib.parts) { Text($0.name).tag($0.id) }
                }
                Picker("Feels", selection: $feel) {
                    ForEach(Feel.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Picker("How bad (1–5)", selection: $severity) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Section("Symptoms") {
                    ForEach(Symptom.all, id: \.self) { s in
                        Toggle(s, isOn: Binding(get: { symptoms.contains(s) }, set: { if $0 { symptoms.insert(s) } else { symptoms.remove(s) } }))
                    }
                }
                TextField("Note", text: $note, axis: .vertical)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    rec.add(BodyEntry(date: Fmt.key(date), part: part, feel: feel, severity: severity,
                                      symptoms: Symptom.all.filter { symptoms.contains($0) }, note: note))
                    dismiss()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 640)
    }
}

// MARK: - Photos and video (shown from the trusted source page)

struct MediaSheet: View {
    let exercise: LibExercise
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(exercise.name).font(.headline)
                    Text("From \(exercise.mediaTitle)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let u = exercise.mediaURL { Button("Open in browser") { NSWorkspace.shared.open(u) } }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            if let u = exercise.mediaURL { SourcePageView(url: u) } else { Text("No media link").padding() }
        }
        .frame(width: 900, height: 720)
    }
}

struct SourcePageView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView()
        w.load(URLRequest(url: url))
        return w
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
