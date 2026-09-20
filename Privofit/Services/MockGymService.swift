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
    func offers() async throws -> [MembershipOffer] { [.init(id: "demo-pass", name: L10n.tr("offer.name"), description: L10n.tr("offer.description"), priceDescription: L10n.tr("offer.price"))] }
    func visits() async throws -> [Visit] { try check(); return [.init(id: "demo-visit", date: Date().addingTimeInterval(-86400 * 2), room: "PRIVOFIT / 01")] }
    let appleConfigured = false
    var signedIn = false
    var accountStatus: AccountStatus = .active
    var simulateOffline = false
    var doorOutcome: DoorReceipt.Outcome = .confirmedOpen
    private var bookings: [Reservation] = []
    private var operations: [UUID: DoorReceipt] = [:]
    private var cachedSlots: [AvailableSlot] = (1...5).map { index in
        let start = Date().addingTimeInterval(Double(index) * 7200)
        return AvailableSlot(id: "demo-slot-\(index)", start: start, end: start.addingTimeInterval(3600), room: "PRIVOFIT / 01")
    }
    private func delay() async throws { try await Task.sleep(for: .milliseconds(300)); if simulateOffline { throw AppFailure.offline } }
    private func check() throws { guard signedIn else { throw AppFailure.unauthorized }; guard accountStatus == .active else { throw AppFailure.forbidden } }
    private var user: Member { .init(id: "demo-member", firstName: "Alex", username: "alex_demo", email: "alex@example.invalid", status: accountStatus) }
    func restore() async throws -> Member? { try await delay(); return signedIn ? user : nil }
    func login(_ input: LoginInput) async throws -> Member { try await delay(); signedIn = true; return user }
    func register(_ input: RegistrationInput) async throws -> Member { try await login(.init(identifier: input.email, password: input.password)) }
    func signInWithApple(_ credential: AppleCredential) async throws -> Member { throw AppFailure.notConfigured("Apple není simulován") }
    func logout() async { signedIn = false }
    func membership() async throws -> Membership { try check(); try await delay(); return .init(title: "Tvůj prostor", validUntil: Date().addingTimeInterval(86400 * 30), remainingEntries: 8, isActive: !inactiveMembership, validFrom: Date().addingTimeInterval(-86400 * 2), status: inactiveMembership ? .inactive : .active) }
    func reservations() async throws -> [Reservation] { try check(); return bookings }
    func availableSlots() async throws -> [AvailableSlot] { try check(); return cachedSlots.filter { slot in !bookings.contains(where: { $0.id == slot.id }) } }
    func reserve(slotID: String, requestID: UUID) async throws -> Reservation {
        try check(); try await delay()
        if let existing = bookings.first(where: { $0.id == slotID }) { return existing }
        guard let slot = cachedSlots.first(where: { $0.id == slotID }) else { throw AppFailure.unavailable }
        let reservation = Reservation(id: slot.id, start: slot.start, end: slot.end, room: slot.room, canCancel: true)
        bookings.append(reservation); return reservation
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
    func registerPush(token: String) async throws { try check() }
}
#endif
