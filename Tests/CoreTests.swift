import Testing
import Foundation
import PassKit
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
    @Test func registrationUsernameAndPassword() {
        #expect(InputValidator.username("haj8cek"))
        #expect(!InputValidator.username("Jan Novak"))
        #expect(InputValidator.password("silne-heslo-12"))
        #expect(!InputValidator.password("kratke"))
        #expect(FriendlyError.message(AppFailure.rejected("Heslo musí mít alespoň 12 znaků.")) == "Heslo musí mít alespoň 12 znaků.")
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
    @Test func unauthorizedKeepsTheSignedInSession() async {
        let model = app(); await model.login(identifier: "alex", password: "sample"); model.finishOnboarding()
        model.handle(AppFailure.unauthorized)
        #expect(model.phase == .authenticated); #expect(model.member != nil)
    }
    @Test func cancelledRequestDoesNotSurfaceError() {
        let model = app()
        model.handle(CancellationError())
        #expect(model.error == nil)
    }
    @Test func syncPicksUpRemoteBlockAndMembership() async {
        let service = MockGymService()
        let model = app(service)
        await model.login(identifier: "alex", password: "sample")
        #expect(model.phase == .authenticated)
        service.accountStatus = .blocked
        await model.syncAccount()
        #expect(model.phase == .restricted(.blocked))
        #expect(model.showDoor == false)
        service.accountStatus = .active
        await model.syncAccount()
        #expect(model.phase == .authenticated)
        service.inactiveMembership = true
        await model.syncAccount()
        #expect(model.membership?.isActive == false)
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
        #expect(ReservationCalendar.durationMinutes(from: slot.start, to: slot.occupiedUntil) == 75)
        #expect(GymMoney.czk(150) == "150 Kč")
        #expect(GymMoney.czk(1990) == "1 990 Kč")
        #expect(!ReservationCalendar.isPastDay(wednesday, now: wednesday, calendar: calendar))
        let grid = ReservationCalendar.monthGrid(containing: wednesday, calendar: calendar)
        #expect(grid.count == 35 || grid.count == 42)
        #expect(grid.contains { $0.inMonth && calendar.isDate($0.date, inSameDayAs: wednesday) })
        #expect(ReservationCalendar.weekdaySymbols(calendar: calendar).count == 7)
        #expect(ReservationCalendar.shortWeekdayLabels(calendar: calendar).count == 7)
        let grouped = ReservationCalendar.groupedByDay([booking], calendar: calendar)
        #expect(grouped.count == 1)
        #expect(grouped[0].1.count == 1)
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
        let second = AvailableSlot(id: "b", start: now.addingTimeInterval(8100), end: now.addingTimeInterval(11700), room: "PRIVOFIT / 01")
        let clash = AvailableSlot(id: "c", start: now.addingTimeInterval(5400), end: now.addingTimeInterval(9000), room: "PRIVOFIT / 01")
        #expect(!ReservationCalendar.conflicts(first, reservations: [], cart: [second]))
        #expect(ReservationCalendar.conflicts(clash, reservations: [], cart: [first]))

        let service = MockGymService()
        let model = app(service)
        await model.login(identifier: "alex", password: "sample")
        let slots = try await service.availableSlots(gymID: "vinohrady")
        let pick = Array(slots.prefix(2))
        #expect(pick.count == 2)
        let quote = try await service.quoteReservations(slotIDs: pick.map(\.id))
        #expect(quote.slots.count == 2)
        #expect(quote.total == Decimal(700))
        let request = UUID()
        let token = ApplePayCheckout.demoToken()
        let paid = try await service.payAndReserve(slotIDs: pick.map(\.id), requestID: request, applePay: token)
        #expect(paid.status == .paid)
        #expect(paid.reservations.count == 2)
        _ = try await service.payAndReserve(slotIDs: pick.map(\.id), requestID: request, applePay: token)
        #expect(service.checkoutCount == 1)
        let applePay = ApplePayCheckout.paymentRequest(quote: quote, merchantID: "merchant.cz.privofit.app", merchantName: "Privofit")
        #expect(applePay.currencyCode == "CZK")
        #expect(applePay.countryCode == "CZ")
        #expect(applePay.merchantIdentifier == "merchant.cz.privofit.app")
        #expect(applePay.paymentSummaryItems.last?.amount == NSDecimalNumber(decimal: quote.total))
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
        #expect(door.state.isFailure)
        if case .failed = door.state {} else { Issue.record("Expected unavailable biometry failure") }
    }
    @Test func presenceFollowsReservedSlot() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        calendar.locale = Locale(identifier: "cs_CZ")
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 12))!
        let booking = Reservation(id: "mine", start: start, end: start.addingTimeInterval(3600), room: "PRIVOFIT / 01", canCancel: true)
        let during = start.addingTimeInterval(20 * 60)
        if case .occupied(let active) = GymPresence.resolve([booking], now: during) {
            #expect(active.id == "mine")
        } else {
            Issue.record("Expected an active reservation")
        }
        let before = GymPresence.resolve([booking], now: start.addingTimeInterval(-60))
        #expect(before == .vacant)
        let afterSession = GymPresence.resolve([booking], now: booking.end.addingTimeInterval(60))
        #expect(afterSession == .vacant)
        #expect(GymPresence.resolve([], now: during) == .vacant)
        let nearSmichov = GymLocator.nearest(MockGymService.places, to: 50.071, longitude: 14.406)
        #expect(nearSmichov?.id == "smichov")
        let nearKarlin = GymLocator.nearest(MockGymService.places, to: 50.094, longitude: 14.450)
        #expect(nearKarlin?.id == "karlin")
    }
    @Test func streakCountsWeeksWithAtLeastOneSession() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        calendar.locale = Locale(identifier: "cs_CZ")
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 15))!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 18))!
        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 18))!
        let tonight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 18))!
        let visits = [
            Visit(id: "m", date: monday, room: "PRIVOFIT / 01"),
            Visit(id: "t", date: tuesday, room: "PRIVOFIT / 01")
        ]
        let planned = Reservation(id: "later", start: tonight, end: tonight.addingTimeInterval(3600), room: "PRIVOFIT / 01", canCancel: true)
        let summary = TrainingStreak.summary(reservations: [planned], visits: visits, now: now, calendar: calendar)
        #expect(summary.length == 1)
        #expect(!summary.todayTrained)
        #expect(!summary.atRisk)
        #expect(summary.week.contains { calendar.isDate($0.date, inSameDayAs: now) && $0.planned && !$0.trained })

        let earlier = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 9))!
        let done = Reservation(id: "done", start: earlier, end: earlier.addingTimeInterval(3600), room: "PRIVOFIT / 01", canCancel: true)
        let continued = TrainingStreak.summary(reservations: [done], visits: visits, now: now, calendar: calendar)
        #expect(continued.todayTrained)
        #expect(continued.length == 1)
    }

    @Test func streakSurvivesRestDaysInsideTheWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        calendar.locale = Locale(identifier: "cs_CZ")
        calendar.firstWeekday = 2
        let lastWeek = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 18))!
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 15))!
        let held = TrainingStreak.summary(reservations: [], visits: [Visit(id: "last", date: lastWeek, room: "PRIVOFIT / 01")], now: wednesday, calendar: calendar)
        #expect(held.length == 1)
        #expect(!held.atRisk)

        let sunday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 15))!
        let closing = TrainingStreak.summary(reservations: [], visits: [Visit(id: "last", date: lastWeek, room: "PRIVOFIT / 01")], now: sunday, calendar: calendar)
        #expect(closing.length == 1)
        #expect(closing.atRisk)

        let older = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 18))!
        let thisWeek = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 10))!
        let gapped = TrainingStreak.summary(
            reservations: [],
            visits: [
                Visit(id: "old", date: older, room: "PRIVOFIT / 01"),
                Visit(id: "now", date: thisWeek, room: "PRIVOFIT / 01")
            ],
            now: wednesday,
            calendar: calendar
        )
        #expect(gapped.length == 1)
    }
}
