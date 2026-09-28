import SwiftUI
import UIKit

struct ReservationsView: View {
    @Environment(AppModel.self) private var app
    @State private var cancellation: Reservation?
    @State private var date = Date()
    @State private var loading = false
    @State private var mutating = false
    @State private var error: String?
    @State private var completed = false
    @State private var showGyms = false
    @State private var showCalendar = false
    @State private var checkout = ApplePayCheckout()
    private var calendar: Calendar { GymClock.calendar }
    private var slots: [AvailableSlot] { app.slots }
    private var visibleReservations: [Reservation] {
        guard let gym = selectedGym else { return app.reservations }
        return app.reservations.filter { item in
            item.gymID.isEmpty || item.gymID == gym.id
        }
    }
    private var daySlots: [AvailableSlot] { ReservationCalendar.slots(on: date, from: slots, calendar: calendar) }
    private var bookableDaySlots: [AvailableSlot] { daySlots.filter { !$0.mine } }
    private var dayBookings: [Reservation] { ReservationCalendar.reservations(on: date, from: visibleReservations, calendar: calendar) }
    private var upcoming: [Reservation] { ReservationCalendar.upcoming(app.reservations) }
    private var focusReservation: Reservation? {
        ReservationCalendar.current(app.reservations) ?? upcoming.first
    }
    private var timelineUpcoming: [Reservation] {
        guard let focus = focusReservation else { return upcoming }
        return upcoming.filter { $0.id != focus.id }
    }
    private var past: [Reservation] { ReservationCalendar.past(app.reservations) }
    private var sortedCart: [AvailableSlot] { app.bookingCart.sorted { $0.start < $1.start } }
    private var canGoBackMonth: Bool { !ReservationCalendar.isCurrentMonth(date, calendar: calendar) }
    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if app.isGuest { guestContent }
                else { memberContent }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !app.isGuest, !app.bookingCart.isEmpty, !app.showBookingCheckout {
                BookingCartDock(embedded: true)
            }
        }
        .brandBackground().navigationTitle(L10n.tr("tab.reservations")).mainToolbar()
            .navigationDestination(isPresented: $app.showBookingCheckout) {
                BookingSummaryView(slots: sortedCart, guests: app.bookingGuests, busy: mutating, error: error) { slot in
                    removeFromCart(slot)
                } pay: { quote in
                    Task { await payAndReserve(quote: quote, applePay: true) }
                } demoPay: {
                    Task { await payAndReserve(quote: nil, applePay: false) }
                }
            }
            .task { await load() }.refreshable { await load() }
            .onChange(of: app.slots) { _, available in
                app.reconcileBooking(available: available)
            }
            .sheet(isPresented: $showGyms) { gymSheet }
            .sheet(isPresented: $showCalendar) { calendarSheet }
            .confirmationDialog(L10n.tr("reservations.cancelConfirm"), isPresented: Binding(get: { cancellation != nil }, set: { if !$0 { cancellation = nil } }), titleVisibility: .visible, presenting: cancellation) { item in
                Button(L10n.tr("reservations.cancel"), role: .destructive) { Task { await cancel(item) } }
                Button(L10n.tr("common.notNow"), role: .cancel) { cancellation = nil }
            }
            .overlay(alignment: .top) {
                if completed {
                    ToastBanner(title: L10n.tr("reservations.paid"))
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: completed) {
                            try? await Task.sleep(nanoseconds: 2_600_000_000)
                            withAnimation(.easeInOut(duration: 0.25)) { completed = false }
                        }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: completed)
    }
    private var guestContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            StatusBadge(title: L10n.tr("guest.reservations"), symbol: "eye")
            Text(L10n.tr("guest.reservations.body")).foregroundStyle(.secondary)
            WeekDayStrip(
                selected: $date,
                slots: [],
                reservations: [],
                selection: [],
                onOpenMonth: { app.showGuestGate = true },
                onSelectDay: { _ in app.showGuestGate = true }
            )
            BrandCard { VStack(alignment: .leading, spacing: 16) {
                Label(L10n.tr("reservations.example"), systemImage: "calendar")
                Text(L10n.tr("reservations.example.time")).font(.title2.bold())
                PrimaryButton(title: L10n.tr("reservations.reserve")) { app.showGuestGate = true }
            } }
        }
    }
    private var memberContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            panePicker
            if let error, !app.showBookingCheckout { FailureView(message: error) { Task { await load() } } }
            if loading && slots.isEmpty && app.reservations.isEmpty { SkeletonCard() }
            if app.reservationSection == .slots { slotsPane } else { minePane }
        }
    }
    private var panePicker: some View {
            Picker(L10n.tr("tab.reservations"), selection: Binding(
                get: { app.reservationSection },
                set: { app.reservationSection = $0 }
            )) {
            Text(L10n.tr("reservations.tab.slots")).tag(ReservationSection.slots)
            Text(L10n.tr("reservations.tab.mine")).tag(ReservationSection.mine)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("reservations.panes")
    }
    private var gymSelector: some View {
        Button { showGyms = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Brand.ink)
                    .frame(width: 44, height: 44)
                    .background(Brand.lime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(selectedGym?.name ?? L10n.tr("reservations.gym.choose"))
                            .font(.headline)
                        if app.gymSuggestedByLocation {
                            Text(L10n.tr("reservations.gym.nearest"))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Brand.lime.opacity(0.35), in: Capsule())
                        }
                    }
                    if let address = selectedGym?.address {
                        Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("Surface"), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color("PrimaryText").opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reservations.gym")
    }
    private var gymSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if app.gyms.isEmpty {
                        Text(L10n.tr("reservations.gym.empty"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    ForEach(app.gyms) { gym in
                        Button { pick(gym) } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(gym.name).font(.headline)
                                    if !gym.address.isEmpty {
                                        Text(gym.address).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                if gym.id == app.selectedGymID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.limeDeep)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(gym.id == app.selectedGymID ? Brand.lime.opacity(0.28) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color("Background").ignoresSafeArea())
            .navigationTitle(L10n.tr("reservations.gym.choose"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) { showGyms = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color("Background"))
    }
    private var selectedGym: GymPlace? { app.gyms.first { $0.id == app.selectedGymID } }
    private func pick(_ gym: GymPlace) {
        showGyms = false
        guard gym.id != app.selectedGymID else { return }
        app.clearBooking()
        app.chooseGym(gym.id)
        Task { await load() }
    }
    private var slotsPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.tr("reservations.plan")).font(.title2.bold())
            Text(L10n.tr("reservations.selectHint")).font(.subheadline).foregroundStyle(.secondary)
            gymSelector
            WeekDayStrip(
                selected: $date,
                slots: slots.filter { !$0.mine },
                reservations: visibleReservations,
                selection: app.bookingCart,
                onOpenMonth: { showCalendar = true }
            )
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(dayTitle)
                    .font(.title3.bold())
                    .contentTransition(.opacity)
                Spacer(minLength: 8)
                Text(slotCountLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .animation(.snappy(duration: 0.22), value: date)
            if !dayBookings.isEmpty {
                MineDayBanner(count: dayBookings.count) {
                    app.reservationSection = .mine
                }
            }
            availability
        }
    }
    @ViewBuilder private var minePane: some View {
        if upcoming.isEmpty && past.isEmpty && !loading {
            BrandCard {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title)
                        .foregroundStyle(Brand.ink)
                        .frame(width: 52, height: 52)
                        .background(Brand.lime, in: RoundedRectangle(cornerRadius: 16))
                    Text(L10n.tr("reservations.mineEmpty")).font(.title3.bold())
                    Text(L10n.tr("reservations.mineEmptyHint")).font(.subheadline).foregroundStyle(.secondary)
                    Button(L10n.tr("reservations.tab.slots")) { app.reservationSection = .slots }.frame(minHeight: 44)
                }
            }
        } else {
            if let focus = focusReservation {
                NextSessionHero(reservation: focus) {
                    if focus.canCancel { cancellation = focus }
                }
                .disabled(mutating)
            }
            if !timelineUpcoming.isEmpty || !past.isEmpty {
                Text(L10n.tr("reservations.timeline")).font(.title2.bold())
                ReservationTimeline(
                    upcoming: timelineUpcoming,
                    past: past,
                    dayHeading: dayHeading,
                    disabled: mutating
                ) { item in
                    cancellation = item
                }
            }
        }
    }
    private var calendarSheet: some View {
        DayPickerSheet(
            date: $date,
            slots: slots.filter { !$0.mine },
            reservations: visibleReservations,
            selection: app.bookingCart,
            canGoBackMonth: canGoBackMonth,
            onDismiss: { showCalendar = false }
        )
    }
    private var dayAgenda: [DayAgendaItem] {
        let opens = bookableDaySlots.map { DayAgendaItem.open($0) }
        let booked = dayBookings.map { DayAgendaItem.booked($0) }
        return (opens + booked).sorted { $0.start < $1.start }
    }
    @ViewBuilder private var availability: some View {
        if dayAgenda.isEmpty && !loading {
            Text(L10n.tr("reservations.noSlots"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            DaySlotTimeline(
                items: dayAgenda,
                guests: app.bookingGuests,
                selectedIDs: Set(app.bookingCart.map(\.id)),
                cart: app.bookingCart,
                reservations: visibleReservations,
                disabled: mutating
            ) { slot in
                toggle(slot)
            } onMine: {
                app.reservationSection = .mine
            }
        }
    }
    private var dayTitle: String { dayHeading(date) }
    private func dayHeading(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return L10n.tr("reservations.today") }
        if calendar.isDateInTomorrow(day) { return L10n.tr("reservations.tomorrow") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
    private var slotCountLabel: String {
        if bookableDaySlots.isEmpty && !dayBookings.isEmpty {
            return dayBookings.count == 1 ? L10n.tr("reservations.bookedOnDayOne") : "\(dayBookings.count) \(L10n.tr("reservations.bookedOnDayMany"))"
        }
        switch bookableDaySlots.count {
        case 0: return L10n.tr("reservations.noSlots")
        case 1: return L10n.tr("reservations.slotsOne")
        default: return "\(bookableDaySlots.count) \(L10n.tr("reservations.slotsMany"))"
        }
    }
    private func toggle(_ slot: AvailableSlot) {
        let blocked = ReservationCalendar.conflicts(slot, reservations: visibleReservations, cart: app.bookingCart)
        app.toggleBooking(slot, blocked: blocked)
        if app.bookingCart.contains(where: { $0.id == slot.id }) { completed = false }
    }
    private func removeFromCart(_ slot: AvailableSlot) {
        app.removeBooking(slot)
    }
    private func load() async {
        guard !app.isGuest else { return }
        loading = true
        defer { loading = false }
        var lastError: Error?
        do {
            let bookings = try await app.service.reservations()
            guard !Task.isCancelled, app.phase == .authenticated else { return }
            app.reservations = bookings
            app.dropBookedSlots(bookings)
            app.publishWidgets()
        } catch is CancellationError {
            return
        } catch {
            lastError = error
            app.handle(error, surface: false)
        }
        var gymID = app.selectedGymID ?? ""
        do {
            let places = try await app.service.gyms()
            guard !Task.isCancelled, app.phase == .authenticated else { return }
            await app.resolveGym(from: places)
            gymID = app.selectedGymID ?? places.first?.id ?? ""
        } catch is CancellationError {
            return
        } catch {
            lastError = error
            app.handle(error, surface: false)
        }
        do {
            let available = try await app.service.availableSlots(gymID: gymID)
            guard !Task.isCancelled, app.phase == .authenticated else { return }
            app.slots = available
            app.reconcileBooking(available: available)
        } catch is CancellationError {
            return
        } catch {
            lastError = error
            app.handle(error, surface: false)
        }
        guard !Task.isCancelled else { return }
        date = ReservationCalendar.clampedDay(date)
        if let lastError { self.error = FriendlyError.message(lastError) } else { error = nil }
    }
    private func payAndReserve(quote: BookingQuote?, applePay useApplePay: Bool) async {
        guard !mutating, app.phase == .authenticated, !app.bookingCart.isEmpty else { return }
        mutating = true; error = nil
        defer { mutating = false }
        let requestID = app.bookingRequestID
        let guestCount = app.bookingGuests
        let slots = sortedCart.map(\.id)
        do {
            let payment: BookingPayment
            if useApplePay {
                guard let quote else { throw AppFailure.unavailable }
                payment = try await checkout.pay(quote: quote, guests: guestCount) { token in
                    try await app.service.payAndReserve(slotIDs: slots, requestID: requestID, applePay: token, guests: guestCount)
                }
            } else {
                payment = try await app.service.payAndReserve(slotIDs: slots, requestID: requestID, applePay: ApplePayCheckout.demoToken(), guests: guestCount)
            }
            if payment.status == .paid {
                app.clearBooking()
                app.reservationSection = .mine
                withAnimation { completed = true }
                await load()
            } else {
                self.error = L10n.tr("reservations.uncertain")
            }
        } catch let failure as AppFailure where failure == .cancelled {
            return
        } catch let failure as AppFailure where failure == .unavailable {
            self.error = L10n.tr("reservations.applePayFailed")
        } catch {
            app.handle(error, surface: false)
            await load()
            self.error = FriendlyError.message(error)
        }
    }
    private func cancel(_ item: Reservation) async {
        guard !mutating, app.phase == .authenticated else { return }
        mutating = true
        defer { mutating = false }
        cancellation = nil
        do {
            try await app.service.cancelReservation(id: item.id, requestID: UUID())
            app.reservations.removeAll { $0.id == item.id }
            app.publishWidgets()
            completed = false
            error = nil
            await load()
        } catch is CancellationError {
            return
        } catch {
            self.error = FriendlyError.message(error)
            app.handle(error, surface: false)
        }
    }
}

struct BookingCartDock: View {
    var embedded = false
    @Environment(AppModel.self) private var app
    private var estimate: Decimal { app.bookingCart.reduce(0) { $0 + ($1.price(for: app.bookingGuests) ?? 0) } }
    private var countLabel: String {
        app.bookingCart.count == 1 ? L10n.tr("reservations.cartOne") : "\(app.bookingCart.count) \(L10n.tr("reservations.cartMany"))"
    }
    private var priceLabel: String {
        estimate > 0 ? GymMoney.czk(estimate) : L10n.tr("reservations.checkoutHint")
    }
    private var usesMembership: Bool {
        guard let membership = app.membership, membership.isActive else { return false }
        let needed = max(1, app.bookingCart.count)
        if let left = membership.remainingEntries { return left >= needed }
        return true
    }
    private var entryLabel: String {
        let count = max(1, app.bookingCart.count)
        switch count {
        case 1: return "1 \(L10n.tr("reservations.entryOne"))"
        case 2...4: return "\(count) \(L10n.tr("reservations.checkoutCountMany"))"
        default: return "\(count) \(L10n.tr("reservations.entriesMany"))"
        }
    }
    private var personsWord: String {
        app.bookingGuests == 1
            ? L10n.tr("reservations.personOne")
            : (app.bookingGuests < 5 ? L10n.tr("reservations.personsFew") : L10n.tr("reservations.personsMany"))
    }
    private var detailLabel: String {
        let people = "\(app.bookingGuests) \(personsWord)"
        if usesMembership {
            return app.bookingGuests > 1 ? "\(people) · \(entryLabel)" : entryLabel
        }
        return app.bookingGuests > 1 ? "\(people) · \(priceLabel)" : priceLabel
    }
    private var actionTitle: String {
        usesMembership ? L10n.tr("reservations.reserve") : L10n.tr("reservations.checkout")
    }
    var body: some View {
        Group {
            if embedded { sheet } else { chip }
        }
        .accessibilityIdentifier("reservations.cartDock")
    }
    private var sheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                if app.bookingPersonLimit > 1 { personControl }
                VStack(alignment: .leading, spacing: 2) {
                    Text(countLabel).font(.headline)
                    Text(detailLabel).font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 8)
                clearButton
            }
            Button { app.openBookingCheckout() } label: {
                Text(actionTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(Brand.ink)
                    .background(Brand.lime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("Background"))
        .overlay(alignment: .top) { Divider() }
    }
    private var chipTitle: String {
        let count = app.bookingCart.count
        switch count {
        case 1: return "1 \(L10n.tr("reservations.slotShortOne"))"
        case 2...4: return "\(count) \(L10n.tr("reservations.slotShortFew"))"
        default: return "\(count) \(L10n.tr("reservations.slotShortMany"))"
        }
    }
    private var chip: some View {
        Button { app.openBookingCheckout() } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Brand.ink)
                    .frame(width: 36, height: 36)
                    .background(Brand.lime, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(chipTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(detailLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(L10n.tr("reservations.resume"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Brand.lime, in: Capsule())
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chipTitle), \(detailLabel)")
    }
    private var clearButton: some View {
        Button { app.clearBooking() } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr("reservations.clearCart"))
    }
    private var personControl: some View {
        HStack(spacing: 0) {
            Button {
                app.adjustBookingGuests(by: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(app.bookingGuests <= 1)
            .opacity(app.bookingGuests <= 1 ? 0.35 : 1)
            .accessibilityLabel(L10n.tr("reservations.personsLess"))

            Text("\(app.bookingGuests)")
                .font(.headline.monospacedDigit())
                .frame(minWidth: 22)
                .accessibilityLabel("\(app.bookingGuests) \(personsWord)")

            Button {
                app.adjustBookingGuests(by: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(app.bookingGuests >= app.bookingPersonLimit)
            .opacity(app.bookingGuests >= app.bookingPersonLimit ? 0.35 : 1)
            .accessibilityLabel(L10n.tr("reservations.personsMore"))
        }
        .padding(.horizontal, 2)
        .frame(height: 40)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .accessibilityElement(children: .contain)
    }
}

struct BookingSummaryView: View {
    let slots: [AvailableSlot]
    var guests = 1
    var busy = false
    var error: String?
    var onRemove: (AvailableSlot) -> Void
    var pay: (BookingQuote) -> Void
    var demoPay: () -> Void
    @State private var quote: BookingQuote?
    @State private var quoteError: String?
    @Environment(AppModel.self) private var app
    private var canPay: Bool { !slots.isEmpty && quote != nil && !busy }
    private var displaySlots: [AvailableSlot] { quote?.slots ?? slots }
    private var grouped: [(Date, [AvailableSlot])] { ReservationCalendar.groupedSlots(displaySlots) }
    private var rooms: [String] { ReservationCalendar.uniqueRooms(slots) }
    private var minutes: Int { ReservationCalendar.totalMinutes(slots) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summaryHero
                guestStepper
                statsRow
                whereSection
                whenSection
                if quote == nil && quoteError == nil { ProgressView().frame(maxWidth: .infinity).padding() }
                if app.isDemo { Text(L10n.tr("reservations.payDemo")).font(.footnote).foregroundStyle(.secondary) }
                if let message = error ?? quoteError { FailureView(message: message) }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .brandBackground()
        .navigationTitle(L10n.tr("reservations.checkoutTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(busy)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { payFooter }
        .task(id: quoteKey) { await loadQuote() }
    }
    private var quoteKey: String { slots.map(\.id).joined(separator: ",") + ":\(app.bookingGuests)" }
    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(slots.count)").font(.largeTitle.weight(.heavy)).monospacedDigit()
                Text(slots.count == 1 ? L10n.tr("reservations.entryOne") : L10n.tr("reservations.checkoutCountMany"))
                    .font(.title2.weight(.semibold))
            }
            if let room = rooms.first, rooms.count == 1 {
                Label("\(L10n.tr("reservations.intoRoom")) \(room)", systemImage: "mappin.and.ellipse")
                    .font(.title3.weight(.semibold))
            } else if !rooms.isEmpty {
                Label(rooms.joined(separator: " · "), systemImage: "mappin.and.ellipse")
                    .font(.title3.weight(.semibold))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Brand.ink)
        .background(LinearGradient(colors: [Color(hex: 0xD4F65E), Brand.lime], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
    private var guestStepper: some View {
        BrandCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("reservations.personsTitle"))
                        .font(.headline)
                    Text(L10n.tr("reservations.personsHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    Button { app.adjustBookingGuests(by: -1) } label: {
                        Image(systemName: "minus")
                            .font(.caption.weight(.bold))
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(app.bookingGuests <= 1 || busy)
                    .opacity(app.bookingGuests <= 1 ? 0.35 : 1)
                    .accessibilityLabel(L10n.tr("reservations.personsLess"))

                    Text("\(app.bookingGuests)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .frame(minWidth: 28)
                        .accessibilityLabel("\(app.bookingGuests) \(app.bookingGuests == 1 ? L10n.tr("reservations.personOne") : L10n.tr("reservations.personsFew"))")

                    Button { app.adjustBookingGuests(by: 1) } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(app.bookingGuests >= app.bookingPersonLimit || busy)
                    .opacity(app.bookingGuests >= app.bookingPersonLimit ? 0.35 : 1)
                    .accessibilityLabel(L10n.tr("reservations.personsMore"))
                }
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
        }
    }
    private var statsRow: some View {
        HStack(spacing: 10) {
            summaryStat(value: "\(slots.count)", label: slots.count == 1 ? L10n.tr("reservations.entryOne") : L10n.tr("reservations.checkoutCountMany"))
            summaryStat(value: "\(rooms.count)", label: rooms.count == 1 ? L10n.tr("reservations.roomOne") : L10n.tr("reservations.roomsMany"))
            summaryStat(value: "\(minutes)", label: L10n.tr("reservations.minutes"))
        }
    }
    private func summaryStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.08)))
    }
    private var whereSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("reservations.whereTitle")).font(.title2.bold())
            ForEach(rooms, id: \.self) { room in
                let count = slots.filter { $0.room == room }.count
                BrandCard {
                    HStack(spacing: 14) {
                        Image(systemName: "door.left.hand.open")
                            .font(.title2)
                            .foregroundStyle(Brand.ink)
                            .frame(width: 48, height: 48)
                            .background(Brand.lime, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(room).font(.headline)
                            Text(count == 1 ? L10n.tr("reservations.checkoutCountOne") : "\(count) \(L10n.tr("reservations.checkoutCountMany"))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("reservations.whenTitle")).font(.title2.bold())
            ForEach(grouped, id: \.0) { day, items in
                CheckoutDayCard(day: day, slots: items, guests: app.bookingGuests, quoted: quote != nil, busy: busy, onRemove: onRemove)
            }
        }
    }
    @ViewBuilder private var payFooter: some View {
        VStack(spacing: 14) {
            if let quote {
                amountBreakdown(quote)
            }
            if let quote, quote.total == 0 {
                PrimaryButton(title: L10n.tr("reservations.confirmAction"), symbol: "checkmark", busy: busy) { demoPay() }
                    .disabled(!canPay)
            } else if let quote, ApplePayCheckout.canMakePayments {
                ApplePayButton(enabled: canPay) { pay(quote) }
                    .frame(height: 58)
                    .accessibilityLabel(payTitle)
            } else if !app.isDemo {
                Text(L10n.tr("reservations.applePayUnavailable")).font(.footnote).foregroundStyle(.secondary)
            }
            if app.isDemo, (quote?.total ?? 1) != 0 {
                Button(L10n.tr("reservations.payDemoAction")) { demoPay() }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).frame(minHeight: 44)
                    .disabled(!canPay)
            }
            if busy { ProgressView() }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func amountBreakdown(_ quote: BookingQuote) -> some View {
        let guests = app.bookingGuests
        let lines = QuotePriceLines.make(quote: quote, cart: slots, guests: guests)
        VStack(alignment: .leading, spacing: 10) {
            if quote.total == 0 {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("reservations.fromMembership"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(L10n.tr("reservations.amountMembershipHint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(entryPhrase(quote.slots.count))
                        .font(.title3.bold())
                        .monospacedDigit()
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    breakdownRow(
                        title: quote.slots.count == 1
                            ? L10n.tr("reservations.amountBaseOne")
                            : "\(quote.slots.count)× \(L10n.tr("reservations.amountBaseMany"))",
                        value: quote.formatted(lines.baseTotal)
                    )
                    if lines.guestSurchargeTotal > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            breakdownRow(
                                title: quote.slots.count == 1
                                    ? L10n.tr("reservations.amountSurchargeOne")
                                    : "\(quote.slots.count)× \(L10n.tr("reservations.amountSurchargeMany"))",
                                value: quote.formatted(lines.guestSurchargeTotal)
                            )
                            Text(L10n.tr("reservations.amountSurchargeHint"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if guests > 1 {
                        Text(L10n.tr("reservations.amountTwoIncluded"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if lines.paymentFeeTotal > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            breakdownRow(
                                title: L10n.tr("reservations.amountCardFee"),
                                value: quote.formatted(lines.paymentFeeTotal)
                            )
                            Text(L10n.tr("reservations.amountCardFeeHint"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Divider().opacity(0.35)
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.tr("reservations.payFooter"))
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Text(quote.formatted(quote.total))
                            .font(.title.bold())
                            .monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func breakdownRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
    private func entryPhrase(_ count: Int) -> String {
        switch count {
        case 1: return "1 \(L10n.tr("reservations.entryOne"))"
        case 2...4: return "\(count) \(L10n.tr("reservations.checkoutCountMany"))"
        default: return "\(count) \(L10n.tr("reservations.entriesMany"))"
        }
    }
    private var payTitle: String {
        if let quote { return "\(L10n.tr("reservations.pay")) · \(quote.formatted(quote.total))" }
        return L10n.tr("reservations.pay")
    }
    private func loadQuote() async {
        guard !slots.isEmpty else { quote = nil; return }
        do {
            quote = try await app.service.quoteReservations(slotIDs: slots.map(\.id), guests: app.bookingGuests)
            quoteError = nil
        } catch {
            quote = nil
            quoteError = FriendlyError.message(error)
        }
    }
}

struct CheckoutDayCard: View {
    let day: Date
    let slots: [AvailableSlot]
    var guests = 1
    var quoted = false
    var busy = false
    var onRemove: (AvailableSlot) -> Void
    var body: some View {
        BrandCard {
            HStack(alignment: .top, spacing: 16) {
                DateBadge(date: day)
                VStack(spacing: 0) {
                    ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ReservationCalendar.occupiedRange(slot.start, slot.end, bufferMinutes: slot.bufferMinutes)).font(.headline.monospacedDigit())
                                Text(ReservationCalendar.bookingDetail(room: slot.room, price: slot.price(for: guests), currency: slot.currencyCode))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button {
                                onRemove(slot)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                                    .background(Color.primary.opacity(0.06), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                            .accessibilityLabel(L10n.tr("reservations.remove"))
                        }
                        .padding(.vertical, 8)
                        if index < slots.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
    }
}

struct NextSessionHero: View {
    let reservation: Reservation
    var onCancel: () -> Void
    private var live: Bool { ReservationCalendar.current([reservation]) != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(live ? L10n.tr("reservations.happening") : L10n.tr("reservations.nextSession"), systemImage: live ? "dot.radiowaves.left.and.right" : "sparkles")
                .font(.caption.weight(.semibold))
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(GymClock.format(reservation.start, Date.FormatStyle().weekday(.wide).day().month(.wide))).font(.subheadline.weight(.medium))
                    Text(ReservationCalendar.occupiedRange(reservation.start, reservation.end, bufferMinutes: reservation.bufferMinutes))
                        .font(.largeTitle.weight(.bold)).tracking(-0.8).monospacedDigit()
                    Text(ReservationCalendar.bookingDetail(room: reservation.room, price: reservation.price, currency: reservation.currencyCode) + reservation.partySuffix)
                        .font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            if reservation.canCancel {
                CancelReservationButton(emphasis: true, action: onCancel)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Brand.ink)
        .background(LinearGradient(colors: [Color(hex: 0xD4F65E), Brand.lime], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}

struct BookedSessionCard: View {
    let reservation: Reservation
    var style: Style = .upcoming
    var onCancel: (() -> Void)?
    enum Style { case upcoming, past }
    var body: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    DateBadge(date: reservation.start, muted: style == .past)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(style == .past ? L10n.tr("reservations.pastBadge") : L10n.tr("reservations.confirmedBadge"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(style == .past ? .secondary : Color("AccentColor"))
                        Text(ReservationCalendar.occupiedRange(reservation.start, reservation.end, bufferMinutes: reservation.bufferMinutes))
                            .font(.title3.bold()).monospacedDigit()
                        Text(ReservationCalendar.bookingDetail(room: reservation.room, price: reservation.price, currency: reservation.currencyCode) + reservation.partySuffix)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if style == .upcoming, reservation.canCancel, let onCancel {
                    CancelReservationButton(action: onCancel)
                }
            }
        }
        .opacity(style == .past ? 0.78 : 1)
        .accessibilityElement(children: .combine)
    }
}

struct DateBadge: View {
    let date: Date
    var muted = false
    var body: some View {
        VStack(spacing: 2) {
            Text(GymClock.format(date, Date.FormatStyle().weekday(.abbreviated))).font(.caption2.weight(.semibold)).textCase(.uppercase)
            Text(GymClock.format(date, Date.FormatStyle().day())).font(.title.bold()).monospacedDigit()
            Text(GymClock.format(date, Date.FormatStyle().month(.abbreviated))).font(.caption2.weight(.medium))
        }
        .foregroundStyle(muted ? Color.primary.opacity(0.55) : Brand.ink)
        .frame(width: 64)
        .padding(.vertical, 10)
        .background(muted ? Color.primary.opacity(0.08) : Brand.lime, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true)
    }
}

enum DayAgendaItem: Identifiable {
    case open(AvailableSlot)
    case booked(Reservation)

    var id: String {
        switch self {
        case .open(let slot): return "open-\(slot.id)"
        case .booked(let item): return "booked-\(item.id)"
        }
    }

    var start: Date {
        switch self {
        case .open(let slot): return slot.start
        case .booked(let item): return item.start
        }
    }
}

struct WeekDayStrip: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selected: Date
    let slots: [AvailableSlot]
    let reservations: [Reservation]
    var selection: [AvailableSlot] = []
    var onOpenMonth: () -> Void
    var onSelectDay: ((Date) -> Void)? = nil

    private var calendar: Calendar { GymClock.calendar }
    private var days: [Date] {
        let start = ReservationCalendar.startOfDay(Date(), calendar: calendar)
        let focus = ReservationCalendar.clampedDay(selected, calendar: calendar)
        let span = calendar.dateComponents([.day], from: start, to: focus).day ?? 0
        return ReservationCalendar.upcomingDays(count: max(21, span + 7), calendar: calendar)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(days, id: \.self) { day in
                            dayCell(day)
                                .id(ReservationCalendar.startOfDay(day, calendar: calendar))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity)
                .onAppear { scrollToSelected(proxy) }
                .onChange(of: selected) { _, _ in scrollToSelected(proxy) }
            }

            Button(action: onOpenMonth) {
                VStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.body.weight(.semibold))
                    Text(L10n.tr("reservations.monthShort"))
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(Brand.ink)
                .frame(width: 56, height: 72)
                .background(Brand.lime, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("reservations.pickDay"))
            .accessibilityHint(L10n.tr("reservations.pickDayHint"))
        }
        .padding(10)
        .background(Brand.surface(scheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Brand.text(scheme).opacity(0.08))
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let focused = calendar.isDate(day, inSameDayAs: selected)
        let today = calendar.isDateInToday(day)
        let free = ReservationCalendar.hasAvailability(slots, on: day, calendar: calendar)
        let mine = ReservationCalendar.hasReservation(reservations, on: day, calendar: calendar)
        let picked = ReservationCalendar.hasSelection(selection, on: day, calendar: calendar)
        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                selected = ReservationCalendar.clampedDay(day, calendar: calendar)
            }
            onSelectDay?(day)
        } label: {
            VStack(spacing: 6) {
                Text(day, format: .dateTime.weekday(.abbreviated))
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                Text(day, format: .dateTime.day())
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                HStack(spacing: 3) {
                    if free { Circle().fill(focused ? Brand.ink.opacity(0.55) : Brand.limeDeep).frame(width: 5, height: 5) }
                    if mine { Capsule().fill(focused ? Brand.ink.opacity(0.55) : Brand.sky).frame(width: 8, height: 4) }
                    if picked && !focused {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Brand.limeDeep)
                            .frame(width: 6, height: 4)
                    }
                    if !free && !mine && !picked {
                        Color.clear.frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .foregroundStyle(focused ? Brand.ink : Brand.text(scheme))
            .frame(width: 52, height: 72)
            .background(
                focused ? Brand.lime : (today ? Brand.lime.opacity(0.14) : Color.clear),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        focused ? Color.clear : (today ? Brand.limeDeep.opacity(0.55) : Brand.text(scheme).opacity(0.06)),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(focused ? .isSelected : [])
    }

    private func scrollToSelected(_ proxy: ScrollViewProxy) {
        let id = ReservationCalendar.startOfDay(selected, calendar: calendar)
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.25)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}

struct DaySlotTimeline: View {
    let items: [DayAgendaItem]
    var guests = 1
    var selectedIDs: Set<String> = []
    var cart: [AvailableSlot] = []
    var reservations: [Reservation] = []
    var disabled = false
    var onToggle: (AvailableSlot) -> Void
    var onMine: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                timelineRow(item, isLast: index == items.count - 1)
            }
        }
    }

    @ViewBuilder
    private func timelineRow(_ item: DayAgendaItem, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(item.start, format: .dateTime.hour().minute())
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                    .padding(.top, 18)
                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 8)
                }
            }
            .frame(width: 44)

            Group {
                switch item {
                case .open(let slot):
                    let selected = selectedIDs.contains(slot.id)
                    let blocked = ReservationCalendar.conflicts(slot, reservations: reservations, cart: cart)
                    SlotPickRow(
                        slot: slot,
                        guests: guests,
                        selected: selected,
                        overlapping: blocked && !selected
                    ) {
                        onToggle(slot)
                    }
                    .disabled(disabled || (blocked && !selected))
                case .booked(let reservation):
                    MineSlotRow(reservation: reservation, action: onMine)
                        .disabled(disabled)
                }
            }
            .padding(.bottom, isLast ? 0 : 12)
        }
    }
}

struct SlotPickRow: View {
    @Environment(\.colorScheme) private var scheme
    let slot: AvailableSlot
    var guests = 1
    var selected = false
    var overlapping = false
    var action: () -> Void

    private var duration: String {
        ReservationCalendar.durationLabel(
            minutes: ReservationCalendar.durationMinutes(from: slot.start, to: slot.end)
        )
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ReservationCalendar.occupiedRange(slot.start, slot.end, bufferMinutes: slot.bufferMinutes))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(selected ? Brand.ink : Brand.text(scheme))
                    HStack(spacing: 8) {
                        Text(duration)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selected ? Brand.ink.opacity(0.7) : .secondary)
                        Text("·")
                            .foregroundStyle(selected ? Brand.ink.opacity(0.45) : .secondary)
                        Text(ReservationCalendar.bookingDetail(room: slot.room, price: slot.price(for: guests), currency: slot.currencyCode))
                            .font(.caption)
                            .foregroundStyle(selected ? Brand.ink.opacity(0.7) : .secondary)
                            .lineLimit(1)
                    }
                    if overlapping {
                        Text(L10n.tr("reservations.overlap"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.danger)
                    } else if selected {
                        Text(L10n.tr("reservations.legend.selected"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.ink.opacity(0.72))
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : overlapping ? "exclamationmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(
                        overlapping ? Brand.danger :
                            selected ? Brand.ink : Brand.limeDeep
                    )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Brand.lime : Brand.surface(scheme),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        selected ? Brand.ink.opacity(0.18) :
                            overlapping ? Brand.danger.opacity(0.45) : Brand.text(scheme).opacity(0.08),
                        lineWidth: selected || overlapping ? 1.5 : 1
                    )
            )
            .opacity(overlapping && !selected ? 0.72 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(L10n.tr("reservations.reserve"))
    }
}

struct MineSlotRow: View {
    let reservation: Reservation
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Brand.sky)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ReservationCalendar.occupiedRange(reservation.start, reservation.end, bufferMinutes: reservation.bufferMinutes))
                        .font(.headline.monospacedDigit())
                    Text(L10n.tr("reservations.yours") + reservation.partySuffix)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.sky)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.sky.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Brand.sky.opacity(0.4), lineWidth: 1.25)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(L10n.tr("reservations.yours")), \(ReservationCalendar.occupiedRange(reservation.start, reservation.end, bufferMinutes: reservation.bufferMinutes))")
        .accessibilityHint(L10n.tr("reservations.goToMine"))
    }
}

struct MineDayBanner: View {
    let count: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Brand.sky)
                VStack(alignment: .leading, spacing: 2) {
                    Text(count == 1 ? L10n.tr("reservations.bookedOnDayOne") : "\(count) \(L10n.tr("reservations.bookedOnDayMany"))")
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.tr("reservations.goToMine"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Brand.sky.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Brand.sky.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ReservationTimeline: View {
    let upcoming: [Reservation]
    let past: [Reservation]
    var dayHeading: (Date) -> String
    var disabled = false
    var onCancel: (Reservation) -> Void

    private var rows: [(id: String, day: Date, item: Reservation, style: BookedSessionCard.Style, isLast: Bool)] {
        let future = upcoming.map { (day: $0.start, item: $0, style: BookedSessionCard.Style.upcoming) }
        let history = past.map { (day: $0.start, item: $0, style: BookedSessionCard.Style.past) }
        let all = future + history
        return all.enumerated().map { index, row in
            (
                id: row.item.id,
                day: row.day,
                item: row.item,
                style: row.style,
                isLast: index == all.count - 1
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.id) { row in
                timelineRow(row.day, reservation: row.item, style: row.style, isLast: row.isLast)
            }
        }
    }

    private func timelineRow(_ day: Date, reservation: Reservation, style: BookedSessionCard.Style, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(style == .past ? Color.primary.opacity(0.22) : Brand.sky)
                    .frame(width: 12, height: 12)
                    .padding(.top, 22)
                if !isLast {
                    Rectangle()
                        .fill(Brand.sky.opacity(style == .past ? 0.18 : 0.35))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            VStack(alignment: .leading, spacing: 10) {
                Text(dayHeading(day))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                BookedSessionCard(
                    reservation: reservation,
                    style: style,
                    onCancel: style == .upcoming && reservation.canCancel ? { onCancel(reservation) } : nil
                )
                .disabled(disabled)
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
    }
}

struct DayPickerSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var date: Date
    let slots: [AvailableSlot]
    let reservations: [Reservation]
    var selection: [AvailableSlot] = []
    var canGoBackMonth = true
    var onDismiss: () -> Void

    private var calendar: Calendar { GymClock.calendar }
    private var today: Date { ReservationCalendar.clampedDay(Date(), calendar: calendar) }
    private var tomorrow: Date {
        ReservationCalendar.clampedDay(
            calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
            calendar: calendar
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        quickPicks
                        MonthCalendar(
                            date: $date,
                            slots: slots,
                            reservations: reservations,
                            selection: selection,
                            canGoBack: canGoBackMonth,
                            onBack: { shiftMonth(-1) },
                            onForward: { shiftMonth(1) },
                            onDayPicked: onDismiss
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }

                Divider().opacity(0.35)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedHeading)
                            .font(.headline)
                        Text(selectedDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(L10n.tr("reservations.pickDayConfirm"), action: onDismiss)
                        .font(.headline)
                        .foregroundStyle(Brand.ink)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(Brand.lime, in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Brand.surface(scheme))
            }
            .brandBackground()
            .navigationTitle(L10n.tr("reservations.pickDay"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close"), action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color("Background"))
        .presentationCornerRadius(28)
    }

    private var quickPicks: some View {
        HStack(spacing: 10) {
            quickChip(
                title: L10n.tr("reservations.today"),
                selected: calendar.isDate(date, inSameDayAs: today)
            ) {
                pick(today)
            }
            quickChip(
                title: L10n.tr("reservations.tomorrow"),
                selected: calendar.isDate(date, inSameDayAs: tomorrow)
            ) {
                pick(tomorrow)
            }
            Spacer(minLength: 0)
        }
    }

    private func quickChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Brand.ink : Brand.text(scheme))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    selected ? Brand.lime : Brand.surface(scheme),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Color.clear : Brand.text(scheme).opacity(0.10),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var selectedHeading: String {
        if calendar.isDateInToday(date) { return L10n.tr("reservations.today") }
        if calendar.isDateInTomorrow(date) { return L10n.tr("reservations.tomorrow") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var selectedDetail: String {
        let open = ReservationCalendar.slots(on: date, from: slots, calendar: calendar).filter { !$0.mine }.count
        let mine = ReservationCalendar.reservations(on: date, from: reservations, calendar: calendar).count
        if open == 0 && mine > 0 {
            return mine == 1 ? L10n.tr("reservations.bookedOnDayOne") : "\(mine) \(L10n.tr("reservations.bookedOnDayMany"))"
        }
        switch open {
        case 0: return L10n.tr("reservations.noSlots")
        case 1: return L10n.tr("reservations.slotsOne")
        default: return "\(open) \(L10n.tr("reservations.slotsMany"))"
        }
    }

    private func pick(_ day: Date) {
        withAnimation(.snappy(duration: 0.22)) {
            date = ReservationCalendar.clampedDay(day, calendar: calendar)
        }
        onDismiss()
    }

    private func shiftMonth(_ value: Int) {
        withAnimation(.snappy(duration: 0.25)) {
            let shifted = ReservationCalendar.shiftMonth(date, by: value, calendar: calendar)
            date = value < 0
                ? ReservationCalendar.clampedDay(shifted, calendar: calendar)
                : ReservationCalendar.startOfDay(shifted, calendar: calendar)
        }
    }
}

struct MonthCalendar: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var date: Date
    let slots: [AvailableSlot]
    let reservations: [Reservation]
    var selection: [AvailableSlot] = []
    var canGoBack = true
    var onBack: () -> Void
    var onForward: () -> Void
    var onDayPicked: (() -> Void)? = nil
    private var calendar: Calendar { GymClock.calendar }
    private var days: [CalendarDay] { ReservationCalendar.monthGrid(containing: date, calendar: calendar) }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 6), count: 7) }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                monthButton(systemName: "chevron.left", label: L10n.tr("reservations.previousMonth"), enabled: canGoBack, action: onBack)
                Text(date.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                monthButton(systemName: "chevron.right", label: L10n.tr("reservations.nextMonth"), enabled: true, action: onForward)
            }

            HStack(spacing: 0) {
                ForEach(Array(ReservationCalendar.shortWeekdayLabels(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(days, id: \.date) { day in
                    dayButton(day)
                }
            }

            HStack(spacing: 14) {
                legendMark(.free, title: L10n.tr("reservations.legend.free"))
                legendMark(.mine, title: L10n.tr("reservations.legend.mine"))
                legendMark(.picked, title: L10n.tr("reservations.legend.selected"))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .padding(18)
        .background(Brand.surface(scheme), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Brand.text(scheme).opacity(0.06))
        )
        .accessibilityIdentifier("reservations.calendar")
    }

    private enum DayMark { case free, mine, picked }

    private func monthButton(systemName: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(enabled ? Brand.ink : Color.primary.opacity(0.28))
                .frame(width: 40, height: 40)
                .background(enabled ? Brand.lime : Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func dayButton(_ day: CalendarDay) -> some View {
        let focused = calendar.isDate(day.date, inSameDayAs: date)
        let past = ReservationCalendar.isPastDay(day.date)
        let today = calendar.isDateInToday(day.date)
        let mine = ReservationCalendar.hasReservation(reservations, on: day.date)
        let picked = ReservationCalendar.hasSelection(selection, on: day.date)
        let free = ReservationCalendar.hasAvailability(slots, on: day.date)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                date = ReservationCalendar.clampedDay(day.date, calendar: calendar)
            }
            onDayPicked?()
        } label: {
            VStack(spacing: 5) {
                Text(day.date, format: .dateTime.day())
                    .font(.body.weight(today || focused ? .bold : .medium))
                    .monospacedDigit()
                    .frame(width: 42, height: 42)
                    .foregroundStyle(foreground(focused: focused, past: past, inMonth: day.inMonth))
                    .background {
                        if focused {
                            Circle().fill(Brand.lime)
                        } else if mine {
                            Circle().fill(Brand.sky.opacity(0.18))
                        } else if picked {
                            Circle().fill(Brand.lime.opacity(0.18))
                        } else if free && day.inMonth && !past {
                            Circle().fill(Brand.lime.opacity(0.10))
                        }
                    }
                    .overlay {
                        if focused {
                            EmptyView()
                        } else if mine {
                            Circle().strokeBorder(Brand.sky, lineWidth: 1.5)
                        } else if today {
                            Circle().strokeBorder(Brand.limeDeep.opacity(0.85), lineWidth: 1.4)
                        }
                    }
                dayMarks(mine: mine, picked: picked, free: free && !mine && !picked && !past)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(past || !day.inMonth)
        .opacity(day.inMonth ? (past ? 0.35 : 1) : 0.22)
        .accessibilityLabel(dayLabel(day, mine: mine, picked: picked, free: free))
        .accessibilityAddTraits(focused ? .isSelected : [])
        .accessibilityHidden(!day.inMonth)
    }

    @ViewBuilder
    private func dayMarks(mine: Bool, picked: Bool, free: Bool) -> some View {
        HStack(spacing: 3) {
            if mine {
                Capsule().fill(Brand.sky).frame(width: 9, height: 4)
            }
            if picked {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Brand.limeDeep)
                    .frame(width: 7, height: 4)
            }
            if free {
                Circle().fill(Brand.limeDeep).frame(width: 4, height: 4)
            }
            if !mine && !picked && !free {
                Color.clear.frame(width: 4, height: 4)
            }
        }
        .frame(height: 6)
    }

    private func dayLabel(_ day: CalendarDay, mine: Bool, picked: Bool, free: Bool) -> String {
        var text = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if mine { text += ", \(L10n.tr("reservations.legend.mine"))" }
        if picked { text += ", \(L10n.tr("reservations.legend.selected"))" }
        if free { text += ", \(L10n.tr("reservations.legend.free"))" }
        return text
    }

    private func foreground(focused: Bool, past: Bool, inMonth: Bool) -> Color {
        if focused { return Brand.ink }
        if past || !inMonth { return Color.primary.opacity(0.35) }
        return Brand.text(scheme)
    }

    private func legendMark(_ mark: DayMark, title: String) -> some View {
        HStack(spacing: 6) {
            switch mark {
            case .free:
                Circle().fill(Brand.limeDeep).frame(width: 6, height: 6)
            case .mine:
                Capsule().fill(Brand.sky).frame(width: 10, height: 5)
            case .picked:
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Brand.limeDeep)
                    .frame(width: 7, height: 5)
            }
            Text(title)
        }
    }
}

struct ReservationSummary: View {
    let reservation: Reservation
    var hidesDay = false
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if !hidesDay { DateBadge(date: reservation.start) }
            VStack(alignment: .leading, spacing: 6) {
                if hidesDay {
                    Text(relativeDay).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(ReservationCalendar.occupiedRange(reservation.start, reservation.end, bufferMinutes: reservation.bufferMinutes)).font(.title3.bold()).monospacedDigit()
                Text(ReservationCalendar.bookingDetail(room: reservation.room, price: reservation.price, currency: reservation.currencyCode) + reservation.partySuffix)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }
    private var relativeDay: String {
        if GymClock.calendar.isDateInToday(reservation.start) { return L10n.tr("reservations.today") }
        if GymClock.calendar.isDateInTomorrow(reservation.start) { return L10n.tr("reservations.tomorrow") }
        return GymClock.format(reservation.start, Date.FormatStyle().weekday(.wide).day().month())
    }
}
