import Foundation

/// Where the runner lives: used to tell when a flight or hotel means being away, and for the weather.
/// Nothing is built in; the runner sets it in Settings > Home.
struct HomeSettings: Codable, Equatable {
    var city: String            // e.g. "Columbus, OH"
    var airports: [String]      // e.g. ["CMH"]
    var latitude: Double?
    var longitude: Double?

    static let unset = HomeSettings(city: "", airports: [], latitude: nil, longitude: nil)

    /// True once a home city has been found, so the weather can be fetched.
    var hasLocation: Bool { latitude != nil && longitude != nil }

    /// The first part of the city, lowercased ("columbus").
    var cityKey: String {
        (city.split(separator: ",").first.map(String.init) ?? city).trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// True when a place, address or airport text is at home.
    func isHome(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        if !cityKey.isEmpty, t.lowercased().range(of: "\\b\(NSRegularExpression.escapedPattern(for: cityKey))\\b", options: .regularExpression) != nil { return true }
        for a in airports where a.count == 3 {
            if t.range(of: "\\b\(a.uppercased())\\b", options: .regularExpression) != nil { return true }
        }
        return false
    }

    /// "jfk, lga ,ewr" -> ["JFK", "LGA", "EWR"]
    static func parseAirports(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == " " }).map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { $0.count == 3 && $0.allSatisfy(\.isLetter) }
    }

    // MARK: Saved next to the snapshot, so the widgets see it too.
    private static var url: URL { Store.url.deletingLastPathComponent().appendingPathComponent("home.json") }

    static var current: HomeSettings {
        guard let d = try? Data(contentsOf: url), let h = try? JSONDecoder().decode(HomeSettings.self, from: d) else { return .unset }
        return h
    }

    static func save(_ h: HomeSettings) {
        if let d = try? JSONEncoder().encode(h) { try? d.write(to: url, options: .atomic) }
    }
}

/// Finds a city's coordinates with Open-Meteo's free geocoding (no key).
enum Geocoder {
    struct Place: Equatable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    static func parse(_ data: Data) throws -> [Place] {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HFError.parse("place search") }
        let results = o["results"] as? [[String: Any]] ?? []
        return results.compactMap { r in
            guard let n = r["name"] as? String, let la = (r["latitude"] as? NSNumber)?.doubleValue,
                  let lo = (r["longitude"] as? NSNumber)?.doubleValue else { return nil }
            let region = [r["admin1"] as? String, r["country_code"] as? String].compactMap { $0 }.joined(separator: ", ")
            return Place(name: region.isEmpty ? n : "\(n), \(region)", latitude: la, longitude: lo)
        }
    }

    static func search(_ city: String) async throws -> [Place] {
        let name = (city.split(separator: ",").first.map(String.init) ?? city).trimmingCharacters(in: .whitespaces)
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "10"),
                        URLQueryItem(name: "language", value: "en"), URLQueryItem(name: "format", value: "json")]
        let (data, resp) = try await URLSession.shared.data(from: c.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw HFError.http("Place search", (resp as? HTTPURLResponse)?.statusCode ?? 0) }
        var places = try parse(data)
        // "Columbus, OH": prefer results whose region mentions the part after the comma.
        if let hint = city.split(separator: ",").dropFirst().first?.trimmingCharacters(in: .whitespaces).lowercased(), !hint.isEmpty {
            places = places.filter { $0.name.lowercased().contains(hint) } + places.filter { !$0.name.lowercased().contains(hint) }
        }
        return places
    }
}
