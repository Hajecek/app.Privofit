import Foundation

// CONFIGURATION BOUNDARY: there is no API specification in the supplied web.
// Implement these factories from real API documentation, including DTO mapping,
// date parsing, error mapping, idempotency and confirmed door-state semantics.
// No invented URL paths or JSON payloads are sent by this project.
struct BackendContract: Sendable {
    var appleEnabled = false
    var googleEnabled = false
    // Injection point for transport tests; production mapping belongs here.
    var refreshFactory: (@Sendable (String) throws -> Endpoint<Session>)? = nil
    func google(_ credential: GoogleCredential) throws -> Endpoint<Session> { throw missing("Google code exchange + PKCE + nonce validation") }
    func resetPassword(_ identifier: String) throws -> Endpoint<EmptyResponse> { throw missing("password reset") }
    func changePassword(current: String, new: String) throws -> Endpoint<EmptyResponse> { throw missing("password change") }
    func deleteAccount() throws -> Endpoint<EmptyResponse> { throw missing("server account deletion") }
    func gymInfo() throws -> Endpoint<GymInfo> { throw missing("public gym information") }
    func offers() throws -> Endpoint<[MembershipOffer]> { throw missing("public membership offers") }
    func visits() throws -> Endpoint<[Visit]> { throw missing("visit history") }
    func login(_ input: LoginInput) throws -> Endpoint<Session> { throw missing("login") }
    func registration(_ input: RegistrationInput) throws -> Endpoint<Session> { throw missing("registration") }
    func apple(_ input: AppleCredential) throws -> Endpoint<Session> { throw missing("Apple token exchange") }
    func refresh(_ token: String) throws -> Endpoint<Session> { if let refreshFactory { return try refreshFactory(token) }; throw missing("refresh") }
    func revoke(_ token: String?) throws -> Endpoint<EmptyResponse> { throw missing("revoke session") }
    func me() throws -> Endpoint<Member> { throw missing("current user") }
    func membership() throws -> Endpoint<Membership> { throw missing("membership") }
    func reservations() throws -> Endpoint<[Reservation]> { throw missing("reservations") }
    func slots() throws -> Endpoint<[AvailableSlot]> { throw missing("available slots") }
    func reserve(_ slot: String, requestID: UUID) throws -> Endpoint<Reservation> { throw missing("create reservation + idempotency") }
    func cancel(_ id: String, requestID: UUID) throws -> Endpoint<EmptyResponse> { throw missing("cancel reservation + idempotency") }
    func inbox() throws -> Endpoint<[InboxItem]> { throw missing("inbox") }
    func eligibility() throws -> Endpoint<DoorEligibility> { throw missing("door eligibility") }
    func openDoor(_ door: String, requestID: UUID) throws -> Endpoint<DoorReceipt> { throw missing("door command + idempotency") }
    func doorStatus(_ requestID: UUID, operationID: String?) throws -> Endpoint<DoorReceipt> { throw missing("door command reconciliation") }
    func push(_ token: String) throws -> Endpoint<EmptyResponse> { throw missing("APNs device registration") }
    private func missing(_ name: String) -> AppFailure { .notConfigured("BackendContract / \(name)") }
}
