import Foundation

/// Live forecast from Open-Meteo (free, no key).
enum Weather {
    private struct Response: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let apparent_temperature_min: [Double?]
            let precipitation_probability_max: [Double?]
            let wind_speed_10m_max: [Double?]
            let weather_code: [Int?]
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double?]
            let apparent_temperature: [Double?]
            let precipitation_probability: [Double?]
            let wind_speed_10m: [Double?]
            let weather_code: [Int?]
        }
        let daily: Daily
        let hourly: Hourly
    }

    /// Nil when no home is set yet (Settings > Home).
    static func fetch() async throws -> ([DayWeather], [HourWeather])? {
        let home = HomeSettings.current
        guard let lat = home.latitude, let lon = home.longitude else { return nil }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,apparent_temperature_min,precipitation_probability_max,wind_speed_10m_max,weather_code"),
            URLQueryItem(name: "hourly", value: "temperature_2m,apparent_temperature,precipitation_probability,wind_speed_10m,weather_code"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "timezone", value: AppConfig.timeZone.identifier),
            URLQueryItem(name: "forecast_days", value: "16"),
        ]
        let (data, resp) = try await URLSession.shared.data(from: c.url!)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw HFError.http("Weather", code) }
        let r = try JSONDecoder().decode(Response.self, from: data)
        let d = r.daily
        let days = d.time.indices.map { i in
            DayWeather(date: d.time[i], maxF: at(d.temperature_2m_max, i), minF: at(d.temperature_2m_min, i),
                       feelsMinF: at(d.apparent_temperature_min, i), precipProb: at(d.precipitation_probability_max, i),
                       windMph: at(d.wind_speed_10m_max, i), code: at(d.weather_code, i))
        }
        let h = r.hourly
        let hours = h.time.indices.compactMap { i -> HourWeather? in
            let hh = h.time[i].suffix(5)
            guard ["07:00", "08:00", "18:00"].contains(String(hh)) else { return nil }
            return HourWeather(time: h.time[i], tempF: at(h.temperature_2m, i), feelsF: at(h.apparent_temperature, i),
                               precipProb: at(h.precipitation_probability, i), windMph: at(h.wind_speed_10m, i), code: at(h.weather_code, i))
        }
        return (days, hours)
    }

    private static func at<T>(_ a: [T?], _ i: Int) -> T? { i < a.count ? a[i] : nil }

    /// Words and an SF Symbol for a WMO weather code.
    static func describe(_ code: Int?) -> (text: String, symbol: String) {
        switch code ?? -1 {
        case 0: return ("Clear", "sun.max.fill")
        case 1, 2: return ("Partly cloudy", "cloud.sun.fill")
        case 3: return ("Cloudy", "cloud.fill")
        case 45, 48: return ("Fog", "cloud.fog.fill")
        case 51, 53, 55, 56, 57: return ("Drizzle", "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67, 80, 81, 82: return ("Rain", "cloud.rain.fill")
        case 71, 73, 75, 77, 85, 86: return ("Snow", "cloud.snow.fill")
        case 95, 96, 99: return ("Storms", "cloud.bolt.rain.fill")
        default: return ("—", "questionmark.circle")
        }
    }

    /// Simple running-kit suggestion from the feels-like temperature.
    static func wear(feelsF: Double?, precip: Double?) -> String {
        guard let f = feelsF else { return "" }
        var s: String
        switch f {
        case ..<20: s = "Tights, thermal top, jacket, hat and gloves"
        case ..<32: s = "Tights, long sleeve plus jacket, hat and gloves"
        case ..<45: s = "Tights or shorts, long sleeve, light gloves"
        case ..<55: s = "Shorts and a long sleeve"
        case ..<70: s = "Shorts and a T-shirt"
        default: s = "Shorts, singlet, and bring water"
        }
        if (precip ?? 0) >= 50 { s += "; rain shell" }
        return s
    }
}
