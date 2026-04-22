import Foundation

// Default coordinates: Prospect Lake, Saanich BC
private let defaultLat =  48.515
private let defaultLng = -123.408

struct WeatherData {
    struct Current {
        let temperatureC: Double
        let windspeedKmh: Double
        let weatherCode:  Int
    }
    struct HourForecast {
        let time:         String   // "HH:mm" local
        let temperatureC: Double
        let weatherCode:  Int
    }
    let current: Current
    let hourly:  [HourForecast]   // next 6 hours
}

// MARK: – Decoding
private struct OMResponse: Decodable {
    struct CurrentWeather: Decodable {
        let temperature: Double
        let windspeed:   Double
        let weathercode: Int
    }
    struct Hourly: Decodable {
        let time:          [String]
        let temperature_2m:[Double]
        let weathercode:   [Int]
    }
    let current_weather: CurrentWeather
    let hourly: Hourly
}

enum WeatherService {
    static func fetch(latitude: Double = defaultLat,
                      longitude: Double = defaultLng) async throws -> WeatherData {
        let urlString = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(latitude)"
            + "&longitude=\(longitude)"
            + "&current_weather=true"
            + "&hourly=temperature_2m,weathercode"
            + "&timezone=America%2FVancouver"
            + "&forecast_days=2"   // 2 days so next-6-hours works near midnight

        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded   = try JSONDecoder().decode(OMResponse.self, from: data)

        let current = WeatherData.Current(
            temperatureC: decoded.current_weather.temperature,
            windspeedKmh: decoded.current_weather.windspeed,
            weatherCode:  decoded.current_weather.weathercode
        )

        // Find the nearest hour index to now and take 6 slots
        let parseFmt = DateFormatter()
        parseFmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        parseFmt.timeZone   = TimeZone(identifier: "America/Vancouver")

        let dispFmt = DateFormatter()
        dispFmt.dateFormat = "HH:mm"
        dispFmt.timeZone   = TimeZone(identifier: "America/Vancouver")

        let now  = Date()
        let times = decoded.hourly.time.compactMap { parseFmt.date(from: $0) }

        // First slot at or after (now - 30 min) so we include the current partial hour
        let startIdx = times.firstIndex { $0 >= now.addingTimeInterval(-1800) } ?? 0
        let endIdx   = min(startIdx + 6, times.count)

        let hourly = (startIdx..<endIdx).map { i -> WeatherData.HourForecast in
            WeatherData.HourForecast(
                time:         dispFmt.string(from: times[i]),
                temperatureC: decoded.hourly.temperature_2m[i],
                weatherCode:  decoded.hourly.weathercode[i]
            )
        }

        return WeatherData(current: current, hourly: hourly)
    }

    // MARK: – Helpers
    static func description(for code: Int) -> String {
        switch code {
        case 0:       return "clear"
        case 1:       return "mainly clear"
        case 2:       return "partly cloudy"
        case 3:       return "overcast"
        case 45, 48:  return "fog"
        case 51...55: return "drizzle"
        case 61:      return "light rain"
        case 63:      return "rain"
        case 65:      return "heavy rain"
        case 71...75: return "snow"
        case 77:      return "snow grains"
        case 80...82: return "showers"
        case 85, 86:  return "snow showers"
        case 95:      return "thunderstorm"
        case 96, 99:  return "t-storm/hail"
        default:      return "—"
        }
    }

    static func sfSymbol(for code: Int) -> String {
        switch code {
        case 0:       return "sun.max"
        case 1:       return "sun.max"
        case 2:       return "cloud.sun"
        case 3:       return "cloud"
        case 45, 48:  return "cloud.fog"
        case 51...55: return "cloud.drizzle"
        case 61...65: return "cloud.rain"
        case 71...77: return "cloud.snow"
        case 80...82: return "cloud.rain"
        case 85, 86:  return "cloud.snow"
        case 95...99: return "cloud.bolt.rain"
        default:      return "questionmark.circle"
        }
    }
}
