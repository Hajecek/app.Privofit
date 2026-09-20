import SwiftUI
import UIKit

struct ReservationsView: View {
    @Environment(AppModel.self) private var app
    @State private var slots: [AvailableSlot] = []
    @State private var cart: [AvailableSlot] = []
    @State private var showCheckout = false
    @State private var cancellation: Reservation?
    @State private var date = Date()
    @State private var loading = false
    @State private var mutating = false
    @State private var error: String?
    @State private var completed = false
    @State private var checkoutID = UUID()
    @State private var applePay = ApplePayCheckout()
    private var calendar: Calendar { .current }
    private var week: [Date] { ReservationCalendar.week(containing: date, calendar: calendar) }
    private var daySlots: [AvailableSlot] { ReservationCalendar.slots(on: date, from: slots, calendar: calendar) }
    private var dayBookings: [Reservation] { ReservationCalendar.reservations(on: date, from: app.reservations, calendar: calendar) }
    private var upcoming: [Reservation] { ReservationCalendar.upcoming(app.reservations) }
    private var sortedCart: [AvailableSlot] { cart.sorted { $0.start < $1.start } }
    private var canGoBack: Bool {
        let current = ReservationCalendar.week(containing: Date(), calendar: calendar).first ?? Date()
        return (week.first ?? date) > current
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if app.isGuest { guestContent }
                else { memberContent }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { if !app.isGuest && !cart.isEmpty { cartBar } }
        .brandBackground().navigationTitle(L10n.tr("tab.reservations")).mainToolbar()
            .task { await load() }.refreshable { await load() }
            .sheet(isPresented: $showCheckout) {
                BookingCheckoutSheet(slots: sortedCart, busy: mutating, error: error) { slot in
                    removeFromCart(slot)
                } pay: { quote in
                    Task { await payAndReserve(quote: quote, applePay: true) }
                } demoPay: {
                    Task { await payAndReserve(quote: nil, applePay: false) }
                }
            }
            .confirmationDialog(L10n.tr("reservations.cancelConfirm"), isPresented: Binding(get: { cancellation != nil }, set: { if !$0 { cancellation = nil } }), titleVisibility: .visible, presenting: cancellation) { item in
                Button(L10n.tr("reservations.cancel"), role: .destructive) { Task { await cancel(item) } }
                Button(L10n.tr("common.notNow"), role: .cancel) { cancellation = nil }
            }
    }
    private var guestContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            StatusBadge(title: L10n.tr("guest.reservations"), symbol: "eye")
            Text(L10n.tr("guest.reservations.body")).foregroundStyle(.secondary)
            WeekStrip(date: $date, week: week, slots: [], reservations: [], selection: [], canGoBack: false, onBack: {}, onForward: {})
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
            if let error, !showCheckout { FailureView(message: error) { Task { await load() } } }
            if completed { StatusBadge(title: L10n.tr("reservations.paid")) }
            if loading { SkeletonCard() }
            upcomingSection
            Text(L10n.tr("reservations.plan")).font(.title2.bold())
            Text(L10n.tr("reservations.selectHint")).font(.subheadline).foregroundStyle(.secondary)
            WeekStrip(
                date: $date,
                week: week,
                slots: slots,
                reservations: app.reservations,
                selection: cart,
                canGoBack: canGoBack,
                onBack: { date = ReservationCalendar.clampedDay(ReservationCalendar.shiftWeek(date, by: -1, calendar: calendar), calendar: calendar) },
                onForward: { date = ReservationCalendar.shiftWeek(date, by: 1, calendar: calendar) }
            )
            dayHeader
            dayReservations
            availability
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
    @ViewBuilder private var upcomingSection: some View {
        if !upcoming.isEmpty {
            Text(L10n.tr("reservations.upcoming")).font(.title2.bold())
            ForEach(upcoming) { item in
                BrandCard { VStack(alignment: .leading, spacing: 16) {
                    ReservationSummary(reservation: item)
                    if item.canCancel { Button(L10n.tr("reservations.cancel"), role: .destructive) { cancellation = item }.frame(minHeight: 44).disabled(mutating) }
                } }
            }
        } else if !loading {
            BrandCard { VStack(alignment: .leading, spacing: 10) {
                Label(L10n.tr("reservations.empty"), systemImage: "calendar").font(.headline)
                Text(L10n.tr("reservations.planHint")).font(.subheadline).foregroundStyle(.secondary)
            } }
        }
    }
    private var dayHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayTitle).font(.title3.bold())
            Text(slotCountLabel).font(.subheadline).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var dayReservations: some View {
        if !dayBookings.isEmpty {
            ForEach(dayBookings) { item in
                BrandCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color("AccentColor"))
                        ReservationSummary(reservation: item)
                    }
                }
            }
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
    private var dayTitle: String {
        if calendar.isDateInToday(date) { return L10n.tr("reservations.today") }
        if calendar.isDateInTomorrow(date) { return L10n.tr("reservations.tomorrow") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
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
        guard !app.isGuest, !loading else { return }; loading = true; defer { loading = false }
        do {
            let bookings = try await app.service.reservations()
            let available = try await app.service.availableSlots()
            guard app.phase == .authenticated else { return }
            app.reservations = bookings
            slots = available
            cart.removeAll { booked in bookings.contains(where: { $0.id == booked.id }) || !available.contains(where: { $0.id == booked.id }) }
            date = ReservationCalendar.clampedDay(date)
            error = nil
        } catch { self.error = FriendlyError.message(error); app.handle(error) }
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
                payment = try await applePay.pay(quote: quote) { token in
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
                await load()
            } else {
                self.error = L10n.tr("reservations.uncertain")
            }
        } catch let failure as AppFailure where failure == .cancelled {
            return
        } catch let failure as AppFailure where failure == .unavailable {
            self.error = L10n.tr("reservations.applePayFailed")
        } catch {
            app.handle(error)
            await load()
            self.error = FriendlyError.message(error)
        }
    }
    private func cancel(_ item: Reservation) async {
        guard !mutating, app.phase == .authenticated else { return }; mutating = true; defer { mutating = false }
        do { try await app.service.cancelReservation(id: item.id, requestID: UUID()); completed = true; await load() }
        catch { self.error = FriendlyError.message(error); app.handle(error) }
    }
}

