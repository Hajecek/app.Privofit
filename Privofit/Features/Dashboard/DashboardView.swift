import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @State private var info: GymInfo?
    @State private var visits: [Visit] = []
    @State private var eligibility: DoorEligibility?
    @State private var publicError: String?
    @State private var visitError: String?
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return L10n.tr(hour < 11 ? "greeting.morning" : hour < 18 ? "greeting.day" : "greeting.evening")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(greeting).font(.title3).foregroundStyle(.secondary)
                    Text(app.member?.firstName ?? L10n.tr("redesign.guestGreeting"))
                        .font(.largeTitle.weight(.bold)).tracking(-1)
                    Text(L10n.tr("redesign.dashboardSubtitle")).font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 12).padding(.bottom, 4)
                if app.isDemo || app.isGuest { StatusBadge(title: L10n.tr(app.isDemo ? "demo.badge" : "guest.badge"), symbol: "info.circle") }
                DoorHero(eligibility: eligibility)
                HStack {
                    SectionHeading(title: L10n.tr("redesign.upNext"))
                    Button(L10n.tr("redesign.allBookings")) { app.tab = .reservations }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }
                if app.loading { SkeletonCard() }
                if let error = app.error, !app.isGuest { FailureView(message: error) { Task { await load() } } }
                if app.isGuest {
                    BrandCard { VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.tr("guest.dashboard.title")).font(.title3.bold())
                        Text(L10n.tr("guest.dashboard.body")).foregroundStyle(.secondary)
                        Button(L10n.tr("auth.login")) { app.showGuestGate = true }.frame(minHeight: 44)
                    } }
                } else {
                    if let membership = app.membership {
                        BrandCard {
                            HStack(spacing: 16) {
                                Image(systemName: "creditcard.fill").font(.title2).foregroundStyle(Color("AccentColor"))
                                VStack(alignment: .leading, spacing: 4) { Text(membership.title).font(.headline); Text(L10n.tr("membership.status.\(membership.status.rawValue)")).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Button { app.tab = .membership } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel(L10n.tr("tab.membership"))
                            }
                        }
                    }
                    BrandCard { VStack(alignment: .leading, spacing: 14) {
                        Label(L10n.tr("reservations.next"), systemImage: "calendar").font(.headline)
                        if let next = app.reservations.filter({ $0.end > Date() }).sorted(by: { $0.start < $1.start }).first { ReservationSummary(reservation: next) }
                        else { Text(L10n.tr("reservations.empty")).foregroundStyle(.secondary) }
                        Button(L10n.tr("reservations.new")) { app.tab = .reservations }.frame(minHeight: 44)
                    } }
                    BrandCard { VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.tr("visits.title"), systemImage: "figure.walk").font(.headline)
                        if let visitError { FailureView(message: visitError) }
                        else if visits.isEmpty { Text(L10n.tr("visits.empty")).foregroundStyle(.secondary) }
                        ForEach(visits) { visit in HStack { Text(visit.room); Spacer(); Text(visit.date, style: .date).font(.subheadline) } }
                    } }
                }
                BrandCard { VStack(alignment: .leading, spacing: 14) {
                    Label(L10n.tr("gym.title"), systemImage: "building.2").font(.headline)
                    if let info {
                        Text(info.description).foregroundStyle(.secondary)
                        Label(info.openingHours, systemImage: "clock")
                        ForEach(info.announcements, id: \.self) { Text($0).font(.subheadline) }
                    } else if let publicError { FailureView(message: publicError) { Task { await loadPublic() } } }
                    else { ProgressView() }
                } }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.brandBackground().navigationTitle("").mainToolbar()
            .task { await load() }.refreshable { await load() }.accessibilityIdentifier("dashboard")
    }
    private func loadPublic() async {
        do { info = try await app.service.gymInfo(); publicError = nil } catch { publicError = FriendlyError.message(error) }
    }
    private func load() async {
        await loadPublic()
        guard !app.isGuest else { return }
        await app.loadDashboard()
        do { visits = try await app.service.visits(); visitError = nil } catch { visitError = FriendlyError.message(error); app.handle(error) }
        do { eligibility = try await app.service.eligibility() } catch { eligibility = nil; app.handle(error) }
    }
}
struct DoorHero: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    var eligibility: DoorEligibility? = nil
    private var statusKey: String {
        if app.isGuest { return "door.guest" }
        return eligibility.map { $0.allowed && $0.expiresAt > Date() ? "redesign.accessAvailable" : "door.checkAgain" } ?? "door.checkAgain"
    }
    var body: some View {
        Button { app.requestDoor() } label: {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L10n.tr("redesign.privateSpace"), systemImage: "location.fill").font(.caption.weight(.semibold))
                        Text(L10n.tr("door.open")).font(.largeTitle.weight(.bold)).tracking(-0.8).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    if !typeSize.isAccessibilitySize { AccessLock().frame(width: 60, height: 76).rotationEffect(.degrees(9)).padding(.top, 6) }
                }
                HStack(spacing: 16) {
                    Text(L10n.tr(statusKey)).font(.subheadline).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.headline).frame(width: 48, height: 48).background(Brand.ink.opacity(0.09), in: Circle())
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Brand.ink)
                .background(LinearGradient(colors: [Color(hex: 0xD4F65E), Brand.lime], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
        }.buttonStyle(.plain).accessibilityIdentifier("door.launch")
    }
}
