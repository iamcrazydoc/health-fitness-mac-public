import Foundation

/// Watch recovery data (readiness, sleep, HRV, resting HR, steps) from athletedata's MCP endpoint,
/// using your own athletedata API key. Optional: the app works without it.
enum Athletedata {
    static var isConfigured: Bool { Keychain.get(.adpURL) != nil && Keychain.get(.adpKey) != nil }

    static func recovery(days: Int = 30) async throws -> [RecoveryDay] {
        guard let urlString = Keychain.get(.adpURL), let url = URL(string: urlString), let key = Keychain.get(.adpKey) else {
            throw HFError.notConfigured("athletedata")
        }
        var session: String?
        _ = try await rpc(url, key, &session, method: "initialize", id: 1, params: [
            "protocolVersion": "2025-03-26",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "HealthFitnessMac", "version": "1.0"],
        ])
        _ = try? await rpc(url, key, &session, method: "notifications/initialized", id: nil, params: nil)
        var rows: [[String: Any]] = []
        var cursor: String?
        var guardCount = 0
        repeat {
            var args: [String: Any] = ["days": days]
            if let cursor { args["cursor"] = cursor }
            let result = try await rpc(url, key, &session, method: "tools/call", id: 2 + guardCount, params: ["name": "get_daily_metrics", "arguments": args])
            let page = try payload(from: result)
            rows += (page["rows"] as? [[String: Any]]) ?? []
            cursor = page["next_cursor"] as? String
            guardCount += 1
        } while cursor != nil && guardCount < 4

        var seen = Set<String>()
        var out: [RecoveryDay] = []
        for r in rows {
            guard let date = r["date"] as? String, !seen.contains(date) else { continue }
            seen.insert(date)
            func num(_ k: String) -> Double? { (r[k] as? NSNumber)?.doubleValue }
            out.append(RecoveryDay(
                date: date,
                readiness: num("readinessScoreV2"),
                verdict: r["readinessVerdict"] as? String,
                sleepH: num("sleepDurationMin").map { ($0 / 6).rounded() / 10 },
                sleepNeedH: num("sleepNeedMin").map { ($0 / 6).rounded() / 10 },
                hrv: num("hrv"),
                hrvBase: num("hrvBaseline60d").map { $0.rounded() },
                restingHR: num("restingHr"),
                steps: num("steps")))
        }
        return out.sorted { $0.date < $1.date }
    }

    /// One JSON-RPC call over MCP Streamable HTTP. Handles both JSON and event-stream answers.
    private static func rpc(_ url: URL, _ key: String, _ session: inout String?, method: String, id: Int?, params: [String: Any]?) async throws -> [String: Any] {
        var body: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let id { body["id"] = id }
        if let params { body["params"] = params }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let session { req.setValue(session, forHTTPHeaderField: "Mcp-Session-Id") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw HFError.http("athletedata", code) }
        if let s = http?.value(forHTTPHeaderField: "Mcp-Session-Id") { session = s }
        if id == nil || data.isEmpty { return [:] }
        let text = String(decoding: data, as: UTF8.self)
        var candidates: [String] = []
        if (http?.value(forHTTPHeaderField: "Content-Type") ?? "").contains("event-stream") || text.hasPrefix("event:") || text.hasPrefix("data:") {
            candidates = text.split(separator: "\n").filter { $0.hasPrefix("data:") }.map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        } else {
            candidates = [text]
        }
        for c in candidates.reversed() {
            if let obj = try? JSONSerialization.jsonObject(with: Data(c.utf8)) as? [String: Any], obj["id"] != nil {
                if let err = obj["error"] as? [String: Any] { throw HFError.parse("athletedata (\(err["message"] as? String ?? "error"))") }
                return (obj["result"] as? [String: Any]) ?? [:]
            }
        }
        throw HFError.parse("athletedata")
    }

    /// The tool answers with text: a short preamble, then a JSON object.
    private static func payload(from result: [String: Any]) throws -> [String: Any] {
        if let sc = result["structuredContent"] as? [String: Any], sc["rows"] != nil { return sc }
        let text = ((result["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined()
        guard let r = text.range(of: "{\"") else { throw HFError.parse("athletedata") }
        let json = String(text[r.lowerBound...])
        guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { throw HFError.parse("athletedata") }
        if let e = obj["error"] { throw HFError.parse("athletedata (\(e))") }
        return obj
    }
}
