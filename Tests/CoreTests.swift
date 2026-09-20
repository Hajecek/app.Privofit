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
    @Test func reservationCalendarPlansWeekAndConflicts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "cs_CZ")
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 12))!
        let week = ReservationCalendar.week(containing: wednesday, calendar: calendar)
        #expect(week.count == 7)
        #expect(calendar.component(.weekday, from: week[0]) == 2)
        #expect(calendar.isDate(week[2], inSameDayAs: wednesday))

        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 17))!
        let slot = AvailableSlot(id: "s1", start: start, end: start.addingTimeInterval(3600), room: "PRIVOFIT / 01")
        let booking = Reservation(id: "r1", start: start.addingTimeInterval(1800), end: start.addingTimeInterval(5400), room: "PRIVOFIT / 01", canCancel: true)
        #expect(ReservationCalendar.overlaps(slot, with: [booking]))
        #expect(ReservationCalendar.next([booking], now: start.addingTimeInterval(-60))?.id == "r1")
        #expect(ReservationCalendar.upcoming([booking], now: start.addingTimeInterval(10_000)).isEmpty)
        #expect(ReservationCalendar.groupedByDayPart([slot], calendar: calendar).map(\.0) == [.evening])
        #expect(ReservationCalendar.durationMinutes(from: slot.start, to: slot.end) == 60)
        #expect(!ReservationCalendar.isPastDay(wednesday, now: wednesday, calendar: calendar))
    }
    @Test func demoSlotsCoverUpcomingDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 9))!
        let slots = MockGymService.demoSlots(now: now, calendar: calendar)
        #expect(!slots.isEmpty)
        let days = Set(slots.map { calendar.startOfDay(for: $0.start) })
        #expect(days.count > 5)
        #expect(slots.allSatisfy { $0.start > now })
        #expect(!slots.contains { calendar.component(.weekday, from: $0.start) == 1 })
    }
    @Test func selectedSlotsCanBePaidTogether() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 9))!
        let first = AvailableSlot(id: "a", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200), room: "PRIVOFIT / 01")
        let second = AvailableSlot(id: "b", start: now.addingTimeInterval(8000), end: now.addingTimeInterval(11600), room: "PRIVOFIT / 01")
        let clash = AvailableSlot(id: "c", start: now.addingTimeInterval(5400), end: now.addingTimeInterval(9000), room: "PRIVOFIT / 01")
        #expect(!ReservationCalendar.conflicts(first, reservations: [], cart: [second]))
        #expect(ReservationCalendar.conflicts(clash, reservations: [], cart: [first]))

        let service = MockGymService()
        let model = app(service)
        await model.login(identifier: "alex", password: "sample")
        let slots = try await service.availableSlots()
        let pick = Array(slots.prefix(2))
        #expect(pick.count == 2)
        let quote = try await service.quoteReservations(slotIDs: pick.map(\.id))
        #expect(quote.slots.count == 2)
        #expect(quote.total == Decimal(700))
        let request = UUID()
        let paid = try await service.payAndReserve(slotIDs: pick.map(\.id), requestID: request)
        #expect(paid.status == .paid)
        #expect(paid.reservations.count == 2)
        _ = try await service.payAndReserve(slotIDs: pick.map(\.id), requestID: request)
        #expect(service.checkoutCount == 1)
        let bookings = try await service.reservations()
        #expect(bookings.count == 2)
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
