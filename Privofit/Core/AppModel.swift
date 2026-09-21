import Foundation
import Observation

enum AppPhase: Equatable {
    case launching, signedOut, onboarding, authenticated, guest, sessionExpired, restricted(AccountStatus)
}
enum AppTab: Hashable { case dashboard, reservations, door, membership, profile }
enum ReservationSection: Hashable { case slots, mine }
@MainActor @Observable final class AppModel {
    private(set) var phase: AppPhase = .launching
    private(set) var member: Member?
    var membership: Membership?
    var reservations: [Reservation] = []
    var visits: [Visit] = []
    var gym: GymInfo?
    var slots: [AvailableSlot] = []
    var offers: [MembershipOffer] = []
    var gyms: [GymPlace] = []
    var selectedGymID: String?
    var gymSuggestedByLocation = false
    var inbox: [InboxItem] = []
    var tab: AppTab = .dashboard
    var reservationSection: ReservationSection = .slots
    var showGuestGate = false
    var showDoor = false
    var showInbox = false
    var showFloor = false
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
    let location: LocationService
    let biometrics: any BiometricAuthenticating
    let vault: KeychainVault
    let apple = AppleSignIn()
    let google = GoogleSignIn()
    private var epoch = 0
    private var syncing = false
    private var liveRevision = ""
    private var liveBusy = false
    var isGuest: Bool { phase == .guest || (phase == .onboarding && member == nil) }
    var isDemo: Bool { service.isDemo }
    init(service: any GymService, preferences: Preferences = Preferences(), notifications: NotificationService = NotificationService(),
         location: LocationService = LocationService(),
         biometrics: any BiometricAuthenticating = BiometricService(), vault: KeychainVault = KeychainVault()) {
        self.service = service; self.preferences = preferences; self.notifications = notifications
        self.location = location
        self.biometrics = biometrics; self.vault = vault
        selectedGymID = preferences.gymID
    }
    func boot() async {
        guard phase == .launching else { return }
        let current = epoch
        do {
            let restored = try await service.restore()
            guard current == epoch else { return }
            if let restored { accept(restored); if preferences.biometrics { locked = true } }
            else { phase = .signedOut }
        } catch {
            guard current == epoch else { return }
            // Relace v klíčence zůstává. Výpadek nebo vypršelý access token není odhlášení.
            phase = .authenticated
            AppDelegate.shared?.updateAuthentication(isLoggedIn: true)
        }
        await notifications.registerIfAllowed()
    }
    private func accept(_ user: Member) {
        member = user
        guard user.status == .active else {
            showDoor = false
            showInbox = false
            showFloor = false
            phase = .restricted(user.status)
            return
        }
        if isDemo {
            preferences.completeOnboarding(for: user.id)
            phase = .authenticated
            AppDelegate.shared?.updateAuthentication(isLoggedIn: true)
            return
        }
        phase = preferences.completedOnboarding(for: user.id) ? .authenticated : .onboarding
        if phase == .authenticated { AppDelegate.shared?.updateAuthentication(isLoggedIn: true) }
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
        if phase == .authenticated { AppDelegate.shared?.updateAuthentication(isLoggedIn: true) }
    }
    func requireLogin() { epoch += 1; phase = .signedOut; tab = .dashboard; error = nil }
    func logout() async {
        guard !busy else { return }; busy = true; epoch += 1
        showDoor = false; showInbox = false; showFloor = false
        phase = .signedOut; member = nil; membership = nil; reservations = []; visits = []; gym = nil; slots = []; offers = []; gyms = []; selectedGymID = nil; gymSuggestedByLocation = false; inbox = []; locked = false; tab = .dashboard
        liveRevision = ""
        AppDelegate.shared?.updateAuthentication(isLoggedIn: false)
        await service.logout(); busy = false
    }
    func loadDashboard() async {
        await syncAccount(showLoading: true)
    }
    func syncAccount(showLoading: Bool = false) async {
        switch phase {
        case .authenticated, .restricted:
            break
        case .onboarding:
            guard member != nil else { return }
        default:
            return
        }
        if syncing && !showLoading { return }
        syncing = true
        if showLoading { loading = true; error = nil }
        let current = epoch
        defer {
            syncing = false
            if showLoading { loading = false }
        }
        do {
            guard let user = try await service.restore() else { return }
            guard current == epoch else { return }
            accept(user)
            guard phase == .authenticated else {
                membership = nil
                return
            }
            if let plan = await fetchKeepingSession({ try await service.membership() }) { membership = plan }
            guard current == epoch, phase == .authenticated else { return }
            if let bookings = await fetchKeepingSession({ try await service.reservations() }) { reservations = bookings }
            guard current == epoch, phase == .authenticated else { return }
            if let history = await fetchKeepingSession({ try await service.visits() }) { visits = history }
            guard current == epoch, phase == .authenticated else { return }
            if let messages = await fetchKeepingSession({ try await service.inbox() }) { inbox = messages }
            guard current == epoch, phase == .authenticated else { return }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            if current == epoch { handle(error, surface: showLoading) }
        }
    }
    private func fetchKeepingSession<T>(_ work: () async throws -> T) async -> T? {
        do { return try await work() }
        catch is CancellationError { return nil }
        catch {
            handle(error, surface: false)
            return nil
        }
    }
    func handle(_ failure: Error, surface: Bool = true) {
        if failure is CancellationError { return }
        if let failure = failure as? AppFailure, failure == .unauthorized {
            if phase == .signedOut { error = L10n.tr("error.credentials"); return }
            // Access token obnoví AuthorizedClient přes API. Aplikace se sama neodhlašuje.
            return
        }
        if surface { error = FriendlyError.message(failure) }
    }
    func backgrounded() { if member != nil && preferences.biometrics { locked = true } }
    func unlock() async {
        do { try await biometrics.authenticate(reason: L10n.tr("biometry.reason")); locked = false }
        catch { self.error = FriendlyError.message(error) }
    }
    func chooseGym(_ id: String) {
        selectedGymID = id
        preferences.gymID = id
        preferences.gymPickedManually = true
        gymSuggestedByLocation = false
    }
    func resolveGym(from places: [GymPlace]) async {
        gyms = places
        guard !places.isEmpty else { selectedGymID = nil; return }
        if preferences.gymPickedManually, let saved = preferences.gymID, places.contains(where: { $0.id == saved }) {
            selectedGymID = saved
            gymSuggestedByLocation = false
            return
        }
        if let coordinate = await location.currentIfAuthorized(),
           let nearest = GymLocator.nearest(places, to: coordinate.latitude, longitude: coordinate.longitude) {
            selectedGymID = nearest.id
            preferences.gymID = nearest.id
            gymSuggestedByLocation = true
            return
        }
        if let saved = preferences.gymID, places.contains(where: { $0.id == saved }) {
            selectedGymID = saved
            return
        }
        selectedGymID = places[0].id
        preferences.gymID = places[0].id
        gymSuggestedByLocation = false
    }
    func refreshReservations() async {
        guard phase == .authenticated, !locked else { return }
        let current = epoch
        do {
            let bookings = try await service.reservations()
            guard current == epoch, phase == .authenticated else { return }
            reservations = bookings
        } catch {
            if current == epoch { handle(error, surface: false) }
        }
    }
    func tickLive(force: Bool = false) async {
        guard !isDemo else { return }
        switch phase {
        case .authenticated, .guest, .onboarding, .restricted:
            break
        default:
            return
        }
        if liveBusy { return }
        liveBusy = true
        defer { liveBusy = false }
        do {
            let revision = try await service.liveRevision()
            let changed = revision != liveRevision
            if changed { liveRevision = revision }
            if force || changed || gym == nil {
                await refreshLiveCatalog()
            }
            if force {
                await syncAccount()
            } else if changed {
                await refreshReservations()
            }
        } catch is CancellationError {
            return
        } catch {
            await refreshLiveCatalog()
            if force { await syncAccount() }
        }
    }
    private func refreshLiveCatalog() async {
        if let info = await fetchPublic({ try await service.gymInfo() }) { gym = info }
        if let plans = await fetchPublic({ try await service.offers() }) { offers = plans }
        guard phase == .authenticated, !locked else { return }
        if let places = await fetchKeepingSession({ try await service.gyms() }) {
            await resolveGym(from: places)
        }
        guard let gymID = selectedGymID else { return }
        if let available = await fetchKeepingSession({ try await service.availableSlots(gymID: gymID) }) {
            slots = available
        }
    }
    private func fetchPublic<T>(_ work: () async throws -> T) async -> T? {
        do { return try await work() }
        catch is CancellationError { return nil }
        catch {
            handle(error, surface: false)
            return nil
        }
    }
    func refreshInbox() async {
        guard phase == .authenticated, !locked else { return }
        do { inbox = try await service.inbox() }
        catch { handle(error, surface: false) }
    }
    func uploadPushToken(_ token: String, kind: String? = nil) async {
        if kind == "fcm" {
            notifications.fcmToken = token
            notifications.deviceToken = token
        } else if kind == "apns" {
            notifications.apnsToken = token
            if notifications.fcmToken == nil { notifications.deviceToken = token }
        } else {
            notifications.deviceToken = token
        }
        await sendPushRegistration()
    }
    func syncPushPreferences() async {
        AppDelegate.shared?.syncNotificationPreferences()
        await sendPushRegistration()
    }
    private func sendPushRegistration() async {
        guard phase == .authenticated, !isDemo, let token = notifications.deliveryToken else { return }
        do {
            try await service.registerPush(token: token, preferences: NotificationPreferencesStore.shared.apiPayload())
            notifications.registrationError = nil
        } catch {
            notifications.registrationError = L10n.tr("notifications.registration.failed")
        }
    }
}