struct BookingCheckoutSheet: View {
    let slots: [AvailableSlot]
    var busy = false
    var error: String?
    var onRemove: (AvailableSlot) -> Void
    var pay: (BookingQuote) -> Void
    var demoPay: () -> Void
    @State private var quote: BookingQuote?
    @State private var quoteError: String?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    private var canPay: Bool { !slots.isEmpty && quote != nil && !busy }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L10n.tr("reservations.checkoutTitle")).font(.title.bold())
                    Text(L10n.tr("reservations.confirmBody")).foregroundStyle(.secondary)
                    ForEach(slots) { slot in
                        BrandCard {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(slot.start, format: .dateTime.weekday(.wide).day().month())
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Text("\(slot.start.formatted(date: .omitted, time: .shortened)) – \(slot.end.formatted(date: .omitted, time: .shortened))")
                                        .font(.headline)
                                    Text("\(ReservationCalendar.durationMinutes(from: slot.start, to: slot.end)) \(L10n.tr("reservations.minutes")) · \(slot.room)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(L10n.tr("reservations.remove")) { onRemove(slot) }
                                    .font(.subheadline).disabled(busy)
                            }
                        }
                    }
                    if let quote {
                        BrandCard {
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledContent(L10n.tr("reservations.perSlot"), value: quote.formatted(quote.pricePerSlot))
                                LabeledContent(L10n.tr("reservations.total"), value: quote.formatted(quote.total))
                                    .font(.headline)
                            }
                        }
                    } else if quoteError == nil {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    }
                    if app.isDemo { Text(L10n.tr("reservations.payDemo")).font(.footnote).foregroundStyle(.secondary) }
                    if let message = error ?? quoteError { FailureView(message: message) }
                    if let quote, ApplePayCheckout.canMakePayments {
                        ApplePayButton(enabled: canPay) { pay(quote) }
                            .frame(height: 58)
                            .accessibilityLabel(payTitle)
                    } else if !app.isDemo {
                        Text(L10n.tr("reservations.applePayUnavailable")).font(.footnote).foregroundStyle(.secondary)
                    }
                    if app.isDemo {
                        Button(L10n.tr("reservations.payDemoAction")) { demoPay() }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity).frame(minHeight: 44)
                            .disabled(!canPay)
                    }
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                }.padding(24)
            }
            .brandBackground()
            .toolbar { Button(L10n.tr("common.close")) { dismiss() } }
            .task { await loadQuote() }
            .onChange(of: slots.map(\.id)) { _, _ in Task { await loadQuote() } }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(busy)
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

