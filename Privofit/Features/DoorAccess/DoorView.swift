import SwiftUI

struct DoorView: View {
    @State var model: DoorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var appeared = false
    @State private var denyShake: CGFloat = 0
    private var app: AppModel { model.app }
    private var opened: Bool { model.state == .confirmed || (model.state == .cooldown && model.confirmedAt != nil) }
    private var failing: Bool { model.state.isFailure }
    private var canOpen: Bool { model.state.canSend && model.prepared && !model.state.busy }
    private var canvas: Color { failing ? Brand.alert : Brand.lime }
    private var onCanvas: Color { failing ? Color(hex: 0xFFF6F1) : Brand.ink }
    private var title: String {
        switch model.state {
        case .idle: return "door.ready"
        case .checking: return "door.checking"
        case .authenticating: return "door.authenticating"
        case .sending: return "door.sending"
        case .confirmed: return "door.success"
        case .cooldown: return "door.cooldown"
        case .accepted: return "door.accepted"
        case .uncertain: return "door.uncertain"
        case .denied: return "door.denied"
        case .failed: return "door.failed"
        }
    }
    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Button(action: attemptOpen) {
                    VStack(spacing: 20) {
                        Spacer(minLength: 4)
                        screen
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 28)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DoorTapStyle())
                .accessibilityIdentifier(canOpen ? "door.prepare" : "door.screen")
                .accessibilityLabel(L10n.tr(title))
                .accessibilityHint(canOpen ? L10n.tr("door.confirmHint") : "")
                footer
            }
            .foregroundStyle(onCanvas)
        }
        .tint(onCanvas)
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(model.state.busy)
        .task {
            withAnimation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.85)) { appeared = true }
            if !model.prepared { await model.restorePending() }
        }
        .task(id: model.state) {
            guard !model.isPreview else { return }
            if model.state == .confirmed {
                try? await Task.sleep(for: .seconds(2)); guard !Task.isCancelled else { return }; model.advanceCooldown()
            } else if model.state == .cooldown {
                let remaining = max(0, app.cooldownUntil.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(remaining)); guard !Task.isCancelled else { return }; model.advanceCooldown()
            }
        }
        .sensoryFeedback(.success, trigger: model.state == .confirmed)
        .onChange(of: model.state.isFailure) { _, failing in
            if failing { playDeniedFeedback() } else { denyShake = 0 }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82), value: model.state.isFailure)
        .overlay {
            if phase == .background && model.state != .authenticating {
                Brand.night.ignoresSafeArea().overlay { BrandMark(size: 36) }
            }
        }
    }
    private var topBar: some View {
        HStack {
            BrandMark(size: 28, showsName: false)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(model.state.busy)
            .accessibilityLabel(L10n.tr("common.close"))
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
    private var screen: some View {
        VStack(spacing: 20) {
            if app.isDemo { StatusBadge(title: L10n.tr("demo.door"), symbol: "hammer") }
            Text(L10n.tr(title)).font(.largeTitle.weight(.bold)).tracking(-1)
                .multilineTextAlignment(.center).accessibilityIdentifier("door.state")
            ZStack {
                if model.state.busy { VerifyWaves(tint: onCanvas) }
                DoorPortal(opened: opened, denied: failing)
                    .frame(height: 300)
            }
                .modifier(AccessDeniedShake(progress: denyShake))
                .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
                .opacity(appeared ? 1 : 0)
            stateContent.font(.subheadline).multilineTextAlignment(.center).frame(maxWidth: 420)
            if let booking = ReservationCalendar.current(app.reservations), !failing {
                HStack { Image(systemName: "calendar"); Text(ReservationCalendar.occupiedRange(booking.start, booking.end, bufferMinutes: booking.bufferMinutes)) }
                    .font(.subheadline.weight(.medium)).padding(12).background(Brand.ink.opacity(0.05), in: Capsule())
            }
        }
    }
    @ViewBuilder private var footer: some View {
        VStack(spacing: 10) {
            if model.state == .accepted || model.state == .uncertain {
                Button(L10n.tr("door.reconcile")) { Task { await model.reconcile() } }
                    .font(.headline)
                    .disabled(!model.prepared)
                    .accessibilityIdentifier("door.reconcile")
            }
            if case .denied = model.state {
                Button(L10n.tr("tab.membership")) { app.tab = .membership; dismiss() }.font(.headline)
            }
            if model.state == .confirmed || model.state == .cooldown {
                Button { dismiss() } label: {
                    HStack {
                        Text(L10n.tr("redesign.backToOverview")).font(.headline)
                        Spacer()
                        Image(systemName: "arrow.down.right")
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .liquidGlassBar()
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }
    @ViewBuilder private var stateContent: some View {
        switch model.state {
        case .idle: Text(L10n.tr("redesign.doorReadyBody"))
        case .confirmed:
            Text(L10n.tr(app.isDemo ? "demo.door.success" : "door.success.body"))
            if let until = model.entryUntil { LabeledContent(L10n.tr("door.entryUntil")) { Text(until, style: .time) } }
        case .cooldown:
            VStack(spacing: 8) {
                Text(L10n.tr("door.cooldown.body"))
                Text(app.cooldownUntil, style: .timer).monospacedDigit().font(.title3.weight(.semibold))
            }
        case .denied(let reason):
            VStack(spacing: 8) {
                Text(reason.isEmpty ? L10n.tr("door.failure.denied.body") : reason).font(.body.weight(.medium))
                Text(L10n.tr("common.retry")).font(.subheadline.weight(.semibold))
            }
        case .failed(let reason):
            VStack(spacing: 8) {
                Text(reason.isEmpty ? L10n.tr("door.failure.body") : reason).font(.body.weight(.medium))
                Text(L10n.tr("common.retry")).font(.subheadline.weight(.semibold))
            }
        case .accepted, .uncertain: Text(L10n.tr("door.uncertain.body"))
        default: Text(L10n.tr("door.wait"))
        }
    }
    private func attemptOpen() {
        guard canOpen else { return }
        SystemFeedback.tap()
        Task { await model.open() }
    }
    private func playDeniedFeedback() {
        SystemFeedback.denied()
        guard !reduceMotion else { return }
        denyShake = 0
        withAnimation(.easeOut(duration: 0.52)) { denyShake = 1 }
    }
}

private struct DoorTapStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.985 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
