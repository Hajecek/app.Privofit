import Foundation

// Maps the local PRIVOFIT PHP API (`/api/v1/`) onto domain models.
struct BackendContract: Sendable {
    var appleEnabled = false
    var googleEnabled = false
    var refreshFactory: (@Sendable (String) throws -> Endpoint<Session>)? = nil

    func google(_ credential: GoogleCredential) throws -> Endpoint<Session> { throw missing("Google code exchange + PKCE + nonce validation") }
    func resetPassword(_ identifier: String) throws -> Endpoint<EmptyResponse> {
        try APIJSON.postEmpty("auth/forgot-password", body: IdentifierBody(identifier: identifier))
    }
    func changePassword(current: String, new: String) throws -> Endpoint<EmptyResponse> {
        try APIJSON.postEmpty("auth/change-password", body: PasswordBody(currentPassword: current, newPassword: new))
    }
    func deleteAccount() throws -> Endpoint<EmptyResponse> {
        Endpoint(path: "users/me", method: .delete, decode: { _ in EmptyResponse() })
    }
    func gymInfo() throws -> Endpoint<GymInfo> {
        Endpoint(path: "gym", method: .get, retryAfterRefresh: true, decode: { try APIJSON.decode($0) })
    }
    func live() throws -> Endpoint<LiveStamp> {
        Endpoint(path: "live", method: .get, retryAfterRefresh: true, decode: { try APIJSON.decode($0) })
    }
    func offers() throws -> Endpoint<[MembershipOffer]> {
        Endpoint(path: "memberships/plans", method: .get, retryAfterRefresh: true, decode: { try APIJSON.decode($0) })
    }
    func visits() throws -> Endpoint<[Visit]> {
        Endpoint(path: "visits", method: .get, retryAfterRefresh: true, decode: { try APIJSON.decodeList($0) })
    }
    func login(_ input: LoginInput) throws -> Endpoint<Session> {
        try APIJSON.post("auth/login", body: LoginBody(identifier: input.identifier, password: input.password))
    }
    func registration(_ input: RegistrationInput) throws -> Endpoint<Session> {
        try APIJSON.post("auth/register", body: RegisterBody(firstName: input.firstName, username: input.username, email: input.email, password: input.password))
    }
    func apple(_ input: AppleCredential) throws -> Endpoint<Session> { throw missing("Apple token exchange") }
    func refresh(_ token: String) throws -> Endpoint<Session> {
        if let refreshFactory { return try refreshFactory(token) }
        return try APIJSON.post("auth/refresh", body: RefreshBody(refreshToken: token))
    }
    func revoke(_ token: String?) throws -> Endpoint<EmptyResponse> {
        try APIJSON.postEmpty("auth/logout", body: RefreshBody(refreshToken: token))
    }
    func me() throws -> Endpoint<Member> {
        Endpoint(path: "users/me", method: .get, retryAfterRefresh: true, decode: { try APIJSON.decode($0) })
    }
    func membership() throws -> Endpoint<Membership> {
        Endpoint(path: "memberships/me", method: .get, retryAfterRefresh: true, decode: { try APIJSON.decode($0) })
    }
    func reservations() throws -> Endpoint<[Reservation]> {
        Endpoint(path: "reservations", method: .get, retryAfterRefresh: true, decode: { try APIJSON.decodeList($0) })
    }
    func gyms() -> Endpoint<[GymPlace]> {
        Endpoint(path: "gyms", method: .get, retryAfterRefresh: true, decode: { try APIJSON.decodeList($0) })
    }
    func slots(gymID: String) -> Endpoint<[AvailableSlot]> {
        let query = gymID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? gymID
        return Endpoint(path: "reservations/slots?gymID=\(query)", method: .get, retryAfterRefresh: true, decode: { try APIJSON.decodeList($0) })
    }
    func reserve(_ slot: String, requestID: UUID) throws -> Endpoint<Reservation> {
        try APIJSON.post("reservations", body: ReserveBody(slotID: slot, requestID: requestID))
    }
    func quoteReservations(_ slotIDs: [String]) throws -> Endpoint<BookingQuote> {
        Endpoint(path: "reservations/quote", method: .post, body: try APIJSON.body(QuoteBody(slotIDs: slotIDs)), decode: { data in
            let dto: QuoteDTO = try APIJSON.decode(data)
            guard let price = Decimal(string: dto.pricePerSlot, locale: Locale(identifier: "en_US_POSIX")) else {
                throw AppFailure.invalidResponse
            }
            let total = dto.total.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } ?? price * Decimal(dto.slots.count)
            return BookingQuote(slots: dto.slots, pricePerSlot: price, currencyCode: dto.currencyCode, total: total)
        })
    }
    func payAndReserve(_ slotIDs: [String], requestID: UUID, applePay: ApplePayToken) throws -> Endpoint<BookingPayment> {
        Endpoint(path: "reservations/pay", method: .post, body: try APIJSON.body(PayBody(slotIDs: slotIDs, requestID: requestID, applePay: .init(applePay))), headers: ["Idempotency-Key": requestID.uuidString], decode: { data in
            let dto: PaymentDTO = try APIJSON.decode(data)
            guard let status = BookingPayment.Status(rawValue: dto.status) else { throw AppFailure.invalidResponse }
            return BookingPayment(id: dto.id, status: status, checkoutURL: dto.checkoutURL, reservations: dto.reservations)
        })
    }
    func cancel(_ id: String, requestID: UUID) throws -> Endpoint<EmptyResponse> {
        Endpoint(
            path: "reservations/\(id)/cancel",
            method: .post,
            body: try APIJSON.body(RequestIDBody(requestID: requestID)),
            headers: ["Idempotency-Key": requestID.uuidString],
            decode: { _ in EmptyResponse() }
        )
    }
    func inbox() throws -> Endpoint<[InboxItem]> {
        Endpoint(path: "inbox", method: .get, retryAfterRefresh: true, decode: { try APIJSON.decodeList($0) })
    }
    func eligibility() throws -> Endpoint<DoorEligibility> {
        Endpoint(path: "access/eligibility", method: .get, retryAfterRefresh: true, decode: { try APIJSON.decode($0) })
    }
    func openDoor(_ door: String, requestID: UUID) throws -> Endpoint<DoorReceipt> {
        try APIJSON.post("access/open", body: OpenDoorBody(doorID: door, requestID: requestID))
    }
    func doorStatus(_ requestID: UUID, operationID: String?) throws -> Endpoint<DoorReceipt> {
        var path = "access/commands?requestID=\(requestID.uuidString)"
        if let operationID, let encoded = operationID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&operationID=\(encoded)"
        }
        return Endpoint(path: path, method: .get, retryAfterRefresh: true, decode: { try APIJSON.decode($0) })
    }
    func push(_ token: String, preferences: PushNotificationPreferences) throws -> Endpoint<EmptyResponse> {
        try APIJSON.postEmpty("devices/push", body: PushBody(token: token, preferences: preferences))
    }
    private func missing(_ name: String) -> AppFailure { .notConfigured("BackendContract / \(name)") }
}

