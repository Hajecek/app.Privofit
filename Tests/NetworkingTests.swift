import XCTest
import Foundation
@testable import Privofit

private actor MemoryVault: CredentialVault {
    var value: Session?
    init(_ value: Session?) { self.value = value }
    func loadSession() -> Session? { value }
    func saveSession(_ session: Session) { value = session }
    func clearSession() { value = nil }
}
private final class ResponseStore: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String: Int] = [:]
    func reset() { lock.lock(); defer { lock.unlock() }; calls = [:] }
    func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return calls[path, default: 0] }
    func response(for request: URLRequest) -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        let path = request.url!.path; calls[path, default: 0] += 1
        if path == "/refresh" {
            let value = Session(accessToken: "renewed", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600))
            return (200, try! JSONEncoder().encode(value))
        }
        if path == "/denied" { return (403, Data()) }
        if path == "/mfa" { return (401, Data(#"{"success":false,"message":"Vyžadován TOTP kód.","errors":{"mfa":true}}"#.utf8)) }
        if path == "/mfa-apple" { return (422, Data(#"{"success":false,"message":"Vyžadován ověřovací kód.","errors":{"mfa":true}}"#.utf8)) }
        if path == "/command" { return (401, Data()) }
        return (request.value(forHTTPHeaderField: "Authorization") == "Bearer renewed" ? 200 : 401, Data("ok".utf8))
    }
}
private final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    static let store = ResponseStore()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.store.response(for: request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
@MainActor final class NetworkingTests: XCTestCase {
    private func http() -> HTTPClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureURLProtocol.self]
        return HTTPClient(baseURL: URL(string: "https://api.example.invalid/"), session: URLSession(configuration: config))
    }
    override func setUp() { FixtureURLProtocol.store.reset() }
    func testRefreshIsSharedAcrossConcurrentReads() async throws {
        let vault = MemoryVault(.init(accessToken: "old", refreshToken: "refresh", expiresAt: .distantPast))
        var contract = BackendContract()
        contract.refreshFactory = { _ in Endpoint(path: "refresh", method: .post, decode: { try JSONDecoder().decode(Session.self, from: $0) }) }
        let client = AuthorizedClient(http: http(), vault: vault, contract: contract)
        let endpoint = Endpoint<String>(path: "member", method: .get, retryAfterRefresh: true, decode: { String(decoding: $0, as: UTF8.self) })
        async let a = client.send(endpoint)
        async let b = client.send(endpoint)
        let values = try await [a, b]
        XCTAssertEqual(values, ["ok", "ok"])
        XCTAssertEqual(FixtureURLProtocol.store.count("/refresh"), 1)
        let stored = await vault.loadSession(); XCTAssertEqual(stored?.accessToken, "renewed")
    }
    func testCommandIsNeverRetriedOnUnauthorized() async throws {
        let vault = MemoryVault(.init(accessToken: "old", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600)))
        var contract = BackendContract()
        contract.refreshFactory = { _ in Endpoint(path: "refresh", method: .post, decode: { try JSONDecoder().decode(Session.self, from: $0) }) }
        let client = AuthorizedClient(http: http(), vault: vault, contract: contract)
        let endpoint = Endpoint<String>(path: "command", method: .post, retryAfterRefresh: true, decode: { String(decoding: $0, as: UTF8.self) })
        do { _ = try await client.send(endpoint); XCTFail("Expected unauthorized") }
        catch { XCTAssertEqual(error as? AppFailure, .unauthorized) }
        XCTAssertEqual(FixtureURLProtocol.store.count("/command"), 1)
        XCTAssertEqual(FixtureURLProtocol.store.count("/refresh"), 1)
    }
    func testMfaChallengeIsNotADeadSession() async {
        let endpoint = Endpoint<String>(path: "mfa", method: .post, decode: { _ in "" })
        do { _ = try await http().send(endpoint); XCTFail("Expected MFA") }
        catch { XCTAssertEqual(error as? AppFailure, .mfaRequired) }
        let apple = Endpoint<String>(path: "mfa-apple", method: .post, decode: { _ in "" })
        do { _ = try await http().send(apple); XCTFail("Expected MFA") }
        catch { XCTAssertEqual(error as? AppFailure, .mfaRequired) }
    }
    func testHTTPErrorMapping() async {
        do { _ = try await http().send(Endpoint<String>(path: "denied", method: .get, decode: { _ in "" })); XCTFail("Expected forbidden") }
        catch { XCTAssertEqual(error as? AppFailure, .forbidden) }
    }
    func testForeignHostIsRejected() async {
        do { _ = try await http().send(Endpoint<String>(path: "https://other.invalid/", method: .get, decode: { _ in "" })); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? AppFailure, .invalidResponse) }
    }
    func testKeychainRoundTripAndDeletion() async throws {
        let vault = KeychainVault(service: "cz.privofit.tests.\(UUID().uuidString)")
        let original = Session(accessToken: "test-only", refreshToken: "test-refresh", expiresAt: Date(timeIntervalSince1970: 1900000000))
        try await vault.saveSession(original)
        let stored = try await vault.loadSession(); XCTAssertEqual(stored, original)
        try await vault.clearSession()
        let deleted = try await vault.loadSession(); XCTAssertNil(deleted)
    }
    func testPendingDoorIsScopedToMember() async throws {
        let vault = KeychainVault(service: "cz.privofit.tests.\(UUID().uuidString)")
        let a = PendingDoorCommand(memberID: "a", requestID: UUID(), operationID: nil, createdAt: Date())
        let b = PendingDoorCommand(memberID: "b", requestID: UUID(), operationID: nil, createdAt: Date())
        try await vault.saveDoor(a); try await vault.saveDoor(b)
        try await vault.clearDoor(for: "a")
        let first = try await vault.pendingDoor(for: "a")
        let second = try await vault.pendingDoor(for: "b")
        XCTAssertNil(first); XCTAssertEqual(second?.requestID, b.requestID)
        try await vault.clearDoor(for: "b")
    }

}
