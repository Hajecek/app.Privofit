import Foundation

@MainActor final class LiveGymService: GymService {
    let isDemo = false
    var googleConfigured: Bool { contract.googleEnabled && Configuration.googleClientID != nil && Configuration.googleRedirect != nil }
    func signInWithGoogle(_ credential: GoogleCredential) async throws -> Member { try await authenticate(contract.google(credential)) }
    func requestPasswordReset(identifier: String) async throws { _ = try await http.send(contract.resetPassword(identifier)) }
    func changePassword(current: String, new: String) async throws { _ = try await authorized.send(contract.changePassword(current: current, new: new)) }
    func deleteAccount() async throws { _ = try await authorized.send(contract.deleteAccount()); await authorized.clear() }
    func gymInfo() async throws -> GymInfo { try await http.send(contract.gymInfo()) }
    func liveRevision() async throws -> String { try await http.send(contract.live()).revision }
    func offers() async throws -> [MembershipOffer] { try await http.send(contract.offers()) }
    func gyms() async throws -> [GymPlace] { try await http.send(contract.gyms()) }
    func visits() async throws -> [Visit] { try await authorized.send(contract.visits()) }
    var appleConfigured: Bool { contract.appleEnabled }
    private let contract: BackendContract
    private let http: HTTPClient
    private let authorized: AuthorizedClient
    init(baseURL: URL?, vault: any CredentialVault, contract: BackendContract = .init()) {
        self.contract = contract
        self.http = HTTPClient(baseURL: baseURL)
        self.authorized = AuthorizedClient(http: http, vault: vault, contract: contract)
    }
    func restore() async throws -> Member? {
        guard try await authorized.hasSession() else { return nil }
        return try await authorized.send(contract.me())
    }
    private func authenticate(_ endpoint: Endpoint<Session>) async throws -> Member {
        let session = try await http.send(endpoint)
        try Task.checkCancellation()
        try await authorized.install(session)
        do { return try await authorized.send(contract.me()) }
        catch { await authorized.clear(); throw error }
    }
    func login(_ input: LoginInput) async throws -> Member { try await authenticate(contract.login(input)) }
    func register(_ input: RegistrationInput) async throws -> Member { try await authenticate(contract.registration(input)) }
    func signInWithApple(_ credential: AppleCredential) async throws -> Member { try await authenticate(contract.apple(credential)) }
    func logout() async {
        // Revoke remotely when the API contract is configured. Local clearing is unconditional.
        if let endpoint = try? contract.revoke(nil) { _ = try? await authorized.send(endpoint) }
        await authorized.clear()
    }
    func membership() async throws -> Membership { try await authorized.send(contract.membership()) }
    func reservations() async throws -> [Reservation] { try await authorized.send(contract.reservations()) }
    func availableSlots(gymID: String) async throws -> [AvailableSlot] { try await authorized.send(contract.slots(gymID: gymID)) }
    func reserve(slotID: String, requestID: UUID) async throws -> Reservation { try await authorized.send(contract.reserve(slotID, requestID: requestID)) }
    func quoteReservations(slotIDs: [String]) async throws -> BookingQuote { try await authorized.send(contract.quoteReservations(slotIDs)) }
    func payAndReserve(slotIDs: [String], requestID: UUID, applePay: ApplePayToken) async throws -> BookingPayment {
        try await authorized.send(contract.payAndReserve(slotIDs, requestID: requestID, applePay: applePay))
    }
    func cancelReservation(id: String, requestID: UUID) async throws { _ = try await authorized.send(contract.cancel(id, requestID: requestID)) }
    func inbox() async throws -> [InboxItem] { try await authorized.send(contract.inbox()) }
    func eligibility() async throws -> DoorEligibility { try await authorized.send(contract.eligibility()) }
    func openDoor(doorID: String, requestID: UUID) async throws -> DoorReceipt { try await authorized.send(contract.openDoor(doorID, requestID: requestID)) }
    func doorStatus(requestID: UUID, operationID: String?) async throws -> DoorReceipt { try await authorized.send(contract.doorStatus(requestID, operationID: operationID)) }
    func registerPush(token: String, preferences: PushNotificationPreferences) async throws {
        _ = try await authorized.send(contract.push(token, preferences: preferences))
    }
}