private enum APIJSON {
    private struct Envelope<Value: Decodable>: Decodable { var data: Value }
    static func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = makeDecoder()
        if let value = try? decoder.decode(T.self, from: data) { return value }
        if let envelope = try? decoder.decode(Envelope<T>.self, from: data) { return envelope.data }
        throw AppFailure.invalidResponse
    }
    static func decodeList<T: Decodable>(_ data: Data) throws -> [T] {
        if let items: [T] = try? decode(data) { return items }
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { throw AppFailure.invalidResponse }
        let rows: [Any]
        if let items = raw as? [Any] {
            rows = items
        } else if let object = raw as? [String: Any], let items = object["data"] as? [Any] {
            rows = items
        } else {
            throw AppFailure.invalidResponse
        }
        let decoder = makeDecoder()
        return rows.compactMap { item in
            guard JSONSerialization.isValidJSONObject(item),
                  let piece = try? JSONSerialization.data(withJSONObject: item),
                  let value = try? decoder.decode(T.self, from: piece) else { return nil }
            return value
        }
    }
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) { return Date(timeIntervalSince1970: value) }
            let raw = try container.decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            iso.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = iso.date(from: raw) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: raw) { return date }
            let posix = DateFormatter()
            posix.locale = Locale(identifier: "en_US_POSIX")
            posix.timeZone = TimeZone(secondsFromGMT: 0)
            for format in ["yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ssX", "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd HH:mm:ss"] {
                posix.dateFormat = format
                if let date = posix.date(from: raw) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "date")
        }
        return decoder
    }
    static func body(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
    static func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) throws -> Endpoint<T> {
        Endpoint(path: path, method: .post, body: try Self.body(body), decode: { try decode($0) })
    }
    static func postEmpty<Body: Encodable>(_ path: String, body: Body) throws -> Endpoint<EmptyResponse> {
        Endpoint(path: path, method: .post, body: try Self.body(body), decode: { _ in EmptyResponse() })
    }
}

private struct IdentifierBody: Encodable { var identifier: String }
private struct PasswordBody: Encodable { var currentPassword: String; var newPassword: String }
private struct LoginBody: Encodable { var identifier: String; var password: String; var platform = "ios"; var deviceName = "iOS" }
private struct RegisterBody: Encodable {
    var firstName: String
    var username: String
    var email: String
    var password: String
    init(firstName: String, username: String, email: String, password: String) {
        self.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.password = password
    }
}
private struct RefreshBody: Encodable { var refreshToken: String? }
private struct ReserveBody: Encodable { var slotID: String; var requestID: UUID }
private struct QuoteBody: Encodable { var slotIDs: [String] }
private struct RequestIDBody: Encodable { var requestID: UUID }
private struct OpenDoorBody: Encodable { var doorID: String; var requestID: UUID }
private struct PushBody: Encodable { var token: String; var preferences: PushNotificationPreferences }
private struct QuoteDTO: Decodable {
    var slots: [AvailableSlot]
    var pricePerSlot: String
    var currencyCode: String
    var total: String?
}
private struct PaymentDTO: Decodable {
    var id: String
    var status: String
    var checkoutURL: URL?
    var reservations: [Reservation]
}
private struct PayBody: Encodable {
    var slotIDs: [String]
    var requestID: UUID
    var applePay: ApplePayBody
}
private struct ApplePayBody: Encodable {
    var transactionIdentifier: String
    var paymentData: Data
    var displayName: String?
    var network: String?
    init(_ token: ApplePayToken) {
        transactionIdentifier = token.transactionIdentifier
        paymentData = token.paymentData
        displayName = token.displayName
        network = token.network
    }
}
