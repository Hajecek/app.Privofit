import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var busy = false
    @State private var error: String?
    @State private var biometryVerified = false

    private var current: OnboardingStep { OnboardingStep(rawValue: step) ?? .welcome }
    private var biometrySymbol: String {
        app.biometrics.name.localizedCaseInsensitiveContains("touch") ? "touchid" : "faceid"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progress
                    .padding(.top, 12)
                    .padding(.horizontal, 28)
                ZStack {
                    page
                        .id(step)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                actions
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { OnboardingGlow(step: step, reduceMotion: reduceMotion) }
            .brandBackground()
            .navigationBarTitleDisplayMode(.inline)
            .clearTopChrome()
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: back) {
                            Image(systemName: "chevron.backward")
                                .font(.body.weight(.semibold))
                        }
                        .disabled(busy)
                        .accessibilityLabel(L10n.tr("common.back"))
                        .accessibilityIdentifier("onboarding.back")
                    }
                }
                ToolbarItem(placement: .principal) { BrandMark(size: 26) }
            }
        }
        .interactiveDismissDisabled()
        .sensoryFeedback(.selection, trigger: step)
        .onChange(of: step) { _, new in
            if OnboardingStep(rawValue: new) != .biometrics { biometryVerified = false }
        }
    }

    private var pageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .offset(x: 36)),
                removal: .opacity.combined(with: .offset(x: -28))
            )
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step ? Brand.lime : Color.primary.opacity(0.1))
                    .frame(width: item.rawValue == step ? 22 : 8, height: 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.78), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr("onboarding.progress"))
        .accessibilityValue("\(step + 1) / \(OnboardingStep.allCases.count)")
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if current != .place {
                    OnboardingArtwork(step: current, symbol: biometrySymbol, verified: biometryVerified)
                        .frame(maxWidth: .infinity)
                        .frame(height: current == .enter ? 300 : 236)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.tr(current.titleKey))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(-0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.tr(current.bodyKey))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if current == .welcome { OnboardingFeatureGrid() }
                if current == .biometrics {
                    StatusBadge(title: app.biometrics.name, symbol: app.biometrics.available ? "checkmark.shield" : "info.circle")
                }
                if current == .ready { OnboardingRecap() }
                if let error { FailureView(message: error) }
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 8)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if current == .place {
                LocationRadarButton(
                    title: L10n.tr(current.actionKey),
                    hint: L10n.tr("onboarding.location.hint"),
                    busy: busy
                ) { Task { await action() } }
            } else {
                PrimaryButton(title: L10n.tr(current.actionKey), symbol: current == .ready ? "checkmark" : "arrow.right", busy: busy) {
                    Task { await primary() }
                }
                .disabled(current == .biometrics && !app.biometrics.available)
                .accessibilityIdentifier("onboarding.next")
            }
            if current.allowsSkip {
                Button(L10n.tr("common.notNow")) { next() }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .disabled(busy)
                    .accessibilityIdentifier("onboarding.skip")
            }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private func back() {
        guard step > 0, !busy else { return }
        error = nil
        move { step -= 1 }
    }

    private func next() {
        error = nil
        let last = OnboardingStep.allCases.count - 1
        move {
            if step < last { step += 1 } else { app.finishOnboarding() }
        }
    }

    private func move(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86), change)
    }

    private func primary() async {
        switch current {
        case .alerts, .place, .biometrics: await action()
        default: next()
        }
    }

    private func action() async {
        guard !busy else { return }
        busy = true
        let started = step
        defer { busy = false }
        do {
            switch OnboardingStep(rawValue: started) {
            case .alerts:
                try await app.notifications.request()
            case .place:
                _ = await app.location.requestAccess()
            case .biometrics:
                try await app.biometrics.authenticate(reason: L10n.tr("biometry.reason"))
                app.preferences.biometrics = true
                biometryVerified = true
                SystemFeedback.success()
                if !reduceMotion { try? await Task.sleep(for: .milliseconds(450)) }
            default:
                break
            }
            guard step == started else { return }
            next()
        } catch {
            guard step == started else { return }
            self.error = FriendlyError.message(error)
        }
    }
}

private enum OnboardingMotion {
    /// XCTest waits until animations idle. Looping timelines never do.
    static var plays: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome, reserve, enter, rhythm, alerts, place, biometrics, ready

    var titleKey: String {
        switch self {
        case .welcome: return "onboarding.0.title"
        case .reserve: return "onboarding.reserve.title"
        case .enter: return "onboarding.enter.title"
        case .rhythm: return "onboarding.rhythm.title"
        case .alerts: return "onboarding.1.title"
        case .place: return "onboarding.location.title"
        case .biometrics: return "onboarding.2.title"
        case .ready: return "onboarding.3.title"
        }
    }

