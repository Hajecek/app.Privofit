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

    struct Plan: Equatable, Sendable {
        var focus: Reservation
        /// Další termín — naplánuje se na konec fokusu, ať se Island přepne i bez otevření appky.
        var successor: Reservation?
    }

    /// Běžící termín, jinak nejbližší otevřená rezervace.
    static func focus(in reservations: [Reservation], now: Date) -> Reservation? {
        plan(reservations: reservations, now: now)?.focus
    }

    static func plan(reservations: [Reservation], now: Date) -> Plan? {
        let open = reservations.filter { $0.occupiedUntil > now }.sorted { $0.start < $1.start }
        guard !open.isEmpty else { return nil }
        let focus = open.filter { $0.start <= now }.max { $0.start < $1.start } ?? open[0]
        guard let index = open.firstIndex(where: { $0.id == focus.id }) else {
            return Plan(focus: focus, successor: nil)
        }
        let candidate = index + 1 < open.count ? open[index + 1] : nil
        // Další jen když navazuje (do 6 h po konci) — neplánovat vzdálené termíny.
        let successor: Reservation?
        if let next = candidate {
            let focusEnd = SessionActivityAttributes.ContentState(focus).occupiedUntil
            let gap = next.start.timeIntervalSince(focusEnd)
            successor = gap <= 6 * 60 * 60 ? next : nil
        } else {
            successor = nil
        }
        return Plan(focus: focus, successor: successor)
    }

    static func commands(reservations: [Reservation], existing: [Existing], now: Date) -> [Command] {
        guard let plan = plan(reservations: reservations, now: now) else {
            return existing.map { .discard($0.id) }
        }
        var wanted: [String: (Reservation, Date?)] = [:]
        let focusContent = SessionActivityAttributes.ContentState(plan.focus)
        let focusStart: Date? = focusContent.windowStart > now ? focusContent.windowStart : nil
        wanted[plan.focus.id] = (plan.focus, focusStart)

        if let next = plan.successor {
            let nextContent = SessionActivityAttributes.ContentState(next)
            // Spustit další až po konci aktuálního (nebo v jeho lead okně, podle toho, co je později).
            let handoff = max(focusContent.occupiedUntil, nextContent.windowStart)
            let startsAt: Date? = handoff > now ? handoff : nil
            wanted[next.id] = (next, startsAt)
        }

        var commands: [Command] = []
        for item in existing where wanted[item.id] == nil {
            commands.append(.discard(item.id))
        }
        for (id, pair) in wanted {
            let (reservation, startsAt) = pair
            let content = SessionActivityAttributes.ContentState(reservation)
            if let item = existing.first(where: { $0.id == id }) {
                commands.append(contentsOf: reconcile(item, content: content, startsAt: startsAt, now: now))
            } else {
                commands.append(.present(content, reservationID: id, startsAt: startsAt))
            }
        }
        return commands
    }

    private static func reconcile(
        _ item: Existing,
        content: SessionActivityAttributes.ContentState,
        startsAt: Date?,
        now: Date
    ) -> [Command] {
        let changed = item.content != content
        switch item.phase {
        case .pending:
            // Pending musí sedět na správný start i obsah.
            let scheduledMismatch = startsAt == nil
            guard changed || scheduledMismatch else { return [] }
            return [
                .discard(item.id),
                .present(content, reservationID: item.id, startsAt: startsAt)
            ]
        case .live:
            if startsAt != nil {
                // Tahle rezervace má být ještě jen naplánovaná — restartovat jako pending.
                return [
                    .discard(item.id),
                    .present(content, reservationID: item.id, startsAt: startsAt)
                ]
            }
            return changed ? [.refresh(item.id, content)] : []
        case .finished:
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
        static var handoff: Task<Void, Never>?
        static var latest: [Reservation] = []
        static var observes = false
    }

    static func sync(_ reservations: [Reservation]) {
        guard SessionActivityProcess.tracksActivities else { return }
        let snapshot = reservations
        Task { @MainActor in
            Queue.latest = snapshot
            startObservingIfNeeded()
            Queue.generation += 1
            let token = Queue.generation
            let previous = Queue.tail
            let next = Task {
                await previous?.value
                let current = await Queue.generation
                guard token == current else { return }
                await perform(snapshot)
                await armHandoff(snapshot)
            }
            Queue.tail = next
        }
    }

    static func settle() async {
        let tail = await Queue.tail
        await tail?.value
    }

    @MainActor
    private static func startObservingIfNeeded() {
        guard !Queue.observes else { return }
        Queue.observes = true
        Task {
            for await _ in Activity<SessionActivityAttributes>.activityUpdates {
                let reservations = await MainActor.run { Queue.latest }
                await perform(reservations)
                await armHandoff(reservations)
            }
        }
    }

    /// Probudí sync na hranicích termínu, ať se stará aktivita sundá a naskočí další.
    private static func armHandoff(_ reservations: [Reservation]) async {
        let previous = await MainActor.run { () -> Task<Void, Never>? in
            let old = Queue.handoff
            Queue.handoff = nil
            return old
        }
        previous?.cancel()
        let now = Date()
        guard let plan = SessionActivityPlanner.plan(reservations: reservations, now: now) else { return }
        let focus = SessionActivityAttributes.ContentState(plan.focus)
        var wakeDates: [Date] = []
        if focus.start > now { wakeDates.append(focus.start) }
        if focus.occupiedUntil > now { wakeDates.append(focus.occupiedUntil) }
        if let next = plan.successor {
            let handoff = max(focus.occupiedUntil, SessionActivityAttributes.ContentState(next).windowStart)
            if handoff > now { wakeDates.append(handoff) }
        }
        guard let wake = wakeDates.min() else { return }
        let delay = wake.timeIntervalSince(now)
        let task = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000) + 250_000_000)
            }
            guard !Task.isCancelled else { return }
            let latest = await MainActor.run { Queue.latest }
            await perform(latest)
            await armHandoff(latest)
        }
        await MainActor.run { Queue.handoff = task }
    }

    private static func perform(_ reservations: [Reservation]) async {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let now = Date()
        var seen: [String: Activity<SessionActivityAttributes>] = [:]
        for activity in Activity<SessionActivityAttributes>.activities {
            // Doběhlé aktivity hned pryč — Island jinak zůstane na 0:00.
            if activity.content.state.occupiedUntil <= now {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
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
            ? SessionActivityPlanner.commands(reservations: reservations, existing: existing, now: now)
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
