import WidgetKit
import SwiftUI
import AppIntents

struct PrivofitEntry: TimelineEntry, Sendable {
    var date: Date
    var snapshot: WidgetSnapshot
    var redacted = false

    var relevance: TimelineEntryRelevance? {
        guard snapshot.signedIn else { return TimelineEntryRelevance(score: 0) }
        if let current = snapshot.current(at: date) {
            return TimelineEntryRelevance(score: 90, duration: max(60, current.occupiedUntil.timeIntervalSince(date)))
        }
        if snapshot.streakAtRisk { return TimelineEntryRelevance(score: 60) }
        if let next = snapshot.next(at: date) {
            let lead = next.start.timeIntervalSince(date)
            if lead < 2 * 3600 { return TimelineEntryRelevance(score: 75) }
            if lead < 12 * 3600 { return TimelineEntryRelevance(score: 40) }
        }
        return TimelineEntryRelevance(score: 12)
    }
}

struct PrivofitProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrivofitEntry {
        PrivofitEntry(date: .now, snapshot: .placeholder, redacted: true)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (PrivofitEntry) -> Void) {
        if context.isPreview {
            completion(PrivofitEntry(date: .now, snapshot: WidgetStore.load() ?? .placeholder))
            return
        }
        completion(PrivofitEntry(date: .now, snapshot: WidgetStore.load() ?? .signedOut))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<PrivofitEntry>) -> Void) {
        let snapshot = WidgetStore.load() ?? .signedOut
        let now = Date()
        let dates = WidgetTimeline.dates(for: snapshot, now: now)
        let entries = dates.map { PrivofitEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(WidgetTimeline.refresh(after: dates, now: now))))
    }
}

enum WidgetBrand {
    static let lime = Color(red: 198 / 255, green: 242 / 255, blue: 26 / 255)
    static let limeDeep = Color(red: 143 / 255, green: 191 / 255, blue: 0)
    static let night = Color(red: 11 / 255, green: 18 / 255, blue: 16 / 255)
    static let fog = Color(red: 232 / 255, green: 240 / 255, blue: 228 / 255)
}

extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }
}

private struct WidgetBackdrop: View {
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if family.isAccessory {
            AccessoryWidgetBackground()
        } else if mode == .fullColor {
            scheme == .dark ? WidgetBrand.night : WidgetBrand.fog
        } else {
            Color.clear
        }
    }
}

private struct WidgetChrome: ViewModifier {
    var link: URL
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { WidgetBackdrop() }
            .widgetURL(link)
    }
}

private struct Emphasis: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder func body(content: Content) -> some View {
        if family.isAccessory || mode != .fullColor {
            content.foregroundStyle(.primary).widgetAccentable()
        } else {
            content.foregroundStyle(scheme == .dark ? WidgetBrand.lime : WidgetBrand.limeDeep).widgetAccentable()
        }
    }
}

private extension View {
    func widgetChrome(_ place: WidgetPlace) -> some View {
        modifier(WidgetChrome(link: WidgetLink.url(place)))
    }

    func emphasis() -> some View { modifier(Emphasis()) }
}

private enum WidgetCopy {
    static func day(_ date: Date, now: Date) -> String {
        let calendar = WidgetClock.calendar
        if calendar.isDate(date, inSameDayAs: now) { return L10n.tr("reservations.today") }
        let start = calendar.startOfDay(for: now)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: start), calendar.isDate(date, inSameDayAs: tomorrow) {
            return L10n.tr("reservations.tomorrow")
        }
        return WidgetClock.format(date, date: .abbreviated, time: .omitted)
    }

    static func range(_ session: WidgetSession) -> String {
        "\(WidgetClock.format(session.start)) – \(WidgetClock.format(session.occupiedUntil))"
    }

    static func unit(_ length: Int) -> String {
        switch length {
        case 1: return L10n.tr("home.streak.unit.one")
        case 2, 3, 4: return L10n.tr("home.streak.unit.few")
        default: return L10n.tr("home.streak.unit.other")
        }
    }

    static func hint(_ snapshot: WidgetSnapshot) -> String {
        if snapshot.todayTrained || snapshot.week.contains(where: \.trained) { return L10n.tr("home.streak.today") }
        if snapshot.streakAtRisk { return L10n.tr("home.streak.risk") }
        if snapshot.streakLength > 0 { return L10n.tr("home.streak.keep") }
        return L10n.tr("home.streak.start")
    }

    static func status(_ snapshot: WidgetSnapshot) -> String {
        switch snapshot.membershipStatus {
        case "active": return L10n.tr("membership.status.active")
        case "ending": return L10n.tr("membership.status.ending")
        case "paused": return L10n.tr("membership.status.paused")
        default: return L10n.tr("membership.status.inactive")
        }
    }

    static func sessionLine(_ session: WidgetSession, now: Date, live: Bool) -> String {
        let when = live ? L10n.tr("home.now") : day(session.start, now: now)
        return "\(when) \(WidgetClock.format(session.start)) \(session.room)"
    }
}

