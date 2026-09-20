import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 8) {
                        ForEach(0..<4) { index in Capsule().fill(index <= step ? Color("AccentColor") : Color.primary.opacity(0.08)).frame(height: 4) }
                    }.accessibilityLabel(L10n.tr("onboarding.progress")).accessibilityValue("\(step + 1) / 4").padding(.top, 24)
                    artwork.frame(maxWidth: .infinity, minHeight: 220).padding(.vertical, 12)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.tr("onboarding.\(step).title")).font(.largeTitle.weight(.bold)).tracking(-1)
                        Text(L10n.tr("onboarding.\(step).body")).foregroundStyle(.secondary).lineSpacing(3)
                    }
                    if step == 2 { StatusBadge(title: app.biometrics.name, symbol: app.biometrics.available ? "checkmark.shield" : "info.circle") }
                    if let error { FailureView(message: error) }
                    VStack(spacing: 8) {
                        PrimaryButton(title: L10n.tr("onboarding.\(step).action"), symbol: "arrow.right", busy: busy) { Task { await action() } }
                            .disabled(step == 2 && !app.biometrics.available).accessibilityIdentifier("onboarding.next")
                        if step == 1 || step == 2 {
                            Button(L10n.tr("common.notNow")) { next() }.font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 48).accessibilityIdentifier("onboarding.skip")
                        }
                    }.padding(.top, 8)
                }.padding(.horizontal, 28).padding(.bottom, 28).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }.brandBackground().navigationBarTitleDisplayMode(.inline)
                .clearTopChrome()
                .toolbar { ToolbarItem(placement: .principal) { BrandMark(size: 26) } }
        }.interactiveDismissDisabled()
    }
    @ViewBuilder private var artwork: some View {
        if step == 0 { AccessToken().scaleEffect(reduceMotion ? 1 : 1.12) }
        else if step == 1 {
            VStack(spacing: 14) {
                Image(systemName: "bell.badge").font(.system(size: 60, weight: .light)).foregroundStyle(Color("AccentColor"))
                BrandCard { HStack(spacing: 14) {
                    Image(systemName: "calendar").font(.title2).foregroundStyle(Color("AccentColor"))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("redesign.reminderTitle")).font(.headline)
                        Text(L10n.tr("redesign.reminderExample")).font(.caption).foregroundStyle(.secondary)
                    }
                } }
            }
        } else {
            Image(systemName: step == 2 ? "faceid" : "checkmark.seal")
                .font(.system(size: 84, weight: .ultraLight)).foregroundStyle(Color("AccentColor"))
                .frame(width: 160, height: 160).background(Color("AccentColor").opacity(0.07), in: RoundedRectangle(cornerRadius: 44))
                .accessibilityHidden(true)
        }
    }
    private func next() { error = nil; withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { if step < 3 { step += 1 } else { app.finishOnboarding() } } }
    private func action() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            if step == 1 { try await app.notifications.request() }
            if step == 2 { try await app.biometrics.authenticate(reason: L10n.tr("biometry.reason")); app.preferences.biometrics = true }
            next()
        } catch { self.error = FriendlyError.message(error) }
    }
}
