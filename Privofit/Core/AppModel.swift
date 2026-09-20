import Foundation
import Observation

enum AppPhase: Equatable {
    case launching, signedOut, onboarding, authenticated, guest, sessionExpired, restricted(AccountStatus)
}
enum AppTab: Hashable { case dashboard, reservations, door, membership, profile }
@MainActor @Observable final class AppModel {
    private(set) var phase: AppPhase = .launching
    private(set) var member: Member?
    var membership: Membership?
    var reservations: [Reservation] = []
    var inbox: [InboxItem] = []
    var tab: AppTab = .dashboard
    var showGuestGate = false
    var showDoor = false
    var showInbox = false
    var registrationRequested = false
    var cooldownUntil: Date = .distantPast
    var doorRequestInFlight = false
    var unconfirmedDoorCommands: [String: PendingDoorCommand] = [:]
    var busy = false
    var loading = false
    var locked = false
    var error: String?
    let service: any GymService
    let preferences: Preferences
    let notifications: NotificationService
    let biometrics: any BiometricAuthenticating
    let vault: KeychainVault
    let apple = AppleSignIn()
    let google = GoogleSignIn()
    private var epoch = 0
    var isGuest: Bool { phase == .guest || (phase == .onboarding && member == nil) }
    var isDemo: Bool { service.isDemo }
    init(service: any GymService, preferences: Preferences = Preferences(), notifications: NotificationService = NotificationService(),
         biometrics: any BiometricAuthenticating = BiometricService(), vault: KeychainVault = KeychainVault()) {
        self.service = service; self.preferences = preferences; self.notifications = notifications
        self.biometrics = biometrics; self.vault = vault
    }
    func boot() async {
        guard phase == .launching else { return }
        let current = epoch
        do {
            let restored = try await service.restore()
            guard current == epoch else { return }
            if let restored { accept(restored); if preferences.biometrics { locked = true } }
            else { phase = .signedOut }
        } catch { guard current == epoch else { return }; handle(error); if phase == .launching { phase = .signedOut } }
        await notifications.registerIfAllowed()
    }
    private func accept(_ user: Member) {
        member = user
        guard user.status == .active else { phase = .restricted(user.status); return }
        if isDemo {
            preferences.completeOnboarding(for: user.id)
            phase = .authenticated
            return
        }
        phase = preferences.completedOnboarding(for: user.id) ? .authenticated : .onboarding
    }
    func login(identifier: String, password: String) async {
        await authenticate { try await self.service.login(.init(identifier: identifier.trimmingCharacters(in: .whitespacesAndNewlines), password: password)) }
    }
    func register(_ input: RegistrationInput) async { await authenticate { try await self.service.register(input) } }
    func appleLogin() async {
        guard service.appleConfigured else { error = L10n.tr("error.configuration"); return }
        await authenticate { let credentials = try await self.apple.signIn(); return try await self.service.signInWithApple(credentials) }
    }
    func googleLogin() async {
        guard service.googleConfigured else { error = L10n.tr("error.configuration"); return }
        await authenticate { let credentials = try await self.google.signIn(); return try await self.service.signInWithGoogle(credentials) }
    }
    func requestDoor() {
        guard phase == .authenticated else { showGuestGate = true; return }
        showDoor = true
    }
    private func authenticate(_ operation: () async throws -> Member) async {
        guard !busy else { return }; busy = true; error = nil; let current = epoch
        defer { busy = false }
        do { let user = try await operation(); guard current == epoch else { return }; accept(user) }
        catch { guard current == epoch else { return }; handle(error) }
    }
    func enterGuest() {
        guard !busy else { return }; epoch += 1; member = nil; error = nil
        phase = preferences.completedOnboarding(for: "guest") ? .guest : .onboarding
    }
    func finishOnboarding() {
        guard phase == .onboarding, member == nil || member?.status == .active else { return }
        preferences.completeOnboarding(for: member?.id ?? "guest")
        phase = member == nil ? .guest : .authenticated
    }
    func requireLogin() { epoch += 1; phase = .signedOut; tab = .dashboard; error = nil }
    func logout() async {
        guard !busy else { return }; busy = true; epoch += 1
        showDoor = false; showInbox = false
        phase = .signedOut; member = nil; membership = nil; reservations = []; inbox = []; locked = false; tab = .dashboard
        await service.logout(); busy = false
    }
    func loadDashboard() async {
        guard phase == .authenticated, !locked, !loading else { return }
        loading = true; error = nil; let current = epoch
        defer { loading = false }
        do {
            let plan = try await service.membership()
            let bookings = try await service.reservations()
            let messages = try await service.inbox()
            guard current == epoch, phase == .authenticated else { return }
            membership = plan; reservations = bookings; inbox = messages
        } catch { if current == epoch { handle(error) } }
    }
    func handle(_ failure: Error) {
        if failure is CancellationError { return }
        if let failure = failure as? AppFailure, failure == .unauthorized {
            if phase == .sessionExpired { error = L10n.tr("error.session"); return }
            if phase == .signedOut { error = L10n.tr("error.credentials"); return }
            showDoor = false; showInbox = false
            busy = true
            Task { await service.logout(); busy = false }
            epoch += 1; member = nil; membership = nil; reservations = []; inbox = []; locked = false; phase = .sessionExpired
        }
        error = FriendlyError.message(failure)
    }
    func backgrounded() { if member != nil && preferences.biometrics { locked = true } }
    func unlock() async {
        do { try await biometrics.authenticate(reason: L10n.tr("biometry.reason")); locked = false }
        catch { self.error = FriendlyError.message(error) }
    }
    func uploadPushToken(_ token: String) async {
        notifications.deviceToken = token
        guard phase == .authenticated, !isDemo else { return }
        do { try await service.registerPush(token: token); notifications.registrationError = nil }
        catch { notifications.registrationError = L10n.tr("notifications.registration.failed") }
    }
}
