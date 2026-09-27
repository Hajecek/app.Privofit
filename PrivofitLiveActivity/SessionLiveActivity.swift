import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

enum SessionActivityPalette {
    static let lime = Color(red: 198.0 / 255, green: 242.0 / 255, blue: 26.0 / 255)
    static let ink = Color(red: 16.0 / 255, green: 23.0 / 255, blue: 20.0 / 255)
    static let night = Color(red: 11.0 / 255, green: 18.0 / 255, blue: 16.0 / 255)
}

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionLockScreen(state: context.state, reservationID: context.attributes.reservationID)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SessionMark(size: 22)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SessionIslandTimer(state: state, probe: "0:00:00")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(SessionActivityPalette.lime)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(SessionCopy.roomLine(state))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(SessionActivityTiming.range(from: state.start, to: state.occupiedUntil))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        SessionProgress(state: state, tint: SessionActivityPalette.lime)
                    }
                }
            } compactLeading: {
                SessionMark(size: 16)
            } compactTrailing: {
                // Text(timerInterval:) bez omezení šířky roztáhne Island přes celý display.
                SessionIslandTimer(state: state, probe: "0:00:00")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(SessionActivityPalette.lime)
            } minimal: {
                SessionMark(size: 14)
            }
            .widgetURL(SessionActivityLink.url(for: context.attributes.reservationID))
            .keylineTint(SessionActivityPalette.lime)
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct SessionLockScreen: View {
    @Environment(\.activityFamily) private var family
    var state: SessionActivityAttributes.ContentState
    var reservationID: String

    var body: some View {
        Group {
            if family == .small {
                watch
            } else {
                card
            }
        }
        .widgetURL(SessionActivityLink.url(for: reservationID))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SessionMark(size: 28, showsPlate: false)
                Text("Privofit")
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 8)
                Text(SessionActivityTiming.range(from: state.start, to: state.occupiedUntil))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Text(SessionCopy.roomLine(state))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            SessionProgress(state: state, tint: SessionActivityPalette.ink)
            HStack(alignment: .top, spacing: 12) {
                moment(String(localized: "liveactivity.starts"), date: state.start, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                endMoment
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .foregroundStyle(SessionActivityPalette.ink)
        .activityBackgroundTint(SessionActivityPalette.lime)
        .accessibilityElement(children: .combine)
    }

    private var watch: some View {
        HStack(spacing: 8) {
            SessionMark(size: 18, showsPlate: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.room)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Text(SessionActivityTiming.range(from: state.start, to: state.occupiedUntil))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(SessionActivityPalette.ink.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            SessionCountdown(state: state)
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 8)
        .foregroundStyle(SessionActivityPalette.ink)
        .accessibilityElement(children: .combine)
    }

    private var endMoment: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(String(localized: "liveactivity.ends"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SessionActivityPalette.ink.opacity(0.62))
                .frame(maxWidth: .infinity, alignment: .trailing)
            if Date() >= state.occupiedUntil {
                Text(String(localized: "liveactivity.finished"))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                // timerInterval Text se sám nezarovná; Spacer ho drží vpravo jako Začátek vlevo
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(timerInterval: state.windowStart...state.occupiedUntil, countsDown: true, showsHours: true)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func moment(_ title: String, date: Date, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SessionActivityPalette.ink.opacity(0.62))
            Text(date, style: .relative)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct SessionCountdown: View {
    var state: SessionActivityAttributes.ContentState

    var body: some View {
        if Date() >= state.occupiedUntil {
            Text(String(localized: "liveactivity.finished"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Text(timerInterval: state.windowStart...state.occupiedUntil, countsDown: true, showsHours: true)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Live odpočet pro Dynamic Island. Bez skrytého „probe“ textu systém roztáhne Island přes celou šířku.
private struct SessionIslandTimer: View {
    var state: SessionActivityAttributes.ContentState
    var probe: String

    var body: some View {
        Text(probe)
            .monospacedDigit()
            .hidden()
            .overlay(alignment: .trailing) {
                if Date() >= state.occupiedUntil {
                    Text("0:00")
                        .monospacedDigit()
                } else {
                    Text(timerInterval: state.windowStart...state.occupiedUntil, countsDown: true, showsHours: true)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .minimumScaleFactor(0.75)
                }
            }
            .lineLimit(1)
    }
}

private struct SessionProgress: View {
    var state: SessionActivityAttributes.ContentState
    var tint: Color

    var body: some View {
        if let interval = state.progressInterval() {
            ProgressView(timerInterval: interval, countsDown: false)
                .tint(tint)
                .labelsHidden()
        }
    }
}

/// Ikona aplikace. Na limetkové kartě bez podkladu (splývá), v Islandu s limetkovým plate.
private struct SessionMark: View {
    var size: CGFloat
    var showsPlate = true

    var body: some View {
        ZStack {
            if showsPlate {
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .fill(SessionActivityPalette.lime)
            }
            icon
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = UIImage(named: "AppMark") ?? UIImage(named: "BrandIcon") {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFit()
        } else {
            SessionMarkFallback()
        }
    }
}

private struct SessionMarkFallback: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var mark = Path(roundedRect: CGRect(x: w * 0.17, y: h * 0.15, width: w * 0.2, height: h * 0.7), cornerRadius: w * 0.06)
            mark.addPath(Path(roundedRect: CGRect(x: w * 0.17, y: h * 0.15, width: w * 0.68, height: h * 0.46), cornerRadius: h * 0.2))
            var hole = Path(ellipseIn: CGRect(x: w * 0.42, y: h * 0.27, width: w * 0.28, height: h * 0.22))
            mark = mark.subtracting(hole)
            context.fill(mark, with: .color(SessionActivityPalette.ink))
        }
    }
}

private enum SessionCopy {
    static func roomLine(_ state: SessionActivityAttributes.ContentState) -> String {
        guard state.guestCount > 1 else { return state.room }
        let word = state.guestCount < 5
            ? String(localized: "reservations.personsFew")
            : String(localized: "reservations.personsMany")
        return "\(state.room) · \(state.guestCount) \(word)"
    }
}

#if DEBUG
private enum SessionActivityPreview {
    static let attributes = SessionActivityAttributes(reservationID: "preview")
    static var upcoming: SessionActivityAttributes.ContentState {
        let start = Date.now.addingTimeInterval(20 * 60)
        return .init(room: "PRIVOFIT / 01", start: start, end: start.addingTimeInterval(3600), bufferMinutes: 15, guestCount: 1)
    }
}

#Preview("Zámek", as: .content, using: SessionActivityPreview.attributes) {
    SessionLiveActivity()
} contentStates: {
    SessionActivityPreview.upcoming
}

#Preview("Island", as: .dynamicIsland(.expanded), using: SessionActivityPreview.attributes) {
    SessionLiveActivity()
} contentStates: {
    SessionActivityPreview.upcoming
}
#endif
