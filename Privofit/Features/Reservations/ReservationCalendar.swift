import Foundation

enum GymClock {
    static let timeZone = TimeZone(identifier: "Europe/Prague") ?? .gmt
    static let locale = Locale(identifier: "cs_CZ")
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        calendar.firstWeekday = 2
        return calendar
    }
    static func occupancyEnd(_ end: Date, bufferMinutes: Int) -> Date {
        end.addingTimeInterval(TimeInterval(max(0, bufferMinutes) * 60))
    }
    static func format(_ date: Date, _ style: Date.FormatStyle) -> String {
        var style = style.locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

enum DayPart: String, CaseIterable, Sendable {
    case morning, afternoon, evening

    func contains(_ date: Date, calendar: Calendar = GymClock.calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        switch self {
        case .morning: return hour < 12
        case .afternoon: return hour >= 12 && hour < 17
        case .evening: return hour >= 17
        }
    }
}

struct CalendarDay: Equatable, Hashable, Sendable {
    var date: Date
    var inMonth: Bool
}

enum ReservationCalendar {
    static func startOfDay(_ date: Date, calendar: Calendar = GymClock.calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    static func week(containing date: Date, calendar: Calendar = GymClock.calendar) -> [Date] {
        let start = startOfDay(date, calendar: calendar)
        let weekday = calendar.component(.weekday, from: start)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        let first = calendar.date(byAdding: .day, value: -delta, to: start) ?? start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }.map { startOfDay($0, calendar: calendar) }
    }

    static func shiftWeek(_ date: Date, by weeks: Int, calendar: Calendar = GymClock.calendar) -> Date {
        calendar.date(byAdding: .weekOfYear, value: weeks, to: date) ?? date
    }

    static func monthStart(_ date: Date, calendar: Calendar = GymClock.calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components).map { startOfDay($0, calendar: calendar) } ?? startOfDay(date, calendar: calendar)
    }

    static func shiftMonth(_ date: Date, by months: Int, calendar: Calendar = GymClock.calendar) -> Date {
        calendar.date(byAdding: .month, value: months, to: monthStart(date, calendar: calendar)) ?? date
    }

    static func isCurrentMonth(_ date: Date, now: Date = Date(), calendar: Calendar = GymClock.calendar) -> Bool {
        calendar.isDate(date, equalTo: now, toGranularity: .month)
    }

    static func weekdaySymbols(calendar: Calendar = GymClock.calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...]) + Array(symbols[..<start])
    }

    static func monthGrid(containing date: Date, calendar: Calendar = GymClock.calendar) -> [CalendarDay] {
        let start = monthStart(date, calendar: calendar)
        let weekday = calendar.component(.weekday, from: start)
        let pad = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -pad, to: start) ?? start
        let daysInMonth = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let cells = (pad + daysInMonth) <= 35 ? 35 : 42
        return (0..<cells).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            return CalendarDay(
                date: startOfDay(day, calendar: calendar),
                inMonth: calendar.isDate(day, equalTo: start, toGranularity: .month)
            )
        }
    }

    static func groupedByDay(_ items: [Reservation], descending: Bool = false, calendar: Calendar = GymClock.calendar) -> [(Date, [Reservation])] {
        let groups = Dictionary(grouping: items) { startOfDay($0.start, calendar: calendar) }
        let keys = descending ? groups.keys.sorted(by: >) : groups.keys.sorted()
        return keys.map { day in (day, groups[day]!.sorted { $0.start < $1.start }) }
    }

    static func groupedSlots(_ slots: [AvailableSlot], calendar: Calendar = GymClock.calendar) -> [(Date, [AvailableSlot])] {
        Dictionary(grouping: slots) { startOfDay($0.start, calendar: calendar) }
            .sorted { $0.key < $1.key }
            .map { day, items in (day, items.sorted { $0.start < $1.start }) }
    }

    static func uniqueRooms(_ slots: [AvailableSlot]) -> [String] {
        Array(Set(slots.map(\.room))).sorted()
    }

    static func totalMinutes(_ slots: [AvailableSlot]) -> Int {
        slots.reduce(0) { $0 + durationMinutes(from: $1.start, to: $1.end) }
    }

    static func timeRange(_ start: Date, _ end: Date) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(GymClock.format(start, style)) – \(GymClock.format(end, style))"
    }
    static func occupiedRange(_ start: Date, _ end: Date, bufferMinutes: Int) -> String {
        timeRange(start, GymClock.occupancyEnd(end, bufferMinutes: bufferMinutes))
    }
    static func bookingDetail(room: String, price: Decimal?, currency: String = "CZK") -> String {
        if let label = GymMoney.label(price, code: currency) { return "\(room) · \(label)" }
        return room
    }

    static func isPastDay(_ date: Date, now: Date = Date(), calendar: Calendar = GymClock.calendar) -> Bool {
        startOfDay(date, calendar: calendar) < startOfDay(now, calendar: calendar)
    }

    static func slots(on day: Date, from slots: [AvailableSlot], calendar: Calendar = GymClock.calendar) -> [AvailableSlot] {
        slots.filter { calendar.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
    }

    static func reservations(on day: Date, from items: [Reservation], calendar: Calendar = GymClock.calendar) -> [Reservation] {
        items.filter { calendar.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
    }

    static func upcoming(_ items: [Reservation], now: Date = Date()) -> [Reservation] {
        items.filter { $0.occupiedUntil > now }.sorted { $0.start < $1.start }
    }

    static func past(_ items: [Reservation], now: Date = Date()) -> [Reservation] {
        items.filter { $0.occupiedUntil <= now }.sorted { $0.start > $1.start }
    }

    static func next(_ items: [Reservation], now: Date = Date()) -> Reservation? {
        upcoming(items, now: now).first
    }

    static func current(_ items: [Reservation], now: Date = Date()) -> Reservation? {
        items.first { $0.start <= now && $0.occupiedUntil >= now }
    }

    static func overlaps(_ slot: AvailableSlot, with items: [Reservation]) -> Bool {
        items.contains { $0.start < slot.occupiedUntil && slot.start < $0.occupiedUntil }
    }

    static func overlaps(_ slot: AvailableSlot, with slots: [AvailableSlot]) -> Bool {
        slots.contains { $0.id != slot.id && $0.start < slot.occupiedUntil && slot.start < $0.occupiedUntil }
    }

    static func conflicts(_ slot: AvailableSlot, reservations: [Reservation], cart: [AvailableSlot]) -> Bool {
        overlaps(slot, with: reservations) || overlaps(slot, with: cart)
    }

    static func groupedByDayPart(_ slots: [AvailableSlot], calendar: Calendar = GymClock.calendar) -> [(DayPart, [AvailableSlot])] {
        DayPart.allCases.compactMap { part in
            let items = slots.filter { part.contains($0.start, calendar: calendar) }
            return items.isEmpty ? nil : (part, items)
        }
    }

    static func hasAvailability(_ slots: [AvailableSlot], on day: Date, calendar: Calendar = GymClock.calendar) -> Bool {
        slots.contains { calendar.isDate($0.start, inSameDayAs: day) }
    }

    static func hasReservation(_ items: [Reservation], on day: Date, calendar: Calendar = GymClock.calendar) -> Bool {
        items.contains { calendar.isDate($0.start, inSameDayAs: day) }
    }

    static func hasSelection(_ slots: [AvailableSlot], on day: Date, calendar: Calendar = GymClock.calendar) -> Bool {
        slots.contains { calendar.isDate($0.start, inSameDayAs: day) }
    }

    static func durationMinutes(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start) / 60))
    }

    static func clampedDay(_ date: Date, now: Date = Date(), calendar: Calendar = GymClock.calendar) -> Date {
        max(startOfDay(date, calendar: calendar), startOfDay(now, calendar: calendar))
    }
}