private struct SignedOutView: View {
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(compact ? .headline : .title3)
                .emphasis()
            Text(L10n.tr("widget.signedOut"))
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WeekDots: View {
    var days: [WidgetDay]
    var now: Date
    var showsLabels: Bool
    private var labels: [String] { WidgetClock.weekdayLabels() }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                let today = WidgetClock.calendar.isDate(day.date, inSameDayAs: now)
                VStack(spacing: 5) {
                    if showsLabels {
                        Text(index < labels.count ? labels[index] : "")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(today ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    ZStack {
                        Circle()
                            .strokeBorder(day.trained || day.planned ? Color.primary.opacity(day.trained ? 1 : 0.75) : Color.primary.opacity(0.18), lineWidth: today ? 2 : 1.5)
                        if day.trained {
                            Circle().fill(Color.primary).padding(3).widgetAccentable()
                        }
                    }
                    .frame(width: 16, height: 16)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

struct SessionWidget: Widget {
    let kind = "cz.privofit.widget.session"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrivofitProvider()) { entry in
            SessionWidgetView(entry: entry)
                .redacted(reason: entry.redacted ? .placeholder : [])
        }
        .configurationDisplayName(LocalizedStringResource("widget.session.name"))
        .description(LocalizedStringResource("widget.session.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct SessionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: PrivofitEntry

    var body: some View {
        Group {
            if family == .accessoryInline {
                if let session = entry.snapshot.signedIn ? entry.snapshot.focus(at: entry.date) : nil {
                    Text(WidgetCopy.sessionLine(session, now: entry.date, live: session.contains(entry.date)))
                } else if entry.snapshot.signedIn {
                    Text(L10n.tr("widget.emptyInline"))
                } else {
                    Text(L10n.tr("widget.signedOut"))
                }
            } else if !entry.snapshot.signedIn {
                SignedOutView(compact: family == .systemSmall || family.isAccessory)
            } else {
                switch family {
                case .systemMedium: SessionMedium(entry: entry)
                case .systemLarge: SessionLarge(entry: entry)
                case .accessoryCircular: SessionCircular(entry: entry)
                case .accessoryRectangular: SessionRectangular(entry: entry)
                default: SessionSmall(entry: entry)
                }
            }
        }
        .widgetChrome(entry.snapshot.signedIn ? .session : .dashboard)
    }
}

private struct SessionSmall: View {
    var entry: PrivofitEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            brand
            Spacer(minLength: 0)
            if let session = entry.snapshot.focus(at: entry.date) {
                Text(entry.snapshot.current(at: entry.date) == nil ? WidgetCopy.day(session.start, now: entry.date) : L10n.tr("home.now"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(WidgetClock.format(session.start))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .emphasis()
                Text(session.room)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                empty
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var brand: some View {
        Text("PRIVOFIT")
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .emphasis()
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.tr("home.bookTitle"))
                .font(.headline)
                .minimumScaleFactor(0.8)
            Text(L10n.tr("home.sessionEmpty"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}

private struct SessionMedium: View {
    var entry: PrivofitEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("PRIVOFIT").font(.caption2.weight(.bold)).tracking(0.6).emphasis()
                Spacer(minLength: 8)
                Text("\(entry.snapshot.streakLength.formatted()) \(WidgetCopy.unit(entry.snapshot.streakLength))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let session = entry.snapshot.focus(at: entry.date) {
                HStack(alignment: .center, spacing: 14) {
                    Text(WidgetClock.format(session.start))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .emphasis()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.snapshot.current(at: entry.date) == nil ? WidgetCopy.day(session.start, now: entry.date) : L10n.tr("home.now"))
                            .font(.subheadline.weight(.semibold))
                        Text(session.room)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(WidgetCopy.range(session))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text(L10n.tr("home.bookTitle")).font(.headline)
                Text(L10n.tr("home.sessionEmpty")).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SessionLarge: View {
    var entry: PrivofitEntry
    private var rows: [WidgetSession] { entry.snapshot.upcoming(at: entry.date, limit: 3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("widget.session.name"))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text(L10n.tr("home.bookTitle")).font(.title3.weight(.bold))
                Text(L10n.tr("home.sessionEmpty")).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, session in
                    sessionRow(session, primary: index == 0)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.tr("home.streak.title")).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(entry.snapshot.streakLength.formatted())
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .emphasis()
                }
                WeekDots(days: entry.snapshot.week, now: entry.date, showsLabels: false)
            }
        }
    }

    private func sessionRow(_ session: WidgetSession, primary: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(WidgetClock.format(session.start))
                .font(primary ? .title2.weight(.bold) : .headline)
                .monospacedDigit()
                .frame(width: primary ? 78 : 64, alignment: .leading)
                .emphasis()
            VStack(alignment: .leading, spacing: 2) {
                Text(session.contains(entry.date) ? L10n.tr("home.now") : WidgetCopy.day(session.start, now: entry.date))
                    .font(.subheadline.weight(.semibold))
                Text(session.room)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SessionCircular: View {
    var entry: PrivofitEntry
    var body: some View {
        if let session = entry.snapshot.focus(at: entry.date) {
            Text(WidgetClock.format(session.start))
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .widgetAccentable()
        } else {
            Image(systemName: "calendar.badge.plus").font(.title3).widgetAccentable()
        }
    }
}

private struct SessionRectangular: View {
    var entry: PrivofitEntry
    var body: some View {
        if let session = entry.snapshot.focus(at: entry.date) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.contains(entry.date) ? L10n.tr("home.now") : WidgetCopy.day(session.start, now: entry.date))
                    .font(.headline)
                    .widgetAccentable()
                Text("\(WidgetClock.format(session.start)) · \(session.room)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text(L10n.tr("home.bookTitle")).font(.headline).widgetAccentable()
        }
    }
}

struct StreakWidget: Widget {
    let kind = "cz.privofit.widget.streak"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrivofitProvider()) { entry in
            StreakWidgetView(entry: entry)
                .redacted(reason: entry.redacted ? .placeholder : [])
        }
        .configurationDisplayName(LocalizedStringResource("widget.streak.name"))
        .description(LocalizedStringResource("widget.streak.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: PrivofitEntry

    var body: some View {
        Group {
            if family == .accessoryInline {
                Text(entry.snapshot.signedIn
                     ? "\(L10n.tr("home.streak.title")) \(entry.snapshot.streakLength.formatted()) \(WidgetCopy.unit(entry.snapshot.streakLength))"
                     : L10n.tr("widget.signedOut"))
            } else if !entry.snapshot.signedIn {
                SignedOutView(compact: family == .systemSmall || family.isAccessory)
            } else {
                switch family {
                case .systemMedium: StreakMedium(entry: entry)
                case .accessoryCircular: StreakCircular(entry: entry)
                case .accessoryRectangular: StreakRectangular(entry: entry)
                default: StreakSmall(entry: entry)
                }
            }
        }
        .widgetChrome(.streak)
    }
}

private struct StreakSmall: View {
    var entry: PrivofitEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("widget.streak.name"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.snapshot.streakLength.formatted())
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .emphasis()
                Text(WidgetCopy.unit(entry.snapshot.streakLength))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            WeekDots(days: entry.snapshot.week, now: entry.date, showsLabels: false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.tr("home.streak.title")) \(entry.snapshot.streakLength.formatted()) \(WidgetCopy.unit(entry.snapshot.streakLength)). \(WidgetCopy.hint(entry.snapshot))")
    }
}

private struct StreakMedium: View {
    var entry: PrivofitEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.tr("widget.streak.name")).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(entry.snapshot.streakLength.formatted())
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .emphasis()
                Text(WidgetCopy.unit(entry.snapshot.streakLength))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            WeekDots(days: entry.snapshot.week, now: entry.date, showsLabels: true)
            Text(WidgetCopy.hint(entry.snapshot))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StreakCircular: View {
    var entry: PrivofitEntry
    var body: some View {
        VStack(spacing: 0) {
            Text(entry.snapshot.streakLength.formatted())
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .widgetAccentable()
            Image(systemName: "flame.fill").font(.caption2).widgetAccentable()
        }
    }
}

private struct StreakRectangular: View {
    var entry: PrivofitEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(L10n.tr("home.streak.title")) \(entry.snapshot.streakLength.formatted()) \(WidgetCopy.unit(entry.snapshot.streakLength))")
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
            WeekDots(days: entry.snapshot.week, now: entry.date, showsLabels: false)
        }
    }
}

struct MembershipWidget: Widget {
    let kind = "cz.privofit.widget.membership"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrivofitProvider()) { entry in
            MembershipWidgetView(entry: entry)
                .redacted(reason: entry.redacted ? .placeholder : [])
        }
        .configurationDisplayName(LocalizedStringResource("widget.membership.name"))
        .description(LocalizedStringResource("widget.membership.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct MembershipWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: PrivofitEntry

    var body: some View {
        Group {
            if family == .accessoryInline {
                if entry.snapshot.signedIn, let entries = entry.snapshot.remainingEntries {
                    Text("\(L10n.tr("widget.membership.name")) \(entries.formatted())")
                } else if entry.snapshot.signedIn {
                    Text("\(L10n.tr("widget.membership.name")) \(WidgetCopy.status(entry.snapshot))")
                } else {
                    Text(L10n.tr("widget.signedOut"))
                }
            } else if !entry.snapshot.signedIn {
                SignedOutView(compact: family == .systemSmall || family.isAccessory)
            } else {
                switch family {
                case .systemMedium: MembershipMedium(entry: entry)
                case .accessoryCircular: MembershipCircular(entry: entry)
                case .accessoryRectangular: MembershipRectangular(entry: entry)
                default: MembershipSmall(entry: entry)
                }
            }
        }
        .widgetChrome(.membership)
    }
}

private struct MembershipSmall: View {
    var entry: PrivofitEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.tr("widget.membership.name"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.snapshot.membershipTitle.isEmpty ? "PRIVOFIT" : entry.snapshot.membershipTitle)
                .font(.headline.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(WidgetCopy.status(entry.snapshot))
                .font(.caption.weight(.semibold))
                .emphasis()
            Spacer(minLength: 0)
            if let entries = entry.snapshot.remainingEntries {
                Text(entries.formatted())
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .emphasis()
                Text(L10n.tr("membership.entries"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let until = entry.snapshot.validUntil {
                Text(L10n.tr("membership.until"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(WidgetClock.format(until, date: .abbreviated, time: .omitted))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MembershipMedium: View {
    var entry: PrivofitEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("widget.membership.name")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(WidgetCopy.status(entry.snapshot)).font(.caption.weight(.bold)).emphasis()
            }
            Text(entry.snapshot.membershipTitle.isEmpty ? "PRIVOFIT" : entry.snapshot.membershipTitle)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if let entries = entry.snapshot.remainingEntries {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entries.formatted()).font(.title.weight(.bold)).monospacedDigit().emphasis()
                        Text(L10n.tr("membership.entries")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let until = entry.snapshot.validUntil {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WidgetClock.format(until, date: .abbreviated, time: .omitted))
                            .font(.headline.monospacedDigit())
                        Text(L10n.tr("membership.until")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MembershipCircular: View {
    var entry: PrivofitEntry
    var body: some View {
        if let entries = entry.snapshot.remainingEntries {
            Text(entries.formatted())
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .widgetAccentable()
        } else {
            Image(systemName: entry.snapshot.membershipActive ? "checkmark" : "creditcard")
                .font(.title3.weight(.bold))
                .widgetAccentable()
        }
    }
}

private struct MembershipRectangular: View {
    var entry: PrivofitEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.snapshot.membershipTitle.isEmpty ? L10n.tr("widget.membership.name") : entry.snapshot.membershipTitle)
                .font(.headline)
                .lineLimit(1)
                .widgetAccentable()
            Text(membershipDetail(entry.snapshot))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func membershipDetail(_ snapshot: WidgetSnapshot) -> String {
        if let entries = snapshot.remainingEntries {
            return "\(WidgetCopy.status(snapshot)) · \(entries.formatted())"
        }
        return WidgetCopy.status(snapshot)
    }
}

struct BookControl: ControlWidget {
    static let kind = "cz.privofit.control.book"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenPrivofitIntent(place: .reservations)) {
                Label("widget.control.book.name", systemImage: "calendar.badge.plus")
            }
        }
        .displayName(LocalizedStringResource("widget.control.book.name"))
        .description(LocalizedStringResource("widget.control.book.description"))
    }
}

#Preview(as: .systemSmall) {
    SessionWidget()
} timeline: {
    PrivofitEntry(date: .now, snapshot: .placeholder)
    PrivofitEntry(date: .now, snapshot: .signedOut)
}

#Preview(as: .systemMedium) {
    StreakWidget()
} timeline: {
    PrivofitEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemSmall) {
    MembershipWidget()
} timeline: {
    PrivofitEntry(date: .now, snapshot: .placeholder)
}