struct WeekStrip: View {
    @Binding var date: Date
    let week: [Date]
    let slots: [AvailableSlot]
    let reservations: [Reservation]
    var selection: [AvailableSlot] = []
    var canGoBack = true
    var onBack: () -> Void
    var onForward: () -> Void
    private var calendar: Calendar { .current }
    var body: some View {
        BrandCard {
            VStack(spacing: 16) {
                HStack {
                    Button(action: onBack) { Image(systemName: "chevron.left") }
                        .frame(width: 44, height: 44).disabled(!canGoBack)
                        .accessibilityLabel(L10n.tr("reservations.previousWeek"))
                    Spacer()
                    Text(weekTitle).font(.headline)
                    Spacer()
                    Button(action: onForward) { Image(systemName: "chevron.right") }
                        .frame(width: 44, height: 44)
                        .accessibilityLabel(L10n.tr("reservations.nextWeek"))
                }
                HStack(spacing: 6) {
                    ForEach(week, id: \.self) { day in
                        let selected = calendar.isDate(day, inSameDayAs: date)
                        let past = ReservationCalendar.isPastDay(day)
                        Button {
                            date = ReservationCalendar.clampedDay(day)
                        } label: {
                            VStack(spacing: 6) {
                                Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption.weight(.semibold))
                                Text(day, format: .dateTime.day()).font(.headline)
                                Circle().fill(dotColor(for: day)).frame(width: 6, height: 6)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .foregroundStyle(selected ? Brand.ink : Color.primary.opacity(past ? 0.35 : 1))
                            .background(selected ? Brand.lime : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(past)
                        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
        .accessibilityIdentifier("reservations.week")
    }
    private var weekTitle: String {
        guard let first = week.first, let last = week.last else { return L10n.tr("reservations.week") }
        return "\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
    }
    private func dotColor(for day: Date) -> Color {
        if ReservationCalendar.hasReservation(reservations, on: day) { return selected(day) ? Brand.ink : Color("AccentColor") }
        if ReservationCalendar.hasSelection(selection, on: day) { return selected(day) ? Brand.ink : Brand.limeDeep }
        if ReservationCalendar.hasAvailability(slots, on: day) { return selected(day) ? Brand.ink.opacity(0.45) : Color.primary.opacity(0.28) }
        return .clear
    }
    private func selected(_ day: Date) -> Bool { calendar.isDate(day, inSameDayAs: date) }
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
                        Text("\(slot.start.formatted(date: .omitted, time: .shortened)) – \(slot.end.formatted(date: .omitted, time: .shortened))")
                            .font(.headline)
                        Text("\(ReservationCalendar.durationMinutes(from: slot.start, to: slot.end)) \(L10n.tr("reservations.minutes")) · \(slot.room)")
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
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(relativeDay).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(reservation.room).font(.headline)
            Text("\(reservation.start.formatted(date: .omitted, time: .shortened)) – \(reservation.end.formatted(date: .omitted, time: .shortened))")
            Text("\(ReservationCalendar.durationMinutes(from: reservation.start, to: reservation.end)) \(L10n.tr("reservations.minutes"))")
                .font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    private var relativeDay: String {
        if Calendar.current.isDateInToday(reservation.start) { return L10n.tr("reservations.today") }
        if Calendar.current.isDateInTomorrow(reservation.start) { return L10n.tr("reservations.tomorrow") }
        return reservation.start.formatted(.dateTime.weekday(.wide).day().month())
    }
}
