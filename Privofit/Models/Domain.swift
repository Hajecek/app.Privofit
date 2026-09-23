import Foundation

// Domain models, NOT an asserted wire format. Map the confirmed backend DTOs
// to these types in BackendContract. Dates are absolute instants.
struct Member: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var firstName: String
    var username: String
    var email: String
    var status: AccountStatus
    var avatarURL: URL? = nil
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
    var bufferMinutes: Int
    var price: Decimal?
    var currencyCode: String
    init(id: String, start: Date, end: Date, room: String, canCancel: Bool, bufferMinutes: Int = 15, price: Decimal? = nil, currencyCode: String = "CZK") {
        self.id = id; self.start = start; self.end = end; self.room = room; self.canCancel = canCancel
        self.bufferMinutes = bufferMinutes; self.price = price; self.currencyCode = currencyCode
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        room = try c.decode(String.self, forKey: .room)
        canCancel = try c.decode(Bool.self, forKey: .canCancel)
        bufferMinutes = try c.decodeIfPresent(Int.self, forKey: .bufferMinutes) ?? 15
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? "CZK"
        price = GymMoney.decode(c, key: .price)
    }
    var occupiedUntil: Date { GymClock.occupancyEnd(end, bufferMinutes: bufferMinutes) }
}
struct AvailableSlot: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let start: Date
    let end: Date
    let room: String
    var bufferMinutes: Int
    var price: Decimal?
    var currencyCode: String
    var gymID: String
    init(id: String, start: Date, end: Date, room: String, bufferMinutes: Int = 15, price: Decimal? = nil, currencyCode: String = "CZK", gymID: String = "vinohrady") {
        self.id = id; self.start = start; self.end = end; self.room = room
        self.bufferMinutes = bufferMinutes; self.price = price; self.currencyCode = currencyCode
        self.gymID = gymID
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        room = try c.decode(String.self, forKey: .room)
        bufferMinutes = try c.decodeIfPresent(Int.self, forKey: .bufferMinutes) ?? 15
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? "CZK"
        price = GymMoney.decode(c, key: .price)
        gymID = try c.decodeIfPresent(String.self, forKey: .gymID) ?? ""
    }
    var occupiedUntil: Date { GymClock.occupancyEnd(end, bufferMinutes: bufferMinutes) }
}
enum GymMoney {
    static func czk(_ value: Decimal, code: String = "CZK") -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        let amount = formatter.string(from: value as NSDecimalNumber) ?? "0"
        if code == "CZK" || code == "Kč" { return "\(amount) Kč" }
        return "\(amount) \(code)"
    }
    static func label(_ price: Decimal?, code: String = "CZK") -> String? {
        guard let price else { return nil }
        return czk(price, code: code)
    }
    static func decode<Key: CodingKey>(_ c: KeyedDecodingContainer<Key>, key: Key) -> Decimal? {
        if let value = try? c.decode(Decimal.self, forKey: key) { return value }
        if let raw = try? c.decode(String.self, forKey: key) {
            return Decimal(string: raw.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
        }
        if let value = try? c.decode(Double.self, forKey: key) { return Decimal(value) }
        return nil
    }
}
struct BookingQuote: Equatable, Sendable {
    var slots: [AvailableSlot]
    var pricePerSlot: Decimal
    var currencyCode: String
    var total: Decimal
    func formatted(_ value: Decimal) -> String { GymMoney.czk(value, code: currencyCode) }
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
    let firstName: String
    let lastName: String
    let username: String
    let email: String
    let password: String
    let passwordConfirmation: String
    let acceptedTerms: Bool
    let acceptedPrivacy: Bool
}
struct AppleCredential: Sendable {
    let identityToken: String
    let authorizationCode: String
    let rawNonce: String
    let givenName: String?
    let familyName: String?
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
    let ticket: String
}
struct GymInfo: Codable, Equatable, Sendable {
    let name: String
    let description: String
    let openingHours: String
    let announcements: [String]
}
struct LiveStamp: Decodable, Sendable {
    var revision: String
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .revision) {
            revision = value
        } else {
            revision = String(try container.decode(Int.self, forKey: .revision))
        }
    }
    private enum CodingKeys: String, CodingKey { case revision }
}
struct GymPlace: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
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
