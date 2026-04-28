import Foundation

/// Fetches KBO schedule data from Naver Sports' unofficial JSON endpoint.
/// Stateless — the ViewModel calls this on its polling cadence.
enum KBOService {
    /// Pretend to be Safari. The endpoint occasionally rejects bare
    /// URLSession requests with no User-Agent.
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Fetch all KBO games for the given date in Asia/Seoul.
    /// Returns an empty array on any error so callers can render a
    /// safe empty state.
    static func fetchGames(date: Date) async -> [KBOGame] {
        let dateString = Self.kboDateFormatter.string(from: date)
        var components = URLComponents(string: "https://api-gw.sports.naver.com/schedule/games")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "basic,baseball"),
            URLQueryItem(name: "upperCategoryId", value: "kbaseball"),
            URLQueryItem(name: "categoryId", value: "kbo"),
            URLQueryItem(name: "fromDate", value: dateString),
            URLQueryItem(name: "toDate", value: dateString),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            let decoded = try JSONDecoder().decode(KBOScheduleResponse.self, from: data)
            return decoded.result.games
        } catch {
            return []
        }
    }

    /// "Today" in the KBO timezone (Asia/Seoul). Using the user's local
    /// date here would be wrong for users west of Korea — they'd see
    /// yesterday's games during the morning.
    static func currentKBODate() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        return calendar.date(from: components) ?? Date()
    }

    private static let kboDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
