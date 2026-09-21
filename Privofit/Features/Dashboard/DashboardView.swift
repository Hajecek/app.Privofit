import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @State private var info: GymInfo?
    @State private var visits: [Visit] = []
    @State private var publicError: String?
    @State private var visitError: String?
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return L10n.tr(hour < 11 ? "greeting.morning" : hour < 18 ? "greeting.day" : "greeting.evening")
    }
    private var next: Reservation? { ReservationCalendar.next(app.reservations) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if app.isDemo || app.isGuest { StatusBadge(title: L10n.tr(app.isDemo ? "demo.badge" : "guest.badge"), symbol: "info.circle") }
                if let error = app.error, !app.isGuest { FailureView(message: error) { Task { await load() } } }
                if app.loading { SkeletonCard() }
                nextSessionCard
                quickActions
                if app.isGuest { guestCard } else { memberBlocks }
                gymCard
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.brandBackground().navigationTitle(L10n.tr("tab.dashboard")).navigationBarTitleDisplayMode(.inline).mainToolbar()
            .task { await load() }.refreshable { await load() }.accessibilityIdentifier("dashboard")
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(greeting).font(.subheadline).foregroundStyle(.secondary)
            Text(app.member?.firstName ?? L10n.tr("redesign.guestGreeting"))
                .font(.largeTitle.weight(.bold)).tracking(-1)
        }.padding(.top, 8)
    }
    private var nextSessionCard: some View {
        Button {
            if app.isGuest { app.showGuestGate = true; return }
            app.reservationSection = next == nil ? .slots : .mine
            app.tab = .reservations
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                Label(L10n.tr("reservations.nextSession"), systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                if let next {
                    Text(ReservationCalendar.timeRange(next.start, next.end))
                        .font(.largeTitle.weight(.bold)).tracking(-0.8).monospacedDigit()
                    Text("\(dayLabel(next.start)) · \(next.room)")
                        .font(.subheadline.weight(.medium))
                } else {
                    Text(L10n.tr("home.sessionEmpty")).font(.title3.weight(.semibold)).multilineTextAlignment(.leading)
                    Text(L10n.tr("reservations.empty")).font(.subheadline).opacity(0.8)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Brand.fog)
            .background {
                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(colors: [Color(hex: 0x2E3F32), Brand.ink], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.tr("redesign.allBookings"))
    }
    private var guestCard: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.tr("guest.dashboard.title")).font(.title3.bold())
                Text(L10n.tr("guest.dashboard.body")).foregroundStyle(.secondary)
                Button(L10n.tr("auth.login")) { app.showGuestGate = true }.frame(minHeight: 44)
            }
        }
    }
    private var quickActions: some View {
        HStack(spacing: 12) {
            Button(action: app.requestDoor) {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "door.left.hand.open").font(.title2.weight(.semibold))
                    Text(L10n.tr("door.open")).font(.headline)
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
                .foregroundStyle(Brand.ink)
                .background(Brand.lime, in: RoundedRectangle(cornerRadius: 24))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("door.launch")
            Button {
                if app.isGuest { app.showGuestGate = true; return }
                app.reservationSection = .slots
                app.tab = .reservations
            } label: {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "calendar.badge.plus").font(.title2.weight(.semibold))
                    Text(L10n.tr("home.book")).font(.headline)
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }
    @ViewBuilder private var memberBlocks: some View {
        if let membership = app.membership {
            Button { app.tab = .membership } label: {
                BrandCard {
                    HStack(spacing: 14) {
                        Image(systemName: "creditcard.fill").font(.title3).foregroundStyle(Color("AccentColor"))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(membership.title).font(.headline)
                            Text(membershipLine(membership)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("tab.membership"))
        }
        BrandCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.tr("visits.title"), systemImage: "figure.walk").font(.headline)
                if let visitError { FailureView(message: visitError) }
                else if visits.isEmpty { Text(L10n.tr("visits.empty")).foregroundStyle(.secondary) }
                ForEach(visits.prefix(3)) { visit in
                    HStack { Text(visit.room); Spacer(); Text(visit.date, style: .date).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
        }
    }
    private var gymCard: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.tr("gym.title"), systemImage: "building.2").font(.headline)
                if let info {
                    Text(info.description).font(.subheadline).foregroundStyle(.secondary)
                    Label(info.openingHours, systemImage: "clock").font(.subheadline)
                } else if let publicError { FailureView(message: publicError) { Task { await loadPublic() } } }
                else { ProgressView() }
            }
        }
    }
    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return L10n.tr("reservations.today") }
        if Calendar.current.isDateInTomorrow(date) { return L10n.tr("reservations.tomorrow") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
    private func membershipLine(_ membership: Membership) -> String {
        if let entries = membership.remainingEntries {
            return "\(L10n.tr("membership.status.\(membership.status.rawValue)")) · \(entries.formatted())"
        }
        return L10n.tr("membership.status.\(membership.status.rawValue)")
    }
    private func loadPublic() async {
        do { info = try await app.service.gymInfo(); publicError = nil } catch { publicError = FriendlyError.message(error) }
    }
    private func load() async {
        await loadPublic()
        guard !app.isGuest else { return }
        await app.loadDashboard()
        guard !Task.isCancelled else { return }
        do { visits = try await app.service.visits(); visitError = nil }
        catch is CancellationError { return }
        catch { visitError = FriendlyError.message(error); app.handle(error, surface: false) }
    }
}
