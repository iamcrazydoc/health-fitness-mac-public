import Foundation
import SwiftUI

// MARK: - Library (bundled, every exercise cited)

struct LibRef: Codable, Identifiable, Hashable {
    let pmid: String
    let authors: String
    let title: String
    let journal: String
    let year: Int
    let doi: String
    let type: String
    var id: String { pmid }
    var pubmedURL: URL { URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/")! }
    var doiURL: URL? { doi.isEmpty ? nil : URL(string: "https://doi.org/\(doi)") }
    var short: String { "\(authors) \(journal) \(year)" }
}

struct LibExercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let phase: String          // calm | build | return
    let dose: String
    let steps: [String]
    let refs: [String]
    let media: String
    let mediaTitle: String
    let symbol: String
    var mediaURL: URL? { URL(string: media) }
}

struct LibPart: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let pubmed: String
    let summary: String
    let run_rule: String
    let run_refs: [String]
    var redflag: String?
    var redflag_refs: [String]?
    let exercises: [LibExercise]
}

struct RecoveryLibrary: Codable {
    let version: Int
    let built: String
    let refs: [LibRef]
    let parts: [LibPart]
    let disclaimer: String

    static let shared: RecoveryLibrary = {
        guard let u = (Bundle.allBundles + [Bundle.main]).lazy.compactMap({ $0.url(forResource: "recovery_library", withExtension: "json") }).first,
              let d = try? Data(contentsOf: u),
              let l = try? JSONDecoder().decode(RecoveryLibrary.self, from: d)
        else { return RecoveryLibrary(version: 0, built: "", refs: [], parts: [], disclaimer: "") }
        return l
    }()

    func ref(_ pmid: String) -> LibRef? { refs.first { $0.pmid == pmid } }
    func part(_ id: String) -> LibPart? { parts.first { $0.id == id } }
}

// MARK: - Body log (your daily check-ins)

struct BodyEntry: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var date: String
    var part: String
    var feel: String           // Tight | Sore | Pain | Injury | Better | Recovered
    var severity: Int          // 1–5
    var symptoms: [String] = []
    var note: String = ""
}

enum Symptom {
    /// Any of these means "get it checked" before following a self-guided plan.
    static let redFlags = ["Pain at rest or at night", "Pain in one spot on the bone", "Numbness or tingling", "Visible swelling or bruising", "Limping or it changes how I run"]
    static let others = ["Morning stiffness", "Hurts at the start of a run", "Hurts later in a run", "Hurts going downhill or on stairs", "Tight but not painful"]
    static var all: [String] { others + redFlags }
}

enum Feel: String, CaseIterable { case Tight, Sore, Pain, Injury, Better, Recovered }

enum Phase: String { case seeDoctor, calm, build, `return` 
    var title: String {
        switch self {
        case .seeDoctor: return "Get it checked"
        case .calm: return "Calm it down"
        case .build: return "Build strength"
        case .return: return "Return to full training"
        }
    }
    var color: Color {
        switch self {
        case .seeDoctor: return Derived.Tone.low.color
        case .calm: return Derived.Tone.caution.color
        case .build: return Color(red: 0.36, green: 0.62, blue: 0.85)
        case .return: return Derived.Tone.good.color
        }
    }
}

struct PartPlan: Identifiable {
    let part: LibPart
    let latest: BodyEntry
    let status: String        // Active | Watching
    let trend: String?        // better | worse | same
    let phase: Phase
    let redFlags: [String]
    let exercises: [LibExercise]
    var id: String { part.id }
}

// MARK: - Live literature (PubMed, checked weekly)

struct Paper: Codable, Identifiable, Hashable {
    let pmid: String
    let title: String
    let journal: String
    let pubdate: String
    let authors: String
    let doi: String?
    let types: [String]
    var foundAt: Date
    var id: String { pmid }
    var url: URL { URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/")! }
    var doiURL: URL? { doi.flatMap { URL(string: "https://doi.org/\($0)") } }
}

struct Literature: Codable {
    var lastCheck: Date?
    var byPart: [String: [Paper]] = [:]
    var error: String?
}

enum PubMed {
    private static let base = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/"
    private static let filter = " AND (systematic review[pt] OR meta-analysis[pt] OR randomized controlled trial[pt] OR practice guideline[pt])"

