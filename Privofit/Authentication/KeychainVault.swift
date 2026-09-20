import Foundation
import Security

protocol CredentialVault: Sendable {
    func loadSession() async throws -> Session?
    func saveSession(_ session: Session) async throws
    func clearSession() async throws
}
actor KeychainVault: CredentialVault {
    private let service: String
    init(service: String = "cz.privofit.ios.credentials") { self.service = service }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    private func read<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        var q = query(account)
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AppFailure.unavailable }
        return try JSONDecoder().decode(type, from: data)
    }
    private func write<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account); attributes.forEach { q[$0.key] = $0.value }
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw AppFailure.unavailable }
        } else if status != errSecSuccess { throw AppFailure.unavailable }
    }
    private func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppFailure.unavailable }
    }
    func loadSession() throws -> Session? { try read(Session.self, account: "session") }
    func saveSession(_ session: Session) throws { try write(session, account: "session") }
    func clearSession() throws { try delete("session") }
    // Retain an uncertain physical command across restarts. Never blindly resend it.
    func pendingDoor(for memberID: String) throws -> PendingDoorCommand? { try read(PendingDoorCommand.self, account: "door.\(memberID)") }
    func saveDoor(_ pending: PendingDoorCommand) throws { try write(pending, account: "door.\(pending.memberID)") }
    func clearDoor(for memberID: String) throws { try delete("door.\(memberID)") }
}
