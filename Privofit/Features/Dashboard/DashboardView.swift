import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    @State private var revealed = false

    private var next: Reservation? { ReservationCalendar.next(app.reservations) }
    private var current: Reservation? { ReservationCalendar.current(app.reservations) }
    private var streak: TrainingStreak.Summary { TrainingStreak.summary(reservations: app.reservations, visits: app.visits) }
    private var text: Color { Brand.text(scheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header.modifier(RiseIn(shown: entered, index: 0, reduceMotion: reduceMotion))
                if app.isDemo || app.isGuest {
                    StatusBadge(title: L10n.tr(app.isDemo ? "demo.badge" : "guest.badge"), symbol: "info.circle")
                        .modifier(RiseIn(shown: entered, index: 1, reduceMotion: reduceMotion))
                }
                if let error = app.error, !app.isGuest {
                    FailureView(message: error) { Task { await reload() } }
                }
                if app.loading && app.reservations.isEmpty && app.visits.isEmpty && !app.isGuest {
                    SkeletonCard()
                }
                if let session = current ?? next {
                    sessionCard(session)
                        .modifier(RiseIn(shown: revealed, index: 1, reduceMotion: reduceMotion))
                }
                bookAction.modifier(RiseIn(shown: entered, index: 2, reduceMotion: reduceMotion))
                doorAction.modifier(RiseIn(shown: entered, index: 3, reduceMotion: reduceMotion))
                if app.isGuest {
                    guestCard.modifier(RiseIn(shown: revealed, index: 4, reduceMotion: reduceMotion))
                } else if !app.loading || !app.visits.isEmpty || !app.reservations.isEmpty {
                    streakCard.modifier(RiseIn(shown: revealed, index: 4, reduceMotion: reduceMotion))
                }
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .brandBackground()
        .navigationTitle(L10n.tr("tab.dashboard"))
        .navigationBarTitleDisplayMode(.inline)
        .mainToolbar()
        .task { await reload() }
        .refreshable { await reload() }
        .accessibilityIdentifier("dashboard")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(L10n.tr("home.hi")) \(app.member?.firstName ?? L10n.tr("redesign.guestGreeting"))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(text.opacity(0.62))
                    .lineLimit(1)
            }
            Text(headerLine)
                .font(.subheadline)
                .foregroundStyle(text.opacity(0.82))
                .lineLimit(2)
        }
        .padding(.top, 2)
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
                    Text(L10n.tr("home.bookHint")).font(.subheadline).foregroundStyle(Brand.ink.opacity(0.72))
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.headline.weight(.semibold))
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .foregroundStyle(Brand.ink)
            .background(Brand.lime, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(HomePressStyle())
        .accessibilityIdentifier("home.book")
    }

    private var doorAction: some View {
        Button(action: openDoor) {
            HStack(spacing: 14) {
                Image(systemName: "door.left.hand.open")
                    .font(.body.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .background(Brand.lime.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("tab.door")).font(.headline)
                    Text(L10n.tr("home.doorHint")).font(.subheadline).foregroundStyle(text.opacity(0.72))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(text.opacity(0.45))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(text)
            .background(Brand.surface(scheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(text.opacity(0.06)))
        }
        .buttonStyle(HomePressStyle())
    }

    private func sessionCard(_ session: Reservation) -> some View {
        let live = current != nil
        return Button {
            if app.isGuest { app.showGuestGate = true; return }
            app.reservationSection = .mine
            app.tab = .reservations
        } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(live ? L10n.tr("home.now") : L10n.tr("reservations.nextSession"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(live ? Brand.ink.opacity(0.62) : text.opacity(0.62))
                    Text(ReservationCalendar.occupiedRange(session.start, session.end, bufferMinutes: session.bufferMinutes))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("\(dayLabel(session.start)) · \(session.room)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(live ? Brand.ink.opacity(0.78) : text.opacity(0.78))
                }
                Spacer(minLength: 8)
                Image(systemName: live ? "bolt.fill" : "clock")
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background((live ? Brand.ink : Brand.lime).opacity(live ? 0.08 : 0.2), in: Circle())
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(live ? Brand.ink : text)
            .background(live ? Brand.lime : Brand.surface(scheme), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                if !live {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(text.opacity(0.06))
                }
            }
        }
        .buttonStyle(HomePressStyle())
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Label(L10n.tr("home.streak.title"), systemImage: "flame.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(scheme == .dark ? Brand.lime : Brand.ink)
                        .symbolEffect(.bounce, value: revealed)
                    Text(streak.length.formatted())
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(text)
                        .contentTransition(.numericText())
                        .padding(.top, 4)
                    Text(streakUnit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(text.opacity(0.72))
                }
                Spacer(minLength: 8)
                WeekBars(
                    week: streak.week,
                    labels: weekdayLabels,
                    revealed: revealed,
                    reduceMotion: reduceMotion,
                    scheme: scheme
                )
            }
            Text(streakHint)
                .font(.subheadline)
                .foregroundStyle(streak.atRisk ? Brand.alert : text.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(streakFill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(streakAccessibility)
    }

    private var guestCard: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("guest.dashboard.title")).font(.title3.bold()).foregroundStyle(text)
                Text(L10n.tr("guest.dashboard.body")).foregroundStyle(text.opacity(0.82))
                Button(L10n.tr("auth.login")) { app.showGuestGate = true }
                    .font(.headline)
                    .frame(minHeight: 44)
            }
        }
    }

    private var weekdayLabels: [String] { ReservationCalendar.shortWeekdayLabels() }

    private var streakFill: Color {
        scheme == .dark ? Color(hex: 0x1C2A22) : Color(hex: 0xD6E4C8)
    }

    private var streakUnit: String {
        switch streak.length {
        case 1: return L10n.tr("home.streak.unit.one")
        case 2, 3, 4: return L10n.tr("home.streak.unit.few")
        default: return L10n.tr("home.streak.unit.other")
        }
    }

    private var streakHint: String {
        if streak.week.contains(where: \.trained) { return L10n.tr("home.streak.today") }
        if streak.atRisk { return L10n.tr("home.streak.risk") }
        if streak.length > 0 { return L10n.tr("home.streak.keep") }
        return L10n.tr("home.streak.start")
    }

    private var streakAccessibility: String {
        "\(L10n.tr("home.streak.title")) \(streak.length.formatted()) \(streakUnit). \(streakHint)"
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

    private func openDoor() {
        if app.isGuest { app.showGuestGate = true; return }
        app.tab = .door
    }

    private func reload() async {
        await showChrome()
        guard !app.isGuest else {
            await showData()
            return
        }
        await app.loadDashboard()
        await showData()
    }

    private func showChrome() async {
        if reduceMotion { entered = true; return }
        if entered { return }
        try? await Task.sleep(for: .milliseconds(20))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { entered = true }
    }

    private func showData() async {
        if reduceMotion { revealed = true; return }
        revealed = false
        try? await Task.sleep(for: .milliseconds(30))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { revealed = true }
    }
}

private struct WeekBars: View {
    var week: [TrainingStreak.Mark]
    var labels: [String]
    var revealed: Bool
    var reduceMotion: Bool
    var scheme: ColorScheme

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(week.enumerated()), id: \.element.id) { index, mark in
                let label = index < labels.count ? labels[index] : ""
                let today = GymClock.calendar.isDateInToday(mark.date)
                VStack(spacing: 7) {
                    Capsule()
                        .fill(barColor(mark))
                        .frame(width: 16, height: barHeight(mark))
                        .overlay {
                            if today {
                                Capsule().strokeBorder(scheme == .dark ? Brand.lime : Brand.ink, lineWidth: 1.5)
                            }
                        }
                        .scaleEffect(y: revealed || reduceMotion ? 1 : 0.18, anchor: .bottom)
                        .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.7).delay(Double(index) * 0.045), value: revealed)
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Brand.text(scheme).opacity(today ? 1 : 0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 210)
        .accessibilityHidden(true)
    }

    private func barHeight(_ mark: TrainingStreak.Mark) -> CGFloat {
        if mark.trained { return 58 }
        if mark.planned { return 36 }
        return 16
    }

    private func barColor(_ mark: TrainingStreak.Mark) -> Color {
        let strong = scheme == .dark ? Brand.lime : Brand.ink
        if mark.trained { return strong }
        if mark.planned { return strong.opacity(0.38) }
        return Color.primary.opacity(0.14)
    }
}

private struct RiseIn: ViewModifier {
    var shown: Bool
    var index: Int
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .animation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.84).delay(0.05 * Double(index)), value: shown)
    }
}

private struct HomePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: ButtonStyle.Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
