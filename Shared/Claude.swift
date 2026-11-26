import Foundation

/// Working with Claude: a summary of the runner's data, ready-made asks for claude.ai,
/// and a small client for the optional in-app chat (the runner's own Anthropic API key).
enum ClaudeAsk: String, CaseIterable, Identifiable {
    case insights, plan, recovery, dashboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .insights: return "Insights"
        case .plan: return "Make or change my plan"
        case .recovery: return "Recovery help"
        case .dashboard: return "Make my dashboard"
        }
    }

    var symbol: String {
        switch self {
        case .insights: return "lightbulb"
        case .plan: return "calendar.badge.plus"
        case .recovery: return "cross.case"
        case .dashboard: return "rectangle.3.group"
        }
    }

    var blurb: String {
        switch self {
        case .insights: return "What your runs, recovery and plan say, and one thing to change this week."
        case .plan: return "Build a plan or change it. With Claude's Google Calendar connector, it can add or move the runs this app shows."
        case .recovery: return "Talk through how your body feels, with cited exercises and when to get checked."
        case .dashboard: return "Start a live dashboard in Claude like the one this app was built beside, from Strava, your watch and your calendar."
        }
    }

    /// What to ask Claude. The data summary follows it.
    var prompt: String {
        switch self {
        case .insights:
            return """
            Act as my running coach. Below is my data from my Mac training app. Give me 3 to 5 short insights about \
            my training, recovery and progress toward my goal, then one specific thing to change this week. \
            Say which numbers you used, and say when something is a guess.
            """
        case .plan:
            return """
            Help me make or change my training plan for the goal below. Ask what you need first (days I can run, \
            how many runs a week, other training). If you can reach my Google Calendar, put each run in as an \
            all-day event whose title starts with 🏃 (or 🏁 for a race) and includes the distance, like \
            "🏃 Long run · 6 mi", with the session details and target pace in the description. My Mac app reads \
            those events. Show me the changes and ask before you add, move or delete anything.
            """
        case .recovery:
            return """
            Help me with recovery. Below are my recent body check-ins, runs and watch data. Suggest what to do this \
            week, with exercises backed by published research (give PubMed IDs or DOIs, and only real ones). \
            Tell me plainly if anything I describe should be checked by a doctor or physio before I keep running.
            """
        case .dashboard:
            return """
            Build me a live training dashboard as an artifact, using my own connected data:
            - Strava (connector): runs, best efforts, predicted half marathon time against my goal.
            - My watch data if a connector is available (for example athletedata): sleep, HRV, resting heart rate, readiness, steps.
            - Google Calendar (connector): my plan as all-day events titled with 🏃 (runs) or 🏁 (races) plus the distance, \
            and trips found from flights, hotel stays and events with trip or travel in the title.
            - Weather for my next runs from Open-Meteo, for my home city.
            Sections: an overview, a month training calendar, weekly miles (run vs planned), predicted half vs goal, \
            sleep and recovery, races, travel dates that move runs, and a body check-in form saved in the artifact. \
            Use miles, min/mi, °F and mph. Use my goal, race and home from the data below. Keep the plan in Google \
            Calendar in that event format so my Mac app shows the same plan. Ask me before writing to my calendar.
            """
        }
    }
}

enum ClaudeContext {
    /// A plain-text summary of the runner's data for Claude. `bodyNotes` are check-ins from the Recovery tab.
    static func summary(_ d: Derived, bodyNotes: [String] = [], home: HomeSettings = .current) -> String {
        var out: [String] = ["# My training data (from my Mac app, \(Fmt.key(Date())))"]
        let p = d.profile
        var goal: [String] = []
        if let g = p.goalHalfSeconds { goal.append("Half marathon goal: \(Fmt.hms(g))") }
        if let r = p.raceDate { goal.append("\(p.raceTitle) on \(r)" + (d.daysToRace.map { " (\($0) days away)" } ?? "")) }
        if let pr = d.predicted { goal.append("Predicted half now: \(Fmt.hms(pr))") }
        if let b = d.bestHalf { goal.append("Best half: \(Fmt.hms(b))") }
        if !home.city.isEmpty { goal.append("Home: \(home.city)" + (home.airports.isEmpty ? "" : " (airports \(home.airports.joined(separator: ", ")))")) }
        out.append("## Goal\n" + (goal.isEmpty ? "- Not set yet" : goal.map { "- " + $0 }.joined(separator: "\n")))

        let from = TrainingMath.add(d.todayKey, -42)
        let recent = d.snap.runs.filter { $0.date >= from }.sorted { $0.date > $1.date }
        let runLines = recent.prefix(30).map { r in
            "- \(r.date): \(Fmt.miles(r.miles)) mi at \(Fmt.pace(r.paceSecPerMile))" + (r.avgHR.map { ", avg HR \(Int($0))" } ?? "")
                + (r.outdoor ? "" : ", indoor") + " (\(r.name))"
        }
        out.append("## Runs, last 6 weeks (Strava)\n" + (runLines.isEmpty ? "- None" : runLines.joined(separator: "\n")))

        let until = TrainingMath.add(d.todayKey, 28)
        let plan = d.fullPlan.filter { $0.date >= TrainingMath.add(d.todayKey, -7) && $0.date <= until }
        let planLines = plan.map { "- \($0.date): \($0.title)" + ($0.notes.isEmpty ? "" : " (\($0.notes.replacingOccurrences(of: "\n", with: "; ")))") }
        out.append("## Plan, last week to 4 weeks ahead (calendar)\n" + (planLines.isEmpty ? "- No planned runs in the calendar" : planLines.joined(separator: "\n")))

        let trips = d.upcomingTrips.map { "- \($0.start) to \($0.end): \($0.place), \($0.modeText)" }
        if !trips.isEmpty { out.append("## Trips\n" + trips.joined(separator: "\n")) }

        if d.hasWatchData {
            let days = d.snap.recovery.sorted { $0.date > $1.date }.prefix(7).map { r -> String in
                var parts: [String] = []
                if let v = r.readiness { parts.append("readiness \(Int(v))") }
                if let v = r.sleepH { parts.append(String(format: "sleep %.1f h", v)) }
                if let v = r.hrv { parts.append("HRV \(Int(v))" + (r.hrvBase.map { " (usual \(Int($0)))" } ?? "")) }
                if let v = r.restingHR { parts.append("resting HR \(Int(v))") }
                if let v = r.steps { parts.append("\(Int(v)) steps") }
                return "- \(r.date): " + (parts.isEmpty ? "no data" : parts.joined(separator: ", "))
            }
            out.append("## Watch, last 7 days\n" + (days.isEmpty ? "- None" : days.joined(separator: "\n")))
        }
        if !bodyNotes.isEmpty { out.append("## Body check-ins, last 30 days\n" + bodyNotes.map { "- " + $0 }.joined(separator: "\n")) }
        return out.joined(separator: "\n\n")
    }

