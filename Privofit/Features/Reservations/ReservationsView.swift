import SwiftUI

struct ReservationsView: View {
    @Environment(AppModel.self) private var app
    @State private var slots: [AvailableSlot] = []
    @State private var selected: AvailableSlot?
    @State private var cancellation: Reservation?
    @State private var date = Date()
    @State private var loading = false
    @State private var mutating = false
    @State private var error: String?
    @State private var completed = false
    @State private var requestIDs: [String: UUID] = [:]
    private var daySlots: [AvailableSlot] { slots.filter { Calendar.current.isDate($0.start, inSameDayAs: date) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if app.isGuest {
                    StatusBadge(title: L10n.tr("guest.reservations"), symbol: "eye")
                    Text(L10n.tr("guest.reservations.body")).foregroundStyle(.secondary)
                    BrandCard { VStack(alignment: .leading, spacing: 16) {
                        Label(L10n.tr("reservations.example"), systemImage: "calendar")
                        Text(L10n.tr("reservations.example.time")).font(.title2.bold())
                        PrimaryButton(title: L10n.tr("reservations.reserve")) { app.showGuestGate = true }
                    } }
                } else {
                    if let error { FailureView(message: error) { Task { await load() } } }
                    if completed { StatusBadge(title: L10n.tr("reservations.confirmed")) }
                    if loading { SkeletonCard() }
                    Text(L10n.tr("reservations.mine")).font(.title2.bold())
                    if app.reservations.isEmpty && !loading { ContentUnavailableView(L10n.tr("reservations.empty"), systemImage: "calendar") }
                    ForEach(app.reservations) { item in
                        BrandCard { VStack(alignment: .leading, spacing: 16) {
                            ReservationSummary(reservation: item)
                            if item.canCancel { Button(L10n.tr("reservations.cancel"), role: .destructive) { cancellation = item }.frame(minHeight: 44).disabled(mutating) }
                        } }
                    }
                    Text(L10n.tr("reservations.available")).font(.title2.bold())
                    BrandCard { DatePicker(L10n.tr("reservations.date"), selection: $date, in: Date()..., displayedComponents: .date).datePickerStyle(.graphical) }
                    if daySlots.isEmpty && !loading { Text(L10n.tr("reservations.noSlots")).foregroundStyle(.secondary) }
                    ForEach(daySlots) { slot in
                        Button { selected = slot } label: {
                            BrandCard { HStack { VStack(alignment: .leading) { Text(slot.room).font(.headline); Text(slot.start, style: .time) }; Spacer(); Image(systemName: "plus.circle.fill") } }
                        }.buttonStyle(.plain).disabled(mutating)
                    }
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.brandBackground().navigationTitle(L10n.tr("tab.reservations")).mainToolbar()
            .task { await load() }.refreshable { await load() }
            .sheet(item: $selected) { slot in
                VStack(alignment: .leading, spacing: 24) {
                    Text(L10n.tr("reservations.detail")).font(.title.bold())
                    Text(slot.room).font(.headline); Text(slot.start, format: .dateTime.day().month().hour().minute()); Text(slot.end, style: .time)
                    Text(L10n.tr("reservations.confirmBody")).foregroundStyle(.secondary)
                    PrimaryButton(title: L10n.tr("reservations.reserve"), busy: mutating) { Task { await reserve(slot) } }
                    if let error { FailureView(message: error) }
                }.padding(28).presentationDetents([.medium, .large]).interactiveDismissDisabled(mutating)
            }
            .confirmationDialog(L10n.tr("reservations.cancelConfirm"), isPresented: Binding(get: { cancellation != nil }, set: { if !$0 { cancellation = nil } }), titleVisibility: .visible, presenting: cancellation) { item in
                Button(L10n.tr("reservations.cancel"), role: .destructive) { Task { await cancel(item) } }
                Button(L10n.tr("common.notNow"), role: .cancel) { cancellation = nil }
            }
    }
    private func load() async {
        guard !app.isGuest, !loading else { return }; loading = true; defer { loading = false }
        do { let bookings = try await app.service.reservations(); let available = try await app.service.availableSlots(); guard app.phase == .authenticated else { return }; app.reservations = bookings; slots = available; error = nil }
        catch { self.error = FriendlyError.message(error); app.handle(error) }
    }
    private func reserve(_ slot: AvailableSlot) async {
        guard !mutating, app.phase == .authenticated else { return }; mutating = true; error = nil; defer { mutating = false }
        let requestID = requestIDs[slot.id] ?? UUID(); requestIDs[slot.id] = requestID
        do { _ = try await app.service.reserve(slotID: slot.id, requestID: requestID); requestIDs[slot.id] = nil; selected = nil; completed = true; await load() }
        catch { app.handle(error); await load(); self.error = L10n.tr("reservations.uncertain") }
    }
    private func cancel(_ item: Reservation) async {
        guard !mutating, app.phase == .authenticated else { return }; mutating = true; defer { mutating = false }
        do { try await app.service.cancelReservation(id: item.id, requestID: UUID()); completed = true; await load() }
        catch { self.error = FriendlyError.message(error); app.handle(error) }
    }
}
struct ReservationSummary: View {
    let reservation: Reservation
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(reservation.room).font(.headline)
            Text(reservation.start, format: .dateTime.weekday().day().month().hour().minute())
            Text(reservation.end, style: .time).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}
