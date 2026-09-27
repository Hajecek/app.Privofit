import Foundation
import AppIntents

enum WidgetPlace: String, Codable, Sendable {
    case session
    case reservations
    case streak
    case membership
    case dashboard
}

enum WidgetLink {
    static func url(_ place: WidgetPlace) -> URL {
        URL(string: "privofit://widget/\(place.rawValue)")!
    }

    static func place(from url: URL) -> WidgetPlace? {
        guard url.scheme == "privofit", url.host == "widget" else { return nil }
        let name = url.path.split(separator: "/").first.map(String.init) ?? ""
        return WidgetPlace(rawValue: name)
    }
}

extension Notification.Name {
    static let privofitWidgetOpen = Notification.Name("privofit.widget.open")
}

enum WidgetHandoff {
    static let key = "widget.handoff.v1"

    static func store(_ place: WidgetPlace) {
        UserDefaults(suiteName: WidgetStore.suiteName)?.set(place.rawValue, forKey: key)
    }

    static func consume() -> WidgetPlace? {
        guard let defaults = UserDefaults(suiteName: WidgetStore.suiteName),
              let raw = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return WidgetPlace(rawValue: raw)
    }
}

struct OpenPrivofitIntent: AppIntent {
    static let title: LocalizedStringResource = "widget.control.open"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "widget.control.place")
    var place: String

    init() {
        place = WidgetPlace.dashboard.rawValue
    }

    init(place: WidgetPlace) {
        self.place = place.rawValue
    }

    func perform() async throws -> some IntentResult {
        if let place = WidgetPlace(rawValue: place) {
            WidgetHandoff.store(place)
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .privofitWidgetOpen, object: nil)
        }
        return .result()
    }
}

enum WidgetClock {
    static let timeZone = TimeZone(identifier: "Europe/Prague") ?? .gmt
    static let locale = Locale(identifier: "cs_CZ")
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        calendar.firstWeekday = 2
        return calendar
    }

    static func format(_ date: Date, date dateStyle: Date.FormatStyle.DateStyle = .omitted, time timeStyle: Date.FormatStyle.TimeStyle = .shortened) -> String {
        var style = Date.FormatStyle(date: dateStyle, time: timeStyle).locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    static func week(containing date: Date, calendar: Calendar = calendar) -> [Date] {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        let first = calendar.date(byAdding: .day, value: -delta, to: start) ?? start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }.map { calendar.startOfDay(for: $0) }
    }

    static func weekdayLabels(calendar: Calendar = calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return (Array(symbols[start...]) + Array(symbols[..<start])).map { $0.uppercased() }
    }
}

struct WidgetSession: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var start: Date
    var end: Date
    var room: String
    var bufferMinutes: Int

    var occupiedUntil: Date {
        end.addingTimeInterval(TimeInterval(max(0, bufferMinutes) * 60))
    }

    func contains(_ date: Date) -> Bool {
        start <= date && occupiedUntil >= date
    }
}

struct WidgetDay: Codable, Equatable, Sendable, Identifiable {
    var date: Date
    var trained: Bool
    var planned: Bool
    var id: Date { date }
}

struct WidgetSnapshot: Codable, Equatable, Sendable {
    var updatedAt: Date
    var signedIn: Bool
    var membershipTitle: String
    var membershipActive: Bool
    var membershipStatus: String
    var validUntil: Date?
    var remainingEntries: Int?
    var streakLength: Int
    var streakAtRisk: Bool
    var todayTrained: Bool
    var week: [WidgetDay]
    var sessions: [WidgetSession]

    func current(at date: Date) -> WidgetSession? {
        sessions.first { $0.contains(date) }
    }

    func next(at date: Date) -> WidgetSession? {
        sessions.filter { $0.occupiedUntil > date }.min { $0.start < $1.start }
    }

    func focus(at date: Date) -> WidgetSession? {
        current(at: date) ?? next(at: date)
    }

    func upcoming(at date: Date, limit: Int) -> [WidgetSession] {
        Array(sessions.filter { $0.occupiedUntil > date }.sorted { $0.start < $1.start }.prefix(limit))
    }

    static var signedOut: WidgetSnapshot {
        WidgetSnapshot(
            updatedAt: .distantPast,
            signedIn: false,
            membershipTitle: "",
            membershipActive: false,
            membershipStatus: "inactive",
            validUntil: nil,
            remainingEntries: nil,
            streakLength: 0,
            streakAtRisk: false,
            todayTrained: false,
            week: [],
            sessions: []
        )
    }

    static var placeholder: WidgetSnapshot {
        let calendar = WidgetClock.calendar
        let now = Date()
        let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
        let start = evening > now ? evening : (calendar.date(byAdding: .day, value: 1, to: evening) ?? evening)
        let week = WidgetClock.week(containing: now).enumerated().map { index, day in
            WidgetDay(date: day, trained: index < 2, planned: index == 3)
        }
        return WidgetSnapshot(
            updatedAt: now,
            signedIn: true,
            membershipTitle: "PRIVOFIT",
            membershipActive: true,
            membershipStatus: "active",
            validUntil: calendar.date(byAdding: .day, value: 28, to: now),
            remainingEntries: 8,
            streakLength: 4,
            streakAtRisk: false,
            todayTrained: false,
            week: week,
            sessions: [
                WidgetSession(id: "preview", start: start, end: start.addingTimeInterval(60 * 60), room: "PRIVOFIT / 01", bufferMinutes: 15)
            ]
        )
    }
}

enum WidgetStore {
    static let suiteName = "group.cz.privofit.app"
    static let key = "widget.snapshot.v1"

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? encode(snapshot) else { return }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: key)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return try? decode(data)
    }

    static func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: key)
    }

    static func encode(_ snapshot: WidgetSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> WidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }
}

enum WidgetTimeline {
    static func dates(for snapshot: WidgetSnapshot, now: Date, calendar: Calendar = WidgetClock.calendar) -> [Date] {
        var points = [now]
        for session in snapshot.sessions {
            if session.start > now { points.append(session.start) }
            if session.occupiedUntil > now { points.append(session.occupiedUntil) }
        }
        if let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) {
            points.append(midnight)
        }
        let sorted = points.sorted()
        var unique: [Date] = []
        for date in sorted where date >= now.addingTimeInterval(-1) {
            if unique.last.map({ abs($0.timeIntervalSince(date)) < 1 }) != true {
                unique.append(date)
            }
        }
        return Array(unique.prefix(8))
    }

    static func refresh(after dates: [Date], now: Date) -> Date {
        let horizon = dates.filter { $0 > now }.max() ?? now.addingTimeInterval(60 * 60)
        let proposed = horizon.addingTimeInterval(60)
        let earliest = now.addingTimeInterval(15 * 60)
        let latest = now.addingTimeInterval(6 * 60 * 60)
        return min(max(proposed, earliest), latest)
    }
}