    /// The text to paste into Claude: the ask, an optional question, then the data.
    static func handoff(_ ask: ClaudeAsk?, question: String, summary: String) -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = [ask?.prompt, q.isEmpty ? nil : "My question: \(q)"].compactMap { $0 }.joined(separator: "\n\n")
        return (head.isEmpty ? "" : head + "\n\n") + summary
    }

    static let newChatURL = URL(string: "https://claude.ai/new")!
}

/// The optional in-app chat: the Messages API with the runner's own API key (from the keychain).
enum ClaudeChat {
    static let model = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static var isConfigured: Bool { Keychain.get(.anthropicKey) != nil }

    static let instructions = """
    You are a running coach and training assistant inside a Mac app for half marathon training. \
    The runner's data is below, as of when this chat started. Use it, say which numbers you used, and say when \
    something is a guess. Use miles, min/mi, °F and mph. Keep answers short and practical. \
    You can't change the runner's calendar or watch from this chat. When they want plan changes, write the \
    changed runs as a list of all-day calendar events, each titled with 🏃 (or 🏁 for a race) and the distance, \
    like "🏃 Long run · 6 mi", and tell them to press "Continue in Claude" to have them added with Claude's \
    Google Calendar connector. For recovery, only cite research you're sure exists, and tell them plainly \
    when a symptom needs a doctor or physio.
    """

    /// One turn. `content` is the API's content array, kept as is so it can be sent back unchanged.
    struct Turn: Identifiable {
        let id = UUID()
        let role: String          // "user" | "assistant"
        let content: [[String: Any]]
        var text: String {
            content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n\n")
        }
        static func user(_ s: String) -> Turn { Turn(role: "user", content: [["type": "text", "text": s]]) }
    }

    enum ChatError: LocalizedError {
        case noKey, http(Int, String), refused(String), parse
        var errorDescription: String? {
            switch self {
            case .noKey: return "Add your Anthropic API key in Settings > Claude."
            case .http(401, _): return "The API key wasn't accepted. Check it in Settings > Claude."
            case .http(429, _): return "Claude is busy or your usage limit was reached. Try again in a minute."
            case .http(let c, let m): return "Claude answered with error \(c)" + (m.isEmpty ? "." : ": \(m)")
            case .refused(let why): return "Claude declined this one" + (why.isEmpty ? "." : ": \(why)")
            case .parse: return "Couldn't read Claude's answer."
            }
        }
    }

    /// The request body for one call (tested).
    static func body(context: String, turns: [Turn]) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 16000,
            "system": [["type": "text", "text": instructions + "\n\n<runner_data>\n" + context + "\n</runner_data>",
                        "cache_control": ["type": "ephemeral"]]],
            "output_config": ["effort": "medium"],
            "fallbacks": "default",
            "messages": turns.map { ["role": $0.role, "content": $0.content] },
        ]
    }

    /// Reads a Messages API response into the assistant turn (tested).
    static func parse(_ data: Data) throws -> Turn {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else { throw ChatError.parse }
        if obj["stop_reason"] as? String == "refusal" {
            let details = obj["stop_details"] as? [String: Any]
            throw ChatError.refused(details?["explanation"] as? String ?? "")
        }
        return Turn(role: "assistant", content: content)
    }

    static func send(context: String, turns: [Turn]) async throws -> Turn {
        guard let key = Keychain.get(.anthropicKey) else { throw ChatError.noKey }
        var req = URLRequest(url: endpoint, timeoutInterval: 180)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body(context: context, turns: turns))
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?["message"] as? String ?? ""
            throw ChatError.http(code, msg)
        }
        return try parse(data)
    }
}
