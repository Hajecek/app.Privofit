import ActivityKit
import Foundation

struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var room: String
        var start: Date
        var end: Date
        var bufferMinutes: Int
        var guestCount: Int

        var occupiedUntil: Date {
            end.addingTimeInterval(TimeInterval(max(0, bufferMinutes) * 60))
        }

        var windowStart: Date {
            start.addingTimeInterval(-SessionActivityTiming.lead)
        }

        func countdownInterval(at now: Date) -> ClosedRange<Date>? {
            let upper = now < start ? start : occupiedUntil
            let lower = now < start ? windowStart : start
            guard lower < upper else { return nil }
            return lower...upper
        }

        func progressInterval() -> ClosedRange<Date>? {
            guard start < occupiedUntil else { return nil }
            return start...occupiedUntil
        }

        /// Další hranice, na které má systém aktivitu překreslit. Odpočet sám běží přes systémový timer.
        func staleDate(at now: Date) -> Date? {
            if now < start { return start }
            if now < occupiedUntil { return occupiedUntil }
            return nil
        }

        func relevance(at now: Date) -> Double {
            if start <= now, now < occupiedUntil { return 100 }
            if windowStart <= now, now < start { return 80 }
            return 40
        }
    }

    var reservationID: String
}

enum SessionActivityTiming {
    /// Aktivita se ukáže půl hodiny před začátkem, aby byla na zámku cestou do fitka.
    static let lead: TimeInterval = 30 * 60
    /// Po jednom otevření aplikace se naplánují termíny v tomto okně.
    static let horizon: TimeInterval = 7 * 24 * 60 * 60
    static let upcomingLimit = 4

    static var timeZone: TimeZone { TimeZone(identifier: "Europe/Prague") ?? .gmt }

    static func range(from start: Date, to end: Date) -> String {
        "\(clock(start)) – \(clock(end))"
    }

    static func clock(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "cs_CZ"))
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

enum SessionActivityLink {
    static func url(for reservationID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "privofit"
        components.host = "reservation"
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let token = reservationID.addingPercentEncoding(withAllowedCharacters: allowed) ?? reservationID
        components.path = "/" + token
        return components.url
    }

    static func reservationID(from url: URL) -> String? {
        guard url.scheme == "privofit", url.host == "reservation" else { return nil }
        let token = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !token.isEmpty, let decoded = token.removingPercentEncoding, !decoded.isEmpty else { return nil }
        return decoded
    }
}