    var bodyKey: String {
        switch self {
        case .welcome: return "onboarding.0.body"
        case .reserve: return "onboarding.reserve.body"
        case .enter: return "onboarding.enter.body"
        case .rhythm: return "onboarding.rhythm.body"
        case .alerts: return "onboarding.1.body"
        case .place: return "onboarding.location.body"
        case .biometrics: return "onboarding.2.body"
        case .ready: return "onboarding.3.body"
        }
    }

    var actionKey: String {
        switch self {
        case .welcome, .reserve, .enter, .rhythm: return "onboarding.0.action"
        case .alerts: return "onboarding.1.action"
        case .place: return "onboarding.location.action"
        case .biometrics: return "onboarding.2.action"
        case .ready: return "onboarding.3.action"
        }
    }

    var allowsSkip: Bool { self == .alerts || self == .place || self == .biometrics }
}

private struct OnboardingArtwork: View {
    let step: OnboardingStep
    var symbol: String
    var verified: Bool

    var body: some View {
        switch step {
        case .welcome: WelcomeArt()
        case .reserve: ReserveArt()
        case .enter: EnterArt()
        case .rhythm: StreakArt()
        case .alerts: AlertArt()
        case .place: EmptyView()
        case .biometrics: BiometryArt(symbol: symbol, verified: verified)
        case .ready: ReadyArt()
        }
    }
}

private struct WelcomeArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animate: Bool { !reduceMotion && OnboardingMotion.plays }

    var body: some View {
        TimelineView(.animation(minimumInterval: animate ? 1.0 / 30.0 : 60, paused: !animate)) { timeline in
            let time = animate ? timeline.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                Circle()
                    .stroke(Brand.lime.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [7, 9]))
                    .frame(width: 214, height: 214)
                    .rotationEffect(.degrees(time * 16))
                Circle()
                    .stroke(Brand.lime.opacity(0.18), lineWidth: 10)
                    .frame(width: 176, height: 176)
                AccessToken()
                    .offset(y: sin(time * 1.5) * 7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

private struct ReserveArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = false
    private let slots = ["07:00", "08:00", "09:00"]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                let on = selected && index == 1
                HStack {
                    Text(slot).font(.headline.monospacedDigit())
                    Spacer()
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(on ? Brand.ink : Color.primary.opacity(0.28))
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(on ? Brand.ink : .primary)
                .background(on ? Brand.lime : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .scaleEffect(on && !reduceMotion ? 1.03 : 1)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if reduceMotion { selected = true; return }
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { selected = true }
        }
        .accessibilityHidden(true)
    }
}

private struct EnterArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened = false

    var body: some View {
        DoorPortal(opened: opened)
            .task {
                if reduceMotion { opened = true; return }
                try? await Task.sleep(for: .milliseconds(380))
                opened = true
            }
    }
}

private struct StreakArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = 0

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "flame.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(Brand.lime)
                .scaleEffect(lit > 0 ? 1 : 0.86)
            HStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(index < lit ? Brand.lime : Color.primary.opacity(0.08))
                        .frame(width: 16, height: index < lit ? 40 : 26)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let target = 5
            if reduceMotion { lit = target; return }
            for value in 1...target {
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) { lit = value }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct AlertArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCard = false

    private var animate: Bool { !reduceMotion && OnboardingMotion.plays }

    var body: some View {
        TimelineView(.animation(minimumInterval: animate ? 1.0 / 30.0 : 60, paused: !animate)) { timeline in
            let wobble = animate ? sin(timeline.date.timeIntervalSinceReferenceDate * 2.6) * 7 : 0
            VStack(spacing: 16) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Brand.lime)
                    .rotationEffect(.degrees(wobble), anchor: .top)
                BrandCard {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar").font(.title3).foregroundStyle(Color("AccentColor"))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.tr("redesign.reminderTitle")).font(.headline)
                            Text(L10n.tr("redesign.reminderExample")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .offset(y: showCard || reduceMotion ? 0 : 18)
                .opacity(showCard || reduceMotion ? 1 : 0)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8).delay(0.12)) { showCard = true }
        }
        .accessibilityHidden(true)
    }
}

private struct BiometryArt: View {
    var symbol: String
    var verified: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LocationRings(active: !verified && !reduceMotion && OnboardingMotion.plays, diameter: 168)
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(Brand.lime.opacity(0.12))
                .frame(width: 148, height: 148)
            Image(systemName: verified ? "checkmark" : symbol)
                .font(.system(size: verified ? 52 : 62, weight: .light))
                .foregroundStyle(Brand.lime)
                .contentTransition(.symbolEffect(.replace))
            if !verified && !reduceMotion && OnboardingMotion.plays {
                ScanBeam()
                    .frame(width: 148, height: 148)
                    .mask(RoundedRectangle(cornerRadius: 40, style: .continuous).frame(width: 148, height: 148))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: verified)
        .accessibilityHidden(true)
    }
}

