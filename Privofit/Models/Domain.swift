import Foundation

// Domain models, NOT an asserted wire format. Map the confirmed backend DTOs
// to these types in BackendContract. Dates are absolute instants.
struct Member: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var firstName: String
    var username: String
    var email: String
    var status: AccountStatus
}
enum AccountStatus: String, Codable, Sendable { case active, inactive, blocked }
struct Membership: Codable, Equatable, Sendable {
    let title: String
    let validUntil: Date
    let remainingEntries: Int?
    let isActive: Bool
    var validFrom: Date? = nil
    var status: Status = .active
}
struct Reservation: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let start: Date
    let end: Date
    let room: String
    let canCancel: Bool
}
struct AvailableSlot: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let start: Date
    let end: Date
    let room: String
}
struct BookingQuote: Equatable, Sendable {
    var slots: [AvailableSlot]
    var pricePerSlot: Decimal
    var currencyCode: String
    var total: Decimal { pricePerSlot * Decimal(slots.count) }
    func formatted(_ value: Decimal) -> String {
        value.formatted(.currency(code: currencyCode).locale(Locale(identifier: "cs_CZ")))
    }
}
struct BookingPayment: Equatable, Sendable {
    enum Status: String, Sendable { case paid, pending, failed }
    var id: String
    var status: Status
    var checkoutURL: URL?
    var reservations: [Reservation]
}
struct ApplePayToken: Equatable, Sendable {
    var transactionIdentifier: String
    var paymentData: Data
    var displayName: String?
    var network: String?
}
struct InboxItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let date: Date
}
struct Session: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
}
struct LoginInput: Sendable { let identifier: String; let password: String }
struct RegistrationInput: Sendable {
    let firstName: String; let username: String; let email: String; let password: String
}
struct AppleCredential: Sendable {
    let identityToken: String
    let authorizationCode: String
    let rawNonce: String
    let givenName: String?
}
struct DoorEligibility: Codable, Sendable {
    let allowed: Bool
    let reason: String?
    let doorID: String
    let expiresAt: Date
    var doorName: String? = nil
}
struct DoorReceipt: Codable, Sendable {
    enum Outcome: String, Codable, Sendable { case confirmedOpen, accepted, denied }
    let operationID: String
    let outcome: Outcome
    let message: String?
    var entryUntil: Date? = nil
}
struct PendingDoorCommand: Codable, Sendable {
    let memberID: String
    let requestID: UUID
    let operationID: String?
    let createdAt: Date
}
struct EmptyResponse: Sendable {}
struct PushNotificationPreferences: Codable, Equatable, Sendable {
    var enabled: Bool
    var channels: [String: Bool]
}

enum AppFailure: Error, LocalizedError, Equatable, Sendable {
    case notConfigured(String), unauthorized, forbidden, unavailable, invalidResponse
    case http(Int), offline, biometricsUnavailable, cancelled, sessionChanged, rejected(String), timeout
    var errorDescription: String? {
        switch self {
        case .notConfigured(let item): return "Chybí konfigurace: \(item)."
        case .unauthorized: return "Přihlášení vypršelo. Přihlas se znovu."
        case .forbidden: return "Pro tuto akci nemáš oprávnění."
        case .unavailable: return "Služba teď není dostupná. Zkus to později."
        case .invalidResponse: return "Server poslal neočekávanou odpověď."
        case .http(let status): return "Požadavek se nepodařil (\(status))."
        case .offline: return "Není dostupné připojení. Zkontroluj internet."
        case .biometricsUnavailable: return "Biometrické ověření není dostupné."
        case .cancelled: return "Ověření bylo zrušeno."
        case .sessionChanged: return "Stav přihlášení se změnil."
        case .rejected(let message): return message
        case .timeout: return "Server neodpověděl včas. Zkus to znovu."
        }
    }
}

struct GoogleCredential: Sendable {
    let authorizationCode: String
    let codeVerifier: String
    let redirectURI: String
    let clientID: String
    let nonce: String
}
struct GymInfo: Codable, Sendable {
    let name: String
    let description: String
    let openingHours: String
    let announcements: [String]
}
struct MembershipOffer: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let priceDescription: String
    // A price label is supplied by the server. Payment is a separately configured web flow.
}
struct Visit: Codable, Identifiable, Sendable { let id: String; let date: Date; let room: String }
extension Membership {
    enum Status: String, Codable, Sendable { case active, ending, paused, inactive }
}
