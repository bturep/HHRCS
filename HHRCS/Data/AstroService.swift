import Foundation

struct AstroData {
    let civilDawn: Date
    let sunrise:   Date
    let sunset:    Date
    let civilDusk: Date
}

private struct SunResponse: Decodable {
    struct Results: Decodable {
        let sunrise:              String
        let sunset:               String
        let civil_twilight_begin: String
        let civil_twilight_end:   String
    }
    let results: Results
    let status:  String
}

enum AstroService {
    static func fetch(latitude:  Double = 48.515,
                      longitude: Double = -123.408,
                      date:      Date   = Date()) async throws -> AstroData {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.timeZone   = TimeZone(identifier: "America/Vancouver")
        let dateStr = dateFmt.string(from: date)

        let urlString = "https://api.sunrise-sunset.org/json"
            + "?lat=\(latitude)&lng=\(longitude)"
            + "&formatted=0"
            + "&date=\(dateStr)"

        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded   = try JSONDecoder().decode(SunResponse.self, from: data)
        guard decoded.status == "OK" else { throw URLError(.badServerResponse) }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parse(_ s: String) -> Date {
            if let d = iso.date(from: s) { return d }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: s) ?? Date()
        }

        return AstroData(
            civilDawn: parse(decoded.results.civil_twilight_begin),
            sunrise:   parse(decoded.results.sunrise),
            sunset:    parse(decoded.results.sunset),
            civilDusk: parse(decoded.results.civil_twilight_end)
        )
    }

    static func format(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone   = TimeZone(identifier: "America/Vancouver")
        return fmt.string(from: date)
    }
}
