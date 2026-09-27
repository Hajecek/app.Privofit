import ActivityKit
import Foundation
import os

enum SessionActivityProcess {
    static var tracksActivities: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return false }
        if environment["XCTestConfigurationFilePath"] != nil { return false }
        if environment["XCTestBundlePath"] != nil { return false }
        if environment["XCTestSessionIdentifier"] != nil { return false }
        return true
    }
}

enum SessionActivityPlanner {
    struct Existing: Equatable, Sendable {
        enum Phase: Equatable, Sendable { case pending, live, finished }
        var id: String
        var phase: Phase
        var content: SessionActivityAttributes.ContentState
    }

    enum Command: Equatable, Sendable {
        case discard(String)
        case present(SessionActivityAttributes.ContentState, reservationID: String, startsAt: Date?)
        case refresh(String, SessionActivityAttributes.ContentState)
    }

    static func commands(reservations: [Reservation], existing: [Existing], now: Date) -> [Command] {
        let wanted = selections(reservations, now: now)
        let wantedIDs = Set(wanted.map(\.id))
        var commands: [Command] = []
        for item in existing where !wantedIDs.contains(item.id) {
            commands.append(.discard(item.id))
        }
        for reservation in wanted {
            let content = SessionActivityAttributes.ContentState(reservation)
            let window = content.windowStart
            if let item = existing.first(where: { $0.id == reservation.id }) {
                commands.append(contentsOf: reconcile(item, content: content, window: window, now: now))
            } else {
                let startsAt: Date? = window > now ? window : nil
                commands.append(.present(content, reservationID: reservation.id, startsAt: startsAt))
            }
        }
        return commands
    }

    private static func selections(_ reservations: [Reservation], now: Date) -> [Reservation] {
        let open = reservations.filter { $0.occupiedUntil > now }.sorted { $0.start < $1.start }
        let current = open.filter { $0.start <= now }.max { $0.start < $1.start }
        var upcoming = open.filter { $0.start > now }
        let horizonEnd = now.addingTimeInterval(SessionActivityTiming.horizon)
        if let first = upcoming.first, first.start > horizonEnd {
            upcoming = [first]
        } else {
            upcoming = upcoming.filter { $0.start <= horizonEnd }
        }
        upcoming = Array(upcoming.prefix(SessionActivityTiming.upcomingLimit))
        var wanted: [Reservation] = []
        if let current { wanted.append(current) }
        for item in upcoming where item.id != current?.id {
            wanted.append(item)
        }
        return wanted
    }

    private static func reconcile(_ item: Existing, content: SessionActivityAttributes.ContentState, window: Date, now: Date) -> [Command] {
        let changed = item.content != content
        switch item.phase {
        case .pending:
            guard changed else { return [] }
            let startsAt: Date? = window > now ? window : nil
            return [
                .discard(item.id),
                .present(content, reservationID: item.id, startsAt: startsAt)
            ]
        case .live:
            // Ukončení aktivity ji hned sundá z Dynamic Islandu. Dokud termín běží, jen aktualizujeme obsah.
            return changed ? [.refresh(item.id, content)] : []
        case .finished:
            let startsAt: Date? = window > now ? window : nil
            return [
                .discard(item.id),
                .present(content, reservationID: item.id, startsAt: startsAt)
            ]
        }
    }
}

extension SessionActivityAttributes.ContentState {
    init(_ reservation: Reservation) {
        self.init(
            room: reservation.room,
            start: reservation.start,
            end: reservation.end,
            bufferMinutes: reservation.bufferMinutes,
            guestCount: reservation.guestCount
        )
    }
}

enum SessionActivityCenter {
    private static let logger = Logger(subsystem: "cz.privofit.app", category: "live-activity")

    @MainActor private enum Queue {
        static var generation = 0
        static var tail: Task<Void, Never>?
    }

    static func sync(_ reservations: [Reservation]) {
        guard SessionActivityProcess.tracksActivities else { return }
        let snapshot = reservations
        Task { @MainActor in
            Queue.generation += 1
            let token = Queue.generation
            let previous = Queue.tail
            let next = Task {
                await previous?.value
                let current = await Queue.generation
                guard token == current else { return }
                await perform(snapshot)
            }
            Queue.tail = next
        }
    }

    static func settle() async {
        let tail = await Queue.tail
        await tail?.value
    }

    private static func perform(_ reservations: [Reservation]) async {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        var seen: [String: Activity<SessionActivityAttributes>] = [:]
        for activity in Activity<SessionActivityAttributes>.activities {
            let id = activity.attributes.reservationID
            if let previous = seen[id] {
                if rank(activity.activityState) > rank(previous.activityState) {
                    await previous.end(nil, dismissalPolicy: .immediate)
                    seen[id] = activity
                } else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                continue
            }
            seen[id] = activity
        }
        let existing: [SessionActivityPlanner.Existing] = enabled ? seen.compactMap { id, activity in
            guard let phase = phase(of: activity.activityState) else { return nil }
            return .init(id: id, phase: phase, content: activity.content.state)
        } : seen.keys.map { .init(id: $0, phase: .live, content: .init(room: "", start: .distantPast, end: .distantPast, bufferMinutes: 0, guestCount: 1)) }
        let commands = enabled
            ? SessionActivityPlanner.commands(reservations: reservations, existing: existing, now: Date())
            : existing.map { .discard($0.id) }
        for command in commands {
            await run(command)
        }
    }

    private static func rank(_ state: ActivityState) -> Int {
        switch state {
        case .active, .stale: return 3
        case .pending: return 2
        case .ended: return 1
        case .dismissed: return 0
        @unknown default: return 3
        }
    }

    private static func phase(of state: ActivityState) -> SessionActivityPlanner.Existing.Phase? {
        switch state {
        case .pending: return .pending
        case .active, .stale: return .live
        case .ended: return .finished
        case .dismissed: return nil
        @unknown default: return .live
        }
    }

    private static func run(_ command: SessionActivityPlanner.Command) async {
        let activities = Activity<SessionActivityAttributes>.activities
        switch command {
        case .discard(let id):
            for activity in activities where activity.attributes.reservationID == id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        case .present(let state, let reservationID, let startsAt):
            await present(state, reservationID: reservationID, startsAt: startsAt)
        case .refresh(let id, let state):
            guard let activity = activities.first(where: {
                $0.attributes.reservationID == id && ($0.activityState == .active || $0.activityState == .stale || $0.activityState == .pending)
            }) else { return }
            await activity.update(activityContent(state, now: Date()))
        }
    }

    private static func present(_ state: SessionActivityAttributes.ContentState, reservationID: String, startsAt: Date?) async {
        let attributes = SessionActivityAttributes(reservationID: reservationID)
        let content = activityContent(state, now: Date())
        do {
            if let startsAt, startsAt > Date() {
                let range = SessionActivityTiming.range(from: state.start, to: state.occupiedUntil)
                let alert = AlertConfiguration(
                    title: LocalizedStringResource("liveactivity.alert.title"),
                    body: LocalizedStringResource(stringLiteral: "\(state.room) · \(range)"),
                    sound: .default
                )
                // Pending aktivitu neukončujeme. end(.after) by zrušil naplánovaný start.
                _ = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil,
                    style: .standard,
                    alertConfiguration: alert,
                    start: startsAt
                )
            } else {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil, style: .standard)
            }
        } catch {
            logger.error("Live Activity se nepodařilo založit: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func activityContent(_ state: SessionActivityAttributes.ContentState, now: Date) -> ActivityContent<SessionActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: state.staleDate(at: now), relevanceScore: state.relevance(at: now))
    }
}
