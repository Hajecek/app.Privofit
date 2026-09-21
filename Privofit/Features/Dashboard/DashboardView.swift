import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    private var next: Reservation? { ReservationCalendar.next(app.reservations) }
    private var current: Reservation? { ReservationCalendar.current(app.reservations) }
    private var weekCount: Int {
        let days = Set(ReservationCalendar.week(containing: Date()))
        return ReservationCalendar.upcoming(app.reservations).filter { days.contains(GymClock.calendar.startOfDay(for: $0.start)) }.count
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if app.isDemo || app.isGuest { StatusBadge(title: L10n.tr(app.isDemo ? "demo.badge" : "guest.badge"), symbol: "info.circle") }
                if let error = app.error, !app.isGuest { FailureView(message: error) { Task { await load() } } }
                if app.loading { SkeletonCard() }
                sessionHero
                quickActions
                if app.isGuest {
                    guestCard
                    privateCard
                } else {
                    mosaic
                    if let item = app.inbox.first { inboxCard(item) }
                    privateCard
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.brandBackground().navigationTitle(L10n.tr("tab.dashboard")).navigationBarTitleDisplayMode(.inline).mainToolbar()
            .task { await load() }.refreshable { await load() }.accessibilityIdentifier("dashboard")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Brand.lime.opacity(0.2), in: Capsule())
            Text(L10n.tr("home.hi"))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(app.member?.firstName ?? L10n.tr("redesign.guestGreeting"))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .tracking(-1.4)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(headerLine)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.top, 6)
    }

    private var headerLine: String {
        if current != nil { return L10n.tr("home.line.now") }
        if let next, GymClock.calendar.isDateInToday(next.start) {
            return "\(L10n.tr("home.line.today")) \(GymClock.format(next.start, Date.FormatStyle(date: .omitted, time: .shortened)))"
        }
        let hour = Calendar.current.component(.hour, from: Date())
        return L10n.tr(hour < 11 ? "home.line.morning" : hour < 18 ? "home.line.day" : "home.line.evening")
    }

    private var sessionHero: some View {
        Button {
            if app.isGuest { app.showGuestGate = true; return }
            app.reservationSection = (current ?? next) == nil ? .slots : .mine
            app.tab = .reservations
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                Label(current != nil ? L10n.tr("home.now") : L10n.tr("reservations.nextSession"), systemImage: current != nil ? "bolt.fill" : "calendar")
                    .font(.caption.weight(.semibold))
                if let session = current ?? next {
                    Text(ReservationCalendar.occupiedRange(session.start, session.end, bufferMinutes: session.bufferMinutes))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(-0.6)
                        .monospacedDigit()
                    HStack {
                        Text("\(dayLabel(session.start)) · \(session.room)")
                        if current == nil {
                            Spacer(minLength: 8)
                            Text(session.start, style: .relative).opacity(0.8)
                        }
                    }.font(.subheadline.weight(.medium))
                } else {
                    Text(L10n.tr("home.sessionEmpty")).font(.title3.weight(.semibold)).multilineTextAlignment(.leading)
                    Text(L10n.tr("home.sessionHint")).font(.subheadline).opacity(0.78)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
            .foregroundStyle(current != nil ? Brand.ink : Brand.fog)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(current != nil
                          ? AnyShapeStyle(Brand.lime)
                          : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x24352C), Brand.ink], startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .overlay(alignment: .topTrailing) {
                Circle().stroke((current != nil ? Brand.ink : Brand.lime).opacity(0.12), lineWidth: 28)
                    .frame(width: 140, height: 140).offset(x: 36, y: -48)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.tr("redesign.allBookings"))
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button(action: app.requestDoor) {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "door.left.hand.open").font(.title2.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(L10n.tr("door.open")).font(.headline)
                    Text(L10n.tr("home.doorHint")).font(.caption).opacity(0.7)
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
                .foregroundStyle(Brand.ink)
                .background(Brand.lime, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
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
                    Spacer(minLength: 0)
                    Text(L10n.tr("home.book")).font(.headline)
                    Text(L10n.tr("home.bookHint")).font(.caption).opacity(0.55)
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    private var mosaic: some View {
        HStack(spacing: 12) {
            Button { app.tab = .membership } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "creditcard.fill").font(.title3)
                    Spacer(minLength: 4)
                    if let entries = app.membership?.remainingEntries {
                        Text(entries.formatted())
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(entries == 1 ? L10n.tr("home.entry.one") : L10n.tr("home.entry.many")).font(.subheadline.weight(.medium))
                    } else {
                        Text(L10n.tr("membership.status.\(app.membership?.status.rawValue ?? "inactive")"))
                            .font(.title3.weight(.bold))
                        Text(L10n.tr("tab.membership")).font(.subheadline)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
                .foregroundStyle(Brand.fog)
                .background {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x1B3A4A), Color(hex: 0x101714)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("tab.membership"))
            Button {
                app.reservationSection = .mine
                app.tab = .reservations
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "flame.fill").font(.title3)
                    Spacer(minLength: 4)
                    Text(weekCount.formatted())
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(L10n.tr("home.week")).font(.subheadline.weight(.medium))
                    Text(weekCount == 0 ? L10n.tr("home.week.empty") : (weekCount == 1 ? L10n.tr("home.week.one") : L10n.tr("home.week.many")))
                        .font(.caption).opacity(0.7)
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
                .foregroundStyle(Brand.ink)
                .background(Color(hex: 0xD6E4C8), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var privateCard: some View {
        Button(action: app.requestDoor) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("home.private.title")).font(.title2.weight(.bold))
                    Text(L10n.tr("home.private.body")).font(.subheadline).opacity(0.72)
                }
                Spacer(minLength: 8)
                Image(systemName: "sparkles").font(.title2)
            }
            .padding(22)
            .foregroundStyle(Brand.ink)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.lime, Color(hex: 0xA8D400)], startPoint: .leading, endPoint: .trailing))
            }
        }
        .buttonStyle(.plain)
    }

    private var guestCard: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("guest.dashboard.title")).font(.title3.bold())
                Text(L10n.tr("guest.dashboard.body")).foregroundStyle(.secondary)
                Button(L10n.tr("auth.login")) { app.showGuestGate = true }.frame(minHeight: 44)
            }
        }
    }

    private func inboxCard(_ item: InboxItem) -> some View {
        Button { app.showInbox = true } label: {
            BrandCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.tr("home.inbox"), systemImage: "bell.fill").font(.caption.weight(.semibold)).foregroundStyle(Color("AccentColor"))
                    Text(item.title).font(.headline)
                    Text(item.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr("notifications.title"))
    }

    private func dayLabel(_ date: Date) -> String {
        if GymClock.calendar.isDateInToday(date) { return L10n.tr("reservations.today") }
        if GymClock.calendar.isDateInTomorrow(date) { return L10n.tr("reservations.tomorrow") }
        return GymClock.format(date, Date.FormatStyle().weekday(.wide).day().month(.wide))
    }

    private func load() async {
        guard !app.isGuest else { return }
        await app.loadDashboard()
    }
}