    static func search(_ query: String, since: Date, max: Int = 5) async throws -> [Paper] {
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd"; f.locale = Locale(identifier: "en_US_POSIX")
        var c = URLComponents(string: base + "esearch.fcgi")!
        c.queryItems = [
            .init(name: "db", value: "pubmed"), .init(name: "retmode", value: "json"),
            .init(name: "retmax", value: String(max)), .init(name: "sort", value: "pub_date"),
            .init(name: "datetype", value: "edat"), .init(name: "mindate", value: f.string(from: since)),
            .init(name: "maxdate", value: "3000"), .init(name: "term", value: "(" + query + ")" + filter),
            .init(name: "tool", value: "HealthFitnessMac"),
        ]
        let (d, r) = try await URLSession.shared.data(from: c.url!)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw HFError.http("PubMed", (r as? HTTPURLResponse)?.statusCode ?? 0) }
        let ids = try parseSearch(d)
        if ids.isEmpty { return [] }
        try await Task.sleep(nanoseconds: 400_000_000) // stay under 3 requests a second
        return try await summary(ids)
    }

    static func summary(_ ids: [String]) async throws -> [Paper] {
        var c = URLComponents(string: base + "esummary.fcgi")!
        c.queryItems = [.init(name: "db", value: "pubmed"), .init(name: "retmode", value: "json"),
                        .init(name: "id", value: ids.joined(separator: ",")), .init(name: "tool", value: "HealthFitnessMac")]
        let (d, r) = try await URLSession.shared.data(from: c.url!)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw HFError.http("PubMed", (r as? HTTPURLResponse)?.statusCode ?? 0) }
        return try parseSummary(d, ids: ids)
    }

    /// PMIDs from an esearch JSON response.
    static func parseSearch(_ d: Data) throws -> [String] {
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any],
              let res = j["esearchresult"] as? [String: Any], let ids = res["idlist"] as? [String] else { throw HFError.parse("PubMed") }
        return ids
    }

    /// Papers from an esummary JSON response, in the order of `ids`.
    static func parseSummary(_ d: Data, ids: [String], now: Date = Date()) throws -> [Paper] {
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any],
              let res = j["result"] as? [String: Any] else { throw HFError.parse("PubMed") }
        return ids.compactMap { id in
            guard let a = res[id] as? [String: Any], let title = a["title"] as? String else { return nil }
            let authors = (a["authors"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let doi = (a["articleids"] as? [[String: Any]])?.first { ($0["idtype"] as? String) == "doi" }?["value"] as? String
            return Paper(pmid: id, title: title,
                         journal: (a["source"] as? String) ?? "",
                         pubdate: (a["pubdate"] as? String) ?? "",
                         authors: authors.isEmpty ? "" : authors[0] + (authors.count > 1 ? " et al." : ""),
                         doi: doi, types: (a["pubtype"] as? [String]) ?? [], foundAt: now)
        }
    }
}

// MARK: - Model

@MainActor
final class RecoveryModel: ObservableObject {
    @Published var entries: [BodyEntry] = []
    @Published var literature = Literature()
    @Published var checking = false

    let lib = RecoveryLibrary.shared
    static let weekly: TimeInterval = 7 * 86400

    private static func file(_ name: String) -> URL { Store.url.deletingLastPathComponent().appendingPathComponent(name) }

    init() {
        if let d = try? Data(contentsOf: Self.file("bodylog.json")), let e = try? JSONDecoder.hf.decode([BodyEntry].self, from: d) { entries = e }
        if let d = try? Data(contentsOf: Self.file("literature.json")), let l = try? JSONDecoder.hf.decode(Literature.self, from: d) { literature = l }
    }

    private func save() {
        if let d = try? JSONEncoder.hf.encode(entries) { try? d.write(to: Self.file("bodylog.json"), options: .atomic) }
        if let d = try? JSONEncoder.hf.encode(literature) { try? d.write(to: Self.file("literature.json"), options: .atomic) }
    }

