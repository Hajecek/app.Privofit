import SwiftUI
import UIKit

struct ReservationsView: View {
    @Environment(AppModel.self) private var app
    @State private var cart: [AvailableSlot] = []
    @State private var showCheckout = false
    @State private var cancellation: Reservation?
    @State private var date = Date()
    @State private var loading = false
    @State private var mutating = false
    @State private var error: String?
    @State private var completed = false
    @State private var checkoutID = UUID()
    @State private var showGyms = false
    @State private var checkout = ApplePayCheckout()
    private var calendar: Calendar { GymClock.calendar }
    private var slots: [AvailableSlot] { app.slots }
    private var daySlots: [AvailableSlot] { ReservationCalendar.slots(on: date, from: slots, calendar: calendar) }
    private var dayBookings: [Reservation] { ReservationCalendar.reservations(on: date, from: app.reservations, calendar: calendar) }
    private var upcoming: [Reservation] { ReservationCalendar.upcoming(app.reservations) }
    private var laterUpcoming: [Reservation] { Array(upcoming.dropFirst()) }
    private var past: [Reservation] { ReservationCalendar.past(app.reservations) }
    private var sortedCart: [AvailableSlot] { cart.sorted { $0.start < $1.start } }
    private var canGoBackMonth: Bool { !ReservationCalendar.isCurrentMonth(date, calendar: calendar) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if app.isGuest { guestContent }
                else { memberContent }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { if !app.isGuest && !cart.isEmpty && !showCheckout { cartBar } }
        .brandBackground().navigationTitle(L10n.tr("tab.reservations")).mainToolbar()
            .navigationDestination(isPresented: $showCheckout) {
                BookingSummaryView(slots: sortedCart, busy: mutating, error: error) { slot in
                    removeFromCart(slot)
                } pay: { quote in
                    Task { await payAndReserve(quote: quote, applePay: true) }
                } demoPay: {
                    Task { await payAndReserve(quote: nil, applePay: false) }
                }
            }
            .task { await load() }.refreshable { await load() }
            .onChange(of: app.slots) { _, available in
                cart.removeAll { booked in !available.contains(where: { $0.id == booked.id }) }
            }
            .sheet(isPresented: $showGyms) { gymSheet }
            .confirmationDialog(L10n.tr("reservations.cancelConfirm"), isPresented: Binding(get: { cancellation != nil }, set: { if !$0 { cancellation = nil } }), titleVisibility: .visible, presenting: cancellation) { item in
                Button(L10n.tr("reservations.cancel"), role: .destructive) { Task { await cancel(item) } }
                Button(L10n.tr("common.notNow"), role: .cancel) { cancellation = nil }
            }
    }
    private var guestContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            StatusBadge(title: L10n.tr("guest.reservations"), symbol: "eye")
            Text(L10n.tr("guest.reservations.body")).foregroundStyle(.secondary)
            MonthCalendar(date: $date, slots: [], reservations: [], selection: [], canGoBack: false, onBack: {}, onForward: {})
                .disabled(true)
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
            if let error, !showCheckout { FailureView(message: error) { Task { await load() } } }
            if completed { StatusBadge(title: L10n.tr("reservations.paid")) }
            if loading { SkeletonCard() }
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
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reservations.gym")
    }
    private var gymSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(app.gyms) { gym in
                        Button { pick(gym) } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(gym.name).font(.headline)
                                    Text(gym.address).font(.subheadline).foregroundStyle(.secondary)
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
                }.padding(24)
            }
            .brandBackground()
            .navigationTitle(L10n.tr("reservations.gym.choose"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) { showGyms = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    private var selectedGym: GymPlace? { app.gyms.first { $0.id == app.selectedGymID } }
    private func pick(_ gym: GymPlace) {
        showGyms = false
        guard gym.id != app.selectedGymID else { return }
        cart = []
        app.chooseGym(gym.id)
        Task { await load() }
    }
    private var slotsPane: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L10n.tr("reservations.plan")).font(.title2.bold())
            Text(L10n.tr("reservations.selectHint")).font(.subheadline).foregroundStyle(.secondary)
            gymSelector
            MonthCalendar(
                date: $date,
                slots: slots,
                reservations: app.reservations,
                selection: cart,
                canGoBack: canGoBackMonth,
                onBack: { date = ReservationCalendar.clampedDay(ReservationCalendar.shiftMonth(date, by: -1, calendar: calendar), calendar: calendar) },
                onForward: {
                    date = ReservationCalendar.startOfDay(ReservationCalendar.shiftMonth(date, by: 1, calendar: calendar), calendar: calendar)
                }
            )
            dayHeader
            if !dayBookings.isEmpty {
                Button {
                    app.reservationSection = .mine
                } label: {
                    BrandCard {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color("AccentColor"))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dayBookings.count == 1 ? L10n.tr("reservations.bookedOnDayOne") : "\(dayBookings.count) \(L10n.tr("reservations.bookedOnDayMany"))")
                                    .font(.headline)
                                Text(L10n.tr("reservations.goToMine")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.tr("reservations.goToMine"))
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
            if let next = upcoming.first {
                NextSessionHero(reservation: next) {
                    if next.canCancel { cancellation = next }
                }
                .disabled(mutating)
            }
            if !laterUpcoming.isEmpty {
                Text(L10n.tr("reservations.mine")).font(.title2.bold())
                ForEach(ReservationCalendar.groupedByDay(laterUpcoming, calendar: calendar), id: \.0) { day, items in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(dayHeading(day)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(items) { item in
                            BookedSessionCard(reservation: item, style: .upcoming) {
                                cancellation = item
                            }
                            .disabled(mutating)
                        }
                    }
                }
            }
            if !past.isEmpty {
                Text(L10n.tr("reservations.past")).font(.title2.bold()).padding(.top, upcoming.isEmpty ? 0 : 8)
                ForEach(ReservationCalendar.groupedByDay(past, descending: true, calendar: calendar), id: \.0) { day, items in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(dayHeading(day)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(items) { item in
                            BookedSessionCard(reservation: item, style: .past, onCancel: nil)
                        }
                    }
                }
            }
        }
    }
    private var cartBar: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cartCountLabel).font(.headline)
                    Text(L10n.tr("reservations.checkoutHint")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.tr("reservations.clearCart")) { clearCart() }.font(.subheadline)
            }
            PrimaryButton(title: L10n.tr("reservations.checkout"), symbol: "wallet.pass", busy: mutating) {
                error = nil
                showCheckout = true
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }
    private var dayHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayTitle).font(.title3.bold())
            Text(slotCountLabel).font(.subheadline).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var availability: some View {
        if daySlots.isEmpty && !loading {
            Text(L10n.tr("reservations.noSlots")).foregroundStyle(.secondary)
        } else {
            ForEach(ReservationCalendar.groupedByDayPart(daySlots, calendar: calendar), id: \.0) { part, items in
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.tr("reservations.period.\(part.rawValue)")).font(.headline)
                    ForEach(items) { slot in
                        let selected = cart.contains(where: { $0.id == slot.id })
                        let blocked = ReservationCalendar.conflicts(slot, reservations: app.reservations, cart: cart)
                        SlotRow(slot: slot, selected: selected, overlapping: blocked && !selected) {
                            toggle(slot)
                        }
                        .disabled(mutating || (blocked && !selected))
                    }
                }
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
        switch daySlots.count {
        case 0: return L10n.tr("reservations.noSlots")
        case 1: return L10n.tr("reservations.slotsOne")
        default: return "\(daySlots.count) \(L10n.tr("reservations.slotsMany"))"
        }
    }
    private var cartCountLabel: String {
        cart.count == 1 ? L10n.tr("reservations.cartOne") : "\(cart.count) \(L10n.tr("reservations.cartMany"))"
    }
    private func toggle(_ slot: AvailableSlot) {
        if let index = cart.firstIndex(where: { $0.id == slot.id }) {
            cart.remove(at: index)
            checkoutID = UUID()
            return
        }
        guard !ReservationCalendar.conflicts(slot, reservations: app.reservations, cart: cart) else { return }
        cart.append(slot)
        checkoutID = UUID()
        completed = false
    }
    private func removeFromCart(_ slot: AvailableSlot) {
        cart.removeAll { $0.id == slot.id }
        checkoutID = UUID()
        if cart.isEmpty { showCheckout = false }
    }
    private func clearCart() {
        cart = []
        checkoutID = UUID()
        showCheckout = false
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
            cart.removeAll { booked in bookings.contains(where: { $0.id == booked.id }) }
        } catch is CancellationError {
            return
        } catch {
            lastError = error
            app.handle(error, surface: false)
        }
        do {
            let places = try await app.service.gyms()
            guard !Task.isCancelled, app.phase == .authenticated else { return }
            await app.resolveGym(from: places)
            let available = try await app.service.availableSlots(gymID: app.selectedGymID ?? places.first?.id ?? "")
            guard !Task.isCancelled, app.phase == .authenticated else { return }
            app.slots = available
            cart.removeAll { booked in !available.contains(where: { $0.id == booked.id }) }
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
        guard !mutating, app.phase == .authenticated, !cart.isEmpty else { return }
        mutating = true; error = nil
        defer { mutating = false }
        let requestID = checkoutID
        let slots = sortedCart.map(\.id)
        do {
            let payment: BookingPayment
            if useApplePay {
                guard let quote else { throw AppFailure.unavailable }
                payment = try await checkout.pay(quote: quote) { token in
                    try await app.service.payAndReserve(slotIDs: slots, requestID: requestID, applePay: token)
                }
            } else {
                payment = try await app.service.payAndReserve(slotIDs: slots, requestID: requestID, applePay: ApplePayCheckout.demoToken())
            }
            if payment.status == .paid {
                cart = []
                showCheckout = false
                completed = true
                checkoutID = UUID()
                app.reservationSection = .mine
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

struct BookingSummaryView: View {
    let slots: [AvailableSlot]
    var busy = false
    var error: String?
    var onRemove: (AvailableSlot) -> Void
    var pay: (BookingQuote) -> Void
    var demoPay: () -> Void
    @State private var quote: BookingQuote?
    @State private var quoteError: String?
    @Environment(AppModel.self) private var app
    private var canPay: Bool { !slots.isEmpty && quote != nil && !busy }
    private var grouped: [(Date, [AvailableSlot])] { ReservationCalendar.groupedSlots(slots) }
    private var rooms: [String] { ReservationCalendar.uniqueRooms(slots) }
    private var minutes: Int { ReservationCalendar.totalMinutes(slots) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summaryHero
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
        .navigationBarBackButtonHidden(busy)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) { payFooter }
        .task { await loadQuote() }
        .onChange(of: slots.map(\.id)) { _, _ in Task { await loadQuote() } }
    }
    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("reservations.checkoutTitle")).font(.caption.weight(.semibold)).textCase(.uppercase)
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
                CheckoutDayCard(day: day, slots: items, busy: busy, onRemove: onRemove)
            }
        }
    }
    @ViewBuilder private var payFooter: some View {
        VStack(spacing: 12) {
            if let quote {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("reservations.payFooter")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("\(quote.slots.count)× \(quote.formatted(quote.pricePerSlot))").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(quote.formatted(quote.total)).font(.title.bold()).monospacedDigit()
                }
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
    private var payTitle: String {
        if let quote { return "\(L10n.tr("reservations.pay")) · \(quote.formatted(quote.total))" }
        return L10n.tr("reservations.pay")
    }
    private func loadQuote() async {
        guard !slots.isEmpty else { quote = nil; return }
        do {
            quote = try await app.service.quoteReservations(slotIDs: slots.map(\.id))
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
                                Text(ReservationCalendar.bookingDetail(room: slot.room, price: slot.price, currency: slot.currencyCode))
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
                    Text(ReservationCalendar.bookingDetail(room: reservation.room, price: reservation.price, currency: reservation.currencyCode))
                        .font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            if reservation.canCancel {
                Button(L10n.tr("reservations.cancel"), role: .destructive, action: onCancel)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
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
                        Text(ReservationCalendar.bookingDetail(room: reservation.room, price: reservation.price, currency: reservation.currencyCode))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if style == .upcoming, reservation.canCancel, let onCancel {
                    Button(L10n.tr("reservations.cancel"), role: .destructive, action: onCancel)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
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

struct MonthCalendar: View {
    @Binding var date: Date
    let slots: [AvailableSlot]
    let reservations: [Reservation]
    var selection: [AvailableSlot] = []
    var canGoBack = true
    var onBack: () -> Void
    var onForward: () -> Void
    private var calendar: Calendar { GymClock.calendar }
    private var days: [CalendarDay] { ReservationCalendar.monthGrid(containing: date, calendar: calendar) }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 6), count: 7) }
    var body: some View {
        BrandCard {
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    monthButton(systemName: "chevron.left", label: L10n.tr("reservations.previousMonth"), enabled: canGoBack, action: onBack)
                    Spacer(minLength: 8)
                    VStack(spacing: 4) {
                        Text(date.formatted(.dateTime.month(.wide).year()))
                            .font(.title3.weight(.bold))
                        if !calendar.isDateInToday(date) {
                            Button(L10n.tr("reservations.todayJump")) { date = ReservationCalendar.clampedDay(Date(), calendar: calendar) }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Brand.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Brand.lime, in: Capsule())
                        }
                    }
                    Spacer(minLength: 8)
                    monthButton(systemName: "chevron.right", label: L10n.tr("reservations.nextMonth"), enabled: true, action: onForward)
                }
                HStack(spacing: 0) {
                    ForEach(Array(ReservationCalendar.shortWeekdayLabels(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                        Text(symbol).font(.caption2.weight(.bold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(days, id: \.date) { day in
                        dayButton(day)
                    }
                }
                HStack(spacing: 14) {
                    legend(color: Brand.limeDeep, title: L10n.tr("reservations.legend.free"))
                    legend(color: Color("AccentColor"), title: L10n.tr("reservations.legend.mine"))
                    legend(color: Brand.ink, title: L10n.tr("reservations.legend.selected"))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("reservations.calendar")
    }
    private func monthButton(systemName: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(enabled ? 0.06 : 0.03), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
    private func dayButton(_ day: CalendarDay) -> some View {
        let selected = calendar.isDate(day.date, inSameDayAs: date)
        let past = ReservationCalendar.isPastDay(day.date)
        let today = calendar.isDateInToday(day.date)
        return Button {
            date = ReservationCalendar.clampedDay(day.date, calendar: calendar)
        } label: {
            VStack(spacing: 5) {
                Text(day.date, format: .dateTime.day())
                    .font(.subheadline.weight(today || selected ? .bold : .medium))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(foreground(selected: selected, past: past, inMonth: day.inMonth))
                    .background(selected ? Brand.lime : Color.clear, in: Circle())
                    .overlay {
                        if today && !selected {
                            Circle().strokeBorder(Brand.limeDeep, lineWidth: 1.5)
                        }
                    }
                Circle().fill(dotColor(for: day.date)).frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(past)
        .opacity(day.inMonth || selected ? 1 : 0.35)
        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHidden(!day.inMonth && past)
    }
    private func foreground(selected: Bool, past: Bool, inMonth: Bool) -> Color {
        if selected { return Brand.ink }
        if past || !inMonth { return Color.primary.opacity(0.35) }
        return Color.primary
    }
    private func dotColor(for day: Date) -> Color {
        if ReservationCalendar.hasReservation(reservations, on: day) { return Color("AccentColor") }
        if ReservationCalendar.hasSelection(selection, on: day) { return Brand.ink }
        if ReservationCalendar.hasAvailability(slots, on: day) { return Brand.limeDeep }
        return .clear
    }
    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
        }
    }
}

struct SlotRow: View {
    let slot: AvailableSlot
    var selected = false
    var overlapping = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            BrandCard {
                HStack(spacing: 14) {
                    Image(systemName: selected ? "checkmark.circle.fill" : overlapping ? "exclamationmark.circle" : "circle")
                        .font(.title2)
                        .foregroundStyle(overlapping ? Brand.danger : selected ? Color("AccentColor") : Color.primary.opacity(0.35))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ReservationCalendar.occupiedRange(slot.start, slot.end, bufferMinutes: slot.bufferMinutes))
                            .font(.headline)
                        Text(ReservationCalendar.bookingDetail(room: slot.room, price: slot.price, currency: slot.currencyCode))
                            .font(.caption).foregroundStyle(.secondary)
                        if overlapping {
                            Text(L10n.tr("reservations.overlap")).font(.caption).foregroundStyle(Brand.danger)
                        }
                    }
                    Spacer()
                }
            }
            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.card).strokeBorder(selected ? Color("AccentColor") : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(L10n.tr("reservations.reserve"))
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
                Text(ReservationCalendar.bookingDetail(room: reservation.room, price: reservation.price, currency: reservation.currencyCode))
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
