import SwiftUI

struct DoorEntryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.tr("door.entry.title")).font(.largeTitle.weight(.bold)).tracking(-1)
                        Text(L10n.tr("door.entry.body")).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.top, 12)
                DoorHero()
                BrandCard {
                    VStack(alignment: .leading, spacing: 20) {
                        EntryInstruction(number: 1, title: L10n.tr("redesign.entry.1"), symbol: "location")
                        Divider()
                        EntryInstruction(number: 2, title: L10n.tr("redesign.entry.2"), symbol: "hand.tap")
                        Divider()
                        EntryInstruction(number: 3, title: L10n.tr("redesign.entry.3"), symbol: "door.left.hand.open")
                    }
                }
                Label(L10n.tr("door.security"), systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.brandBackground().navigationTitle(L10n.tr("tab.door")).mainToolbar()
    }
}
private struct EntryInstruction: View {
    let number: Int
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: 14) {
            Text(number.formatted()).font(.caption.weight(.bold)).frame(width: 30, height: 30).background(Color.primary.opacity(0.06), in: Circle())
            Text(title).font(.subheadline)
            Spacer(minLength: 0)
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }
}
struct DoorView: View {
    @State var model: DoorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var confirm = false
    @State private var appeared = false
    @State private var denyShake: CGFloat = 0
    private var app: AppModel { model.app }
    private var opened: Bool { model.state == .confirmed || (model.state == .cooldown && model.confirmedAt != nil) }
    private var failing: Bool { model.state.isFailure }
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if app.isDemo { StatusBadge(title: L10n.tr("demo.door"), symbol: "hammer") }
                    Label(model.doorName ?? L10n.tr("door.entrance"), systemImage: "location.fill")
                        .font(.caption.weight(.semibold)).padding(.top, 8)
                    Text(L10n.tr(title)).font(.largeTitle.weight(.bold)).tracking(-1)
                        .multilineTextAlignment(.center).accessibilityIdentifier("door.state")
                    DoorPortal(opened: opened, checking: model.state.busy, denied: failing)
                        .frame(height: 330)
                        .modifier(AccessDeniedShake(progress: denyShake))
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
                        .opacity(appeared ? 1 : 0)
                    stateContent.font(.subheadline).multilineTextAlignment(.center).frame(maxWidth: 420)
                    if let booking = ReservationCalendar.current(app.reservations), !failing {
                        HStack { Image(systemName: "calendar"); Text(booking.start, style: .time); Text("–"); Text(booking.end, style: .time) }
                            .font(.subheadline.weight(.medium)).padding(12).background(Brand.ink.opacity(0.05), in: Capsule())
                    }

                }.padding(.horizontal, 28).padding(.bottom, 24).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }.background(canvas.ignoresSafeArea()).foregroundStyle(onCanvas)
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
                .navigationTitle(L10n.tr("tab.door")).navigationBarTitleDisplayMode(.inline)
                .clearTopChrome()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        BrandMark(size: 28, showsName: false)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }.disabled(model.state.busy).accessibilityLabel(L10n.tr("common.close"))
                    }
                }
        }.tint(onCanvas).preferredColorScheme(.light)
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
            .confirmationDialog(L10n.tr("door.confirmTitle"), isPresented: $confirm, titleVisibility: .visible) {
                Button(L10n.tr("door.open")) { Task { await model.open() } }.accessibilityIdentifier("door.confirm")
                Button(L10n.tr("common.cancel"), role: .cancel) { }
            } message: { Text(L10n.tr("door.confirmBody")) }
            .overlay { if phase != .active { Brand.night.ignoresSafeArea().overlay { BrandMark(size: 36) } } }
    }
    private var footer: some View {
        VStack(spacing: 8) {
                    if model.state.canSend && model.prepared {
                        Button { confirm = true } label: {
                            HStack {
                                Image(systemName: failing ? "arrow.clockwise" : "lock.open")
                                Text(L10n.tr(failing ? "common.retry" : "door.confirmAction"))
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                                .font(.headline).padding(22).frame(maxWidth: .infinity)
                                .foregroundStyle(failing ? Brand.alert : Brand.lime)
                                .background(failing ? Color(hex: 0xFFF6F1) : Brand.ink, in: RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain).accessibilityHint(L10n.tr("door.confirmHint")).accessibilityIdentifier("door.prepare")
                    }
                    if model.state == .accepted || model.state == .uncertain {
                        Button(L10n.tr("door.reconcile")) { Task { await model.reconcile() } }
                            .buttonStyle(.borderedProminent).tint(Brand.ink).foregroundStyle(Brand.lime).controlSize(.large)
                            .disabled(!model.prepared).accessibilityIdentifier("door.reconcile")
                    }
                    if model.state == .confirmed || model.state == .cooldown {
                        Button(L10n.tr("redesign.backToOverview")) { dismiss() }.font(.headline).frame(minHeight: 52)
                    }
                    if case .denied = model.state { Button(L10n.tr("tab.membership")) { app.tab = .membership; dismiss() }.frame(minHeight: 44) }
                    ConfiguredLink(title: L10n.tr("profile.support"), key: "SupportURL").font(.subheadline)
        }.padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 8)
            .frame(maxWidth: .infinity).background(canvas)
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
            Text(reason.isEmpty ? L10n.tr("door.failure.denied.body") : reason)
                .font(.body.weight(.medium))
        case .failed(let reason):
            Text(reason.isEmpty ? L10n.tr("door.failure.body") : reason)
                .font(.body.weight(.medium))
        case .accepted, .uncertain: Text(L10n.tr("door.uncertain.body"))
        default: Text(L10n.tr("door.wait"))
        }
    }
    private func playDeniedFeedback() {
        SystemFeedback.denied()
        guard !reduceMotion else { return }
        denyShake = 0
        withAnimation(.easeOut(duration: 0.52)) { denyShake = 1 }
    }
}
