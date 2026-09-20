import Foundation

@MainActor protocol AuthenticationServicing {
    var appleConfigured: Bool { get }
    var googleConfigured: Bool { get }
    func restore() async throws -> Member?
    func login(_ input: LoginInput) async throws -> Member
    func register(_ input: RegistrationInput) async throws -> Member
    func signInWithApple(_ credential: AppleCredential) async throws -> Member
    func signInWithGoogle(_ credential: GoogleCredential) async throws -> Member
    func requestPasswordReset(identifier: String) async throws
    func changePassword(current: String, new: String) async throws
    func deleteAccount() async throws
    func logout() async
}
@MainActor protocol MembershipServicing {
    func membership() async throws -> Membership
    func offers() async throws -> [MembershipOffer]
}
@MainActor protocol BookingServicing {
    func reservations() async throws -> [Reservation]
    func availableSlots() async throws -> [AvailableSlot]
    func reserve(slotID: String, requestID: UUID) async throws -> Reservation
    func quoteReservations(slotIDs: [String]) async throws -> BookingQuote
    func payAndReserve(slotIDs: [String], requestID: UUID) async throws -> BookingPayment
    func cancelReservation(id: String, requestID: UUID) async throws
}
@MainActor protocol DoorAccessServicing {
    func eligibility() async throws -> DoorEligibility
    func openDoor(doorID: String, requestID: UUID) async throws -> DoorReceipt
    func doorStatus(requestID: UUID, operationID: String?) async throws -> DoorReceipt
}
@MainActor protocol RemoteNotificationsServicing {
    func inbox() async throws -> [InboxItem]
    func registerPush(token: String, preferences: PushNotificationPreferences) async throws
}
@MainActor protocol UserServicing {
    func gymInfo() async throws -> GymInfo
    func visits() async throws -> [Visit]
}
@MainActor protocol GymService: AuthenticationServicing, MembershipServicing, BookingServicing,
                              DoorAccessServicing, RemoteNotificationsServicing, UserServicing {
    var isDemo: Bool { get }
}
