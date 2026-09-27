import Foundation
import WidgetKit

enum WidgetPublisher {
    static func publish(phase: AppPhase, membership: Membership?, reservations: [Reservation], visits: [Visit], now: Date = Date()) {
        guard phase == .authenticated else {
            WidgetStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        WidgetStore.save(make(membership: membership, reservations: reservations, visits: visits, now: now))
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func make(membership: Membership?, reservations: [Reservation], visits: [Visit], now: Date = Date()) -> WidgetSnapshot {
        let streak = TrainingStreak.summary(reservations: reservations, visits: visits, now: now)
        let sessions = ReservationCalendar.upcoming(reservations, now: now).prefix(4).map { item in
            WidgetSession(
                id: item.id,
                start: item.start,
                end: item.end,
                room: item.room,
                bufferMinutes: item.bufferMinutes
            )
        }
        return WidgetSnapshot(
            updatedAt: now,
            signedIn: true,
            membershipTitle: membership?.title ?? "",
            membershipActive: membership?.isActive ?? false,
            membershipStatus: membership?.status.rawValue ?? "inactive",
            validUntil: membership?.validUntil,
            remainingEntries: membership?.remainingEntries,
            streakLength: streak.length,
            streakAtRisk: streak.atRisk,
            todayTrained: streak.todayTrained,
            week: streak.week.map { WidgetDay(date: $0.date, trained: $0.trained, planned: $0.planned) },
            sessions: Array(sessions)
        )
    }
}
