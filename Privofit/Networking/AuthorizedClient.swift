import Foundation

actor AuthorizedClient {
    private let http: HTTPClient
    private let vault: any CredentialVault
    private let contract: BackendContract
    private var refreshTask: Task<Session, Error>?
    private var generation = 0
    init(http: HTTPClient, vault: any CredentialVault, contract: BackendContract) {
        self.http = http; self.vault = vault; self.contract = contract
    }
    func install(_ value: Session) async throws { generation += 1; refreshTask?.cancel(); refreshTask = nil; try await vault.saveSession(value) }
    func clear() async { generation += 1; refreshTask?.cancel(); refreshTask = nil; try? await vault.clearSession() }
    func hasSession() async throws -> Bool { try await vault.loadSession() != nil }
    private func refresh(_ old: Session) async throws -> Session {
        if let refreshTask { return try await refreshTask.value }
        let epoch = generation
        guard let current = try await vault.loadSession() else { throw AppFailure.unauthorized }
        guard epoch == generation else { throw AppFailure.sessionChanged }
        if current.accessToken != old.accessToken && current.expiresAt > Date().addingTimeInterval(30) { return current }
        // Another caller may have started a refresh while the vault read suspended.
        if let refreshTask { return try await refreshTask.value }
        guard let token = current.refreshToken else { throw AppFailure.unauthorized }
        let task = Task { try await http.send(contract.refresh(token)) }
        refreshTask = task
        do {
            let fresh = try await task.value
            guard epoch == generation else { throw AppFailure.sessionChanged }
            try await vault.saveSession(fresh); refreshTask = nil; return fresh
        } catch { if epoch == generation { refreshTask = nil }; throw error }
    }
    func send<T>(_ endpoint: Endpoint<T>) async throws -> T {
        let epoch = generation
        guard var session = try await vault.loadSession() else { throw AppFailure.unauthorized }
        if session.expiresAt <= Date().addingTimeInterval(30) { session = try await refresh(session) }
        guard epoch == generation else { throw AppFailure.sessionChanged }
        do {
            let result = try await http.send(endpoint, bearer: session.accessToken)
            guard epoch == generation else { throw AppFailure.sessionChanged }
            return result
        } catch AppFailure.unauthorized where endpoint.retryAfterRefresh && endpoint.method == .get {
            let renewed = try await refresh(session)
            guard epoch == generation else { throw AppFailure.sessionChanged }
            let result = try await http.send(endpoint, bearer: renewed.accessToken)
            guard epoch == generation else { throw AppFailure.sessionChanged }
            return result
        }
    }
}