    func add(_ e: BodyEntry) { entries.append(e); entries.sort { $0.date > $1.date }; save() }
    func delete(_ e: BodyEntry) { entries.removeAll { $0.id == e.id }; save() }

    // Same rule as the dashboard's body tracker.
    var plans: [PartPlan] {
        let cutoff = Fmt.key(Calendar.current.date(byAdding: .day, value: -14, to: Date())!)
        var out: [PartPlan] = []
        for part in lib.parts {
            let es = entries.filter { $0.part == part.id }.sorted { $0.date > $1.date }
            guard let last = es.first, last.feel != Feel.Recovered.rawValue else { continue }
            if last.date < cutoff && last.severity <= 2 { continue }
            let status = (last.feel == "Pain" || last.feel == "Injury" || last.severity >= 3) ? "Active" : "Watching"
            let trend: String? = es.count > 1 ? (last.severity < es[1].severity ? "better" : last.severity > es[1].severity ? "worse" : "same") : nil
            let flags = last.symptoms.filter { Symptom.redFlags.contains($0) }
            let phase: Phase
            if !flags.isEmpty || last.feel == "Injury" || last.severity >= 5 { phase = .seeDoctor }
            else if last.feel == "Pain" || last.severity >= 4 { phase = .calm }
            else if last.feel == "Better" || last.severity <= 1 { phase = .return }
            else { phase = .build }
            let pick: [String] = switch phase {
                case .seeDoctor, .calm: ["calm"]
                case .build: ["calm", "build"]
                case .return: ["build", "return"]
            }
            var ex = part.exercises.filter { pick.contains($0.phase) }
            if ex.isEmpty { ex = Array(part.exercises.prefix(2)) }
            out.append(PartPlan(part: part, latest: last, status: status, trend: trend, phase: phase, redFlags: flags, exercises: ex))
        }
        let order: [Phase] = [.seeDoctor, .calm, .build, .return]
        return out.sorted { (order.firstIndex(of: $0.phase) ?? 0) < (order.firstIndex(of: $1.phase) ?? 0) }
    }

    /// Adds general recovery when the watch says you're under-recovered.
    func generalAdvice(_ d: Derived) -> String? { Self.generalAdviceText(d) }

    /// nil without athletedata (latestRecovery is nil then) or when the watch looks fine.
    nonisolated static func generalAdviceText(_ d: Derived) -> String? {
        guard let r = d.latestRecovery else { return nil }
        var why: [String] = []
        if let x = r.readiness, x < 45 { why.append("readiness \(Int(x))") }
        if let h = r.hrv, let b = r.hrvBase, b > 0, h / b < 0.88 { why.append("HRV below your usual") }
        if let s = r.sleepH, s < (r.sleepNeedH ?? 7.5) - 1 { why.append(String(format: "%.1fh sleep", s)) }
        return why.isEmpty ? nil : "Your watch shows " + why.joined(separator: ", ") + ". Keep today easy and use the general recovery options."
    }

    var literatureDue: Bool { literature.lastCheck.map { Date().timeIntervalSince($0) > Self.weekly } ?? true }

    /// Weekly PubMed check for every body part. First run looks back 2 years; after that, since the last check.
    func checkLiterature(force: Bool = false) async {
        guard force || literatureDue, !checking else { return }
        checking = true
        defer { checking = false }
        let since = literature.lastCheck.map { $0.addingTimeInterval(-86400) } ?? Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        var failed = false
        for part in lib.parts {
            do {
                let found = try await PubMed.search(part.pubmed, since: since)
                var list = literature.byPart[part.id] ?? []
                let known = Set(list.map(\.pmid)).union(lib.refs.map(\.pmid))
                list.insert(contentsOf: found.filter { !known.contains($0.pmid) }, at: 0)
                literature.byPart[part.id] = Array(list.prefix(12))
            } catch { failed = true }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        literature.error = failed ? "Some PubMed searches didn't finish; they'll retry next time." : nil
        if !failed { literature.lastCheck = Date() }
        save()
    }

    func newPapers(_ part: String) -> [Paper] {
        let since = Date().addingTimeInterval(-Self.weekly)
        return (literature.byPart[part] ?? []).filter { $0.foundAt > since }
    }
}
