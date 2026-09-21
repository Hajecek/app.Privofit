import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    private var next: Reservation? { ReservationCalendar.next(app.reservations) }
    private var current: Reservation? { ReservationCalendar.current(app.reservations) }
    private var streak: TrainingStreak.Summary { TrainingStreak.summary(reservations: app.reservations, visits: app.visits) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if app.isDemo || app.isGuest { StatusBadge(title: L10n.tr(app.isDemo ? "demo.badge" : "guest.badge"), symbol: "info.circle") }
                if let error = app.error, !app.isGuest { FailureView(message: error) { Task { await load() } } }
                if app.loading && app.reservations.isEmpty && app.visits.isEmpty && !app.isGuest { SkeletonCard() }
                bookAction
                if let session = current ?? next { sessionRow(session) }
                if app.isGuest {
                    guestCard
                } else if !app.loading || !app.visits.isEmpty || !app.reservations.isEmpty {
                    streakCard
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .brandBackground()
        .navigationTitle(L10n.tr("tab.dashboard"))
        .navigationBarTitleDisplayMode(.inline)
        .mainToolbar()
        .task { await load() }
        .refreshable { await load() }
        .accessibilityIdentifier("dashboard")
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

    private var bookAction: some View {
        Button(action: openBooking) {
            HStack(spacing: 16) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title2.weight(.semibold))
                    .frame(width: 52, height: 52)
                    .background(Brand.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("home.bookTitle")).font(.title3.weight(.bold))
                    Text(L10n.tr("home.bookHint")).font(.subheadline).opacity(0.7)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.headline.weight(.semibold))
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .foregroundStyle(Brand.ink)
            .background(Brand.lime, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.book")
    }

    private func sessionRow(_ session: Reservation) -> some View {
        Button {
            if app.isGuest { app.showGuestGate = true; return }
            app.reservationSection = .mine
            app.tab = .reservations
        } label: {
            HStack(spacing: 14) {
                Image(systemName: current != nil ? "bolt.fill" : "clock")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Brand.lime.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(current != nil ? L10n.tr("home.now") : L10n.tr("reservations.nextSession"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(ReservationCalendar.occupiedRange(session.start, session.end, bufferMinutes: session.bufferMinutes))
                        .font(.headline.monospacedDigit())
                    Text("\(dayLabel(session.start)) · \(session.room)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }
        }
        .buttonStyle(.plain)
        .padding(16)
        .background(Brand.surface(scheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label(L10n.tr("home.streak.title"), systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(scheme == .dark ? Brand.lime : Brand.ink)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(streak.length.formatted())
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(L10n.tr("home.streak.unit"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(zip(streak.week, weekdayLabels)), id: \.0.id) { mark, label in
                    dayMark(mark, label: label)
                }
            }
            Text(streakHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(scheme == .dark ? Brand.fog : Brand.ink)
        .background(streakFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(streakAccessibility)
    }

    private func dayMark(_ mark: TrainingStreak.Mark, label: String) -> some View {
        let today = GymClock.calendar.isDateInToday(mark.date)
        let fill = scheme == .dark ? Brand.lime : Brand.ink
        return VStack(spacing: 8) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(today ? .primary : .secondary)
            ZStack {
                Circle().strokeBorder(mark.planned || mark.trained ? fill.opacity(mark.trained ? 1 : 0.85) : Color.primary.opacity(0.16), lineWidth: today ? 2 : 1.5)
                if mark.trained { Circle().fill(fill).padding(3.5) }
            }
            .frame(width: 18, height: 18)
        }
        .frame(maxWidth: .infinity)
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

    private var weekdayLabels: [String] { ReservationCalendar.shortWeekdayLabels() }

    private var streakFill: Color {
        scheme == .dark ? Color(hex: 0x1C2A22) : Color(hex: 0xD6E4C8)
    }

    private var streakHint: String {
        if streak.todayTrained { return L10n.tr("home.streak.today") }
        if streak.length > 0 { return L10n.tr("home.streak.keep") }
        return L10n.tr("home.streak.start")
    }

    private var streakAccessibility: String {
        "\(L10n.tr("home.streak.title")) \(streak.length.formatted()) \(L10n.tr("home.streak.unit")). \(streakHint)"
    }

    private func dayLabel(_ date: Date) -> String {
        if GymClock.calendar.isDateInToday(date) { return L10n.tr("reservations.today") }
        if GymClock.calendar.isDateInTomorrow(date) { return L10n.tr("reservations.tomorrow") }
        return GymClock.format(date, Date.FormatStyle().weekday(.wide).day().month(.wide))
    }

    private func openBooking() {
        if app.isGuest { app.showGuestGate = true; return }
        app.reservationSection = .slots
        app.tab = .reservations
    }

    private func load() async {
        guard !app.isGuest else { return }
        await app.loadDashboard()
    }
}