private struct ReadyArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Brand.lime.opacity(0.22), lineWidth: 14)
                .frame(width: 168, height: 168)
                .scaleEffect(drawn || reduceMotion ? 1 : 0.7)
            Circle()
                .trim(from: 0, to: drawn || reduceMotion ? 1 : 0.08)
                .stroke(Brand.lime, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 168, height: 168)
                .rotationEffect(.degrees(-90))
            Image(systemName: "checkmark")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Brand.lime)
                .scaleEffect(drawn || reduceMotion ? 1 : 0.4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.72)) { drawn = true }
        }
        .accessibilityHidden(true)
    }
}

private struct OnboardingFeatureGrid: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    private let items: [(String, String)] = [
        ("calendar", "onboarding.chip.reserve"),
        ("door.left.hand.open", "onboarding.chip.door"),
        ("flame.fill", "onboarding.chip.streak"),
        ("person.crop.rectangle", "onboarding.chip.membership")
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Label(L10n.tr(item.1), systemImage: item.0)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(shown || reduceMotion ? 1 : 0)
                    .offset(y: shown || reduceMotion ? 0 : 12)
                    .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8).delay(Double(index) * 0.06), value: shown)
            }
        }
        .task { shown = true }
    }
}

private struct OnboardingRecap: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    private let items = ["onboarding.chip.reserve", "onboarding.chip.door", "onboarding.chip.streak", "onboarding.chip.membership"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, key in
                HStack(spacing: 10) {
                    Image(systemName: index < shown ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(index < shown ? Brand.limeDeep : Color.primary.opacity(0.25))
                    Text(L10n.tr(key)).font(.subheadline.weight(.semibold))
                }
                .opacity(index < shown || reduceMotion ? 1 : 0.35)
            }
        }
        .task {
            if reduceMotion { shown = items.count; return }
            for value in 1...items.count {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { shown = value }
            }
        }
    }
}

private struct LocationRadarButton: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var title: String
    var hint: String
    var busy: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    LocationRings(active: !busy && !reduceMotion && OnboardingMotion.plays, diameter: 96)
                    Circle().fill(Brand.lime).frame(width: 62, height: 62)
                    if busy {
                        ProgressView().tint(Brand.ink)
                    } else {
                        Image(systemName: "location.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Brand.ink)
                    }
                }
                .frame(width: 108, height: 108)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Brand.text(scheme))
                        .multilineTextAlignment(.leading)
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            .padding(.trailing, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(Brand.surface(scheme), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Brand.lime, lineWidth: 1.5)
            }
        }
        .buttonStyle(OnboardingPressStyle())
        .disabled(busy)
        .accessibilityIdentifier("onboarding.next")
        .accessibilityHint(hint)
    }
}

private struct LocationRings: View {
    var active: Bool
    var diameter: CGFloat = 140

    var body: some View {
        Group {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(0..<3, id: \.self) { index in
                            let phase = (time / 1.8 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                            Circle()
                                .stroke(Brand.lime.opacity(0.55 * (1 - phase)), lineWidth: 2)
                                .frame(width: diameter * 0.42, height: diameter * 0.42)
                                .scaleEffect(0.55 + phase * 1.7)
                        }
                    }
                }
            } else {
                ZStack {
                    Circle().stroke(Brand.lime.opacity(0.28), lineWidth: 1.5).frame(width: diameter * 0.62, height: diameter * 0.62)
                    Circle().stroke(Brand.lime.opacity(0.14), lineWidth: 1.5).frame(width: diameter, height: diameter)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ScanBeam: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = (sin(timeline.date.timeIntervalSinceReferenceDate * 1.7) + 1) / 2
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Brand.lime.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom))
                .frame(height: 16)
                .offset(y: -58 + phase * 116)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct OnboardingGlow: View {
    var step: Int
    var reduceMotion: Bool

    private var animate: Bool { !reduceMotion && OnboardingMotion.plays }

    var body: some View {
        TimelineView(.animation(minimumInterval: animate ? 1.0 / 30.0 : 60, paused: !animate)) { timeline in
            let drift = animate ? sin(timeline.date.timeIntervalSinceReferenceDate / 2.8) * 18 : 0
            ZStack {
                Circle()
                    .fill(Brand.lime.opacity(0.2))
                    .frame(width: 260, height: 260)
                    .blur(radius: 48)
                    .offset(x: 130 + drift, y: -230)
                Circle()
                    .fill(Brand.limeDeep.opacity(0.14))
                    .frame(width: 210, height: 210)
                    .blur(radius: 42)
                    .offset(x: -150, y: 60 - drift + CGFloat(step) * CGFloat(6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct OnboardingPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: ButtonStyle.Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
