#if DEBUG
import Foundation

// Compiled out of Release. Selected only by the Demo scheme, unconfigured Debug builds, or previews/tests.
@MainActor final class MockGymService: GymService {
    let isDemo = true
    let googleConfigured = false
    var openCount = 0
    var accessAllowed = true
    var inactiveMembership = false
    func signInWithGoogle(_ credential: GoogleCredential) async throws -> Member { throw AppFailure.notConfigured("Google") }
    func requestPasswordReset(identifier: String) async throws { try await delay() }
    func changePassword(current: String, new: String) async throws { try check(); try await delay() }
    func deleteAccount() async throws { try check(); try await delay(); signedIn = false; bookings = [] }
    func gymInfo() async throws -> GymInfo { .init(name: "PRIVOFIT", description: L10n.tr("gym.demo.description"), openingHours: L10n.tr("gym.demo.hours"), announcements: [L10n.tr("demo.notice")]) }
    func liveRevision() async throws -> String { "demo" }
    func offers() async throws -> [MembershipOffer] { [.init(id: "demo-pass", name: L10n.tr("offer.name"), description: L10n.tr("offer.description"), priceDescription: L10n.tr("offer.price"))] }
    func visits() async throws -> [Visit] {
        try check()
        let calendar = GymClock.calendar
        let today = calendar.startOfDay(for: Date())
        return (1...4).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let date = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
            return Visit(id: "demo-visit-\(offset)", date: date, room: "PRIVOFIT / 01")
        }
    }
    let appleConfigured = false
    var signedIn = false
    var accountStatus: AccountStatus = .active
    var simulateOffline = false
    var doorOutcome: DoorReceipt.Outcome = .confirmedOpen
    var checkoutCount = 0
    private var bookings: [Reservation] = []
    private var operations: [UUID: DoorReceipt] = [:]
    private var checkouts: [UUID: BookingPayment] = [:]
    private var cachedSlots: [AvailableSlot] = MockGymService.demoSlots()
    static func demoSlots(now: Date = Date(), calendar: Calendar = GymClock.calendar) -> [AvailableSlot] {
        let hours = [6, 8, 10, 12, 16, 17, 18, 19]
        let today = calendar.startOfDay(for: now)
        let stamp = DateFormatter()
        stamp.calendar = calendar
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = calendar.timeZone
        stamp.dateFormat = "yyyyMMddHH"
        return places.flatMap { place in
            (0..<14).flatMap { offset -> [AvailableSlot] in
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
                if calendar.component(.weekday, from: day) == 1 { return [] }
                return hours.compactMap { hour in
                    if calendar.component(.weekday, from: day) == 7, hour >= 17 { return nil }
                    guard let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                          start > now else { return nil }
                    return AvailableSlot(
                        id: "demo-slot-\(place.id)-\(stamp.string(from: start))",
                        start: start,
                        end: start.addingTimeInterval(3600),
                        room: place.name,
                        price: 350,
                        gymID: place.id
                    )
                }
            }
        }
    }
    private func delay() async throws { try await Task.sleep(for: .milliseconds(300)); if simulateOffline { throw AppFailure.offline } }
    private func check() throws { guard signedIn else { throw AppFailure.unauthorized }; guard accountStatus == .active else { throw AppFailure.forbidden } }
    private var user: Member { .init(id: "demo-member", firstName: "Alex", username: "alex_demo", email: "alex@example.invalid", status: accountStatus) }
    func restore() async throws -> Member? { try await delay(); return signedIn ? user : nil }
    func login(_ input: LoginInput) async throws -> Member { try await delay(); signedIn = true; return user }
    func register(_ input: RegistrationInput) async throws -> Member { try await login(.init(identifier: input.email, password: input.password)) }
    func uploadAvatar(_ jpeg: Data) async throws { try await delay() }
    func signInWithApple(_ credential: AppleCredential) async throws -> Member { throw AppFailure.notConfigured("Apple není simulován") }
    func logout() async { signedIn = false }
    func membership() async throws -> Membership { try check(); try await delay(); return currentMembership() }
    func membershipPass() async throws -> Data { try check(); try await delay(); return try WalletPassArchive.make(member: user, membership: currentMembership()) }
    private func currentMembership() -> Membership {
        .init(title: "Tvůj prostor", validUntil: Date().addingTimeInterval(86400 * 30), remainingEntries: 8, isActive: !inactiveMembership, validFrom: Date().addingTimeInterval(-86400 * 2), status: inactiveMembership ? .inactive : .active)
    }
    func reservations() async throws -> [Reservation] { try check(); return bookings }
    func gyms() async throws -> [GymPlace] { Self.places }
    func availableSlots(gymID: String) async throws -> [AvailableSlot] {
        try check()
        return cachedSlots.filter { slot in slot.gymID == gymID && !bookings.contains(where: { $0.id == slot.id }) }
    }
    static let places: [GymPlace] = [
        .init(id: "vinohrady", name: "PRIVOFIT Vinohrady", address: "Vinohradská 12, Praha", latitude: 50.0755, longitude: 14.4378),
        .init(id: "karlin", name: "PRIVOFIT Karlín", address: "Sokolovská 80, Praha", latitude: 50.0930, longitude: 14.4490),
        .init(id: "smichov", name: "PRIVOFIT Smíchov", address: "Nádražní 20, Praha", latitude: 50.0702, longitude: 14.4048)
    ]
    func reserve(slotID: String, requestID: UUID) async throws -> Reservation {
        try check(); try await delay()
        if let existing = bookings.first(where: { $0.id == slotID }) { return existing }
        guard let slot = cachedSlots.first(where: { $0.id == slotID }) else { throw AppFailure.unavailable }
        let reservation = Reservation(id: slot.id, start: slot.start, end: slot.end, room: slot.room, canCancel: true, bufferMinutes: slot.bufferMinutes, price: slot.price, currencyCode: slot.currencyCode)
        bookings.append(reservation); return reservation
    }
    func quoteReservations(slotIDs: [String]) async throws -> BookingQuote {
        try check(); try await delay()
        let chosen = try resolvedSlots(slotIDs)
        return BookingQuote(slots: chosen, pricePerSlot: 350, currencyCode: "CZK", total: 350 * Decimal(chosen.count))
    }
    func payAndReserve(slotIDs: [String], requestID: UUID, applePay: ApplePayToken) async throws -> BookingPayment {
        try check(); try await delay()
        guard !applePay.transactionIdentifier.isEmpty else { throw AppFailure.unavailable }
        if let previous = checkouts[requestID] { return previous }
        checkoutCount += 1
        var reserved: [Reservation] = []
        for id in slotIDs {
            reserved.append(try await reserve(slotID: id, requestID: requestID))
        }
        let payment = BookingPayment(id: requestID.uuidString, status: .paid, checkoutURL: nil, reservations: reserved)
        checkouts[requestID] = payment
        return payment
    }
    private func resolvedSlots(_ slotIDs: [String]) throws -> [AvailableSlot] {
        guard !slotIDs.isEmpty else { throw AppFailure.unavailable }
        let chosen = slotIDs.compactMap { id in cachedSlots.first(where: { $0.id == id }) }
        guard chosen.count == slotIDs.count else { throw AppFailure.unavailable }
        return chosen.sorted { $0.start < $1.start }
    }
    func cancelReservation(id: String, requestID: UUID) async throws { try check(); try await delay(); bookings.removeAll { $0.id == id } }
    func inbox() async throws -> [InboxItem] { try check(); return [.init(id: "demo-welcome", title: "Vítej ve svém", body: "Toto je vývojová ukázka. Žádná skutečná rezervace ani vstup nevzniká.", date: Date())] }
    func eligibility() async throws -> DoorEligibility { try check(); try await delay(); return .init(allowed: accessAllowed, reason: accessAllowed ? nil : L10n.tr("door.denied"), doorID: "demo-door", expiresAt: Date().addingTimeInterval(30)) }
    func openDoor(doorID: String, requestID: UUID) async throws -> DoorReceipt {
        try check(); try await delay()
        if let previous = operations[requestID] { return previous }
        openCount += 1
        let value = DoorReceipt(operationID: requestID.uuidString, outcome: doorOutcome, message: "Vývojová simulace")
        operations[requestID] = value; return value
    }
    func doorStatus(requestID: UUID, operationID: String?) async throws -> DoorReceipt {
        try check(); guard let result = operations[requestID] else { throw AppFailure.unavailable }; return result
    }
    func registerPush(token: String, preferences: PushNotificationPreferences) async throws { try check() }
}
#endif
