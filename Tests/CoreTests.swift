import Testing
import Foundation
@testable import Privofit

struct ValidationTests {
    @Test func usernameAndEmailLogin() {
        #expect(InputValidator.login("alex", "a"))
        #expect(InputValidator.login("alex@example.com", "password"))
        #expect(!InputValidator.login(" \n", "password"))
        #expect(!InputValidator.login("alex", ""))
    }
    @Test func registrationEmail() {
        #expect(InputValidator.email("alex+gym@example.com"))
        #expect(!InputValidator.email("alex@"))
        #expect(!InputValidator.email("a b@example.com"))
    }
    @Test func errorsDoNotLeakServerDetails() {
        let message = FriendlyError.message(AppFailure.notConfigured("SECRET internal service name"))
        #expect(!message.contains("SECRET"))
        #expect(FriendlyError.message(AppFailure.http(500)) == L10n.tr("error.generic"))
        #expect(FriendlyError.message(AppFailure.offline) == L10n.tr("error.offline"))
    }
}
@MainActor struct StateTests {
    private func app(_ service: MockGymService = MockGymService()) -> AppModel {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        return AppModel(service: service, preferences: Preferences(defaults: defaults), biometrics: UnavailableBiometrics())
    }
    @Test func guestOnboardingNeverCreatesMember() {
        let model = app(); model.enterGuest()
        #expect(model.phase == .onboarding); #expect(model.member == nil)
        model.finishOnboarding(); #expect(model.phase == .guest)
        model.requestDoor(); #expect(model.showGuestGate); #expect(!model.showDoor)
    }
    @Test func loginAndOnboardingDriveRootState() async {
        let model = app(); await model.boot(); #expect(model.phase == .signedOut)
        await model.login(identifier: "alex", password: "sample")
        #expect(model.phase == .authenticated)
        #expect(model.preferences.completedOnboarding(for: "demo-member"))
        await model.logout(); #expect(model.phase == .signedOut); #expect(model.member == nil)
        #expect(model.reservations.isEmpty)
    }
    @Test func blockedAccountCannotEnter() async {
        let service = MockGymService(); service.accountStatus = .blocked
        let model = app(service); await model.login(identifier: "alex", password: "sample")
        #expect(model.phase == .restricted(.blocked))
        model.finishOnboarding(); #expect(model.phase == .restricted(.blocked))
        model.requestDoor(); #expect(!model.showDoor)
    }
    @Test func unauthorizedClearsPrivateState() async {
        let model = app(); await model.login(identifier: "alex", password: "sample"); model.finishOnboarding()
        model.handle(AppFailure.unauthorized)
        #expect(model.phase == .sessionExpired); #expect(model.member == nil)
    }
    @Test func doorRejectsGuestAndServerDenial() async {
        let service = MockGymService(); let model = app(service)
        model.enterGuest(); model.finishOnboarding()
        let guestDoor = DoorModel(app: model, isActive: { true }); await guestDoor.restorePending(); await guestDoor.open()
        #expect(service.openCount == 0)
        model.requireLogin(); await model.login(identifier: "alex", password: "sample"); model.finishOnboarding()
        service.accessAllowed = false
        let door = DoorModel(app: model, isActive: { true }); await door.restorePending(); await door.open()
        if case .denied = door.state {} else { Issue.record("Expected server denial") }
        #expect(service.openCount == 0)
    }
    @Test func duplicateDoorRequestAndCooldown() async {
        let service = MockGymService(); let model = app(service)
        await model.login(identifier: "alex", password: "sample"); model.finishOnboarding()
        let door = DoorModel(app: model, isActive: { true }); await door.restorePending()
        let first = Task { await door.open() }
        let second = Task { await door.open() }
        await first.value; await second.value
        #expect(service.openCount == 1); #expect(door.state == .confirmed)
        let reopened = DoorModel(app: model, isActive: { true }); await reopened.restorePending(); await reopened.open()
        #expect(service.openCount == 1)
    }
    @Test func pushPreferencesPayload() {
        let defaults = UserDefaults(suiteName: "tests.push.\(UUID().uuidString)")!
        let store = NotificationPreferencesStore(defaults: defaults)
        store.masterEnabled = false
        store.setEnabled(.door, false)
        let payload = store.apiPayload()
        #expect(payload.enabled == false)
        #expect(payload.channels["door"] == false)
        #expect(payload.channels["reservations"] == true)
    }
    @Test func acceptedIsNotPhysicalSuccess() async {
        let service = MockGymService(); service.doorOutcome = .accepted
        let model = app(service); await model.login(identifier: "alex", password: "sample"); model.finishOnboarding()
        let door = DoorModel(app: model, isActive: { true }); await door.restorePending(); await door.open()
        #expect(door.state == .accepted)
        await door.open(); #expect(service.openCount == 1)
        await door.reconcile(); #expect(door.state == .accepted)
    }
    @Test func biometryFailureDoesNotOpenDoor() async {
        let service = MockGymService(); let model = app(service)
        await model.login(identifier: "alex", password: "sample"); model.finishOnboarding(); model.preferences.biometrics = true
        let door = DoorModel(app: model, isActive: { true }); await door.restorePending(); await door.open()
        #expect(service.openCount == 0)
        if case .failed = door.state {} else { Issue.record("Expected unavailable biometry failure") }
    }
}
