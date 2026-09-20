import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        @Bindable var preferences = app.preferences
        Form {
            Section(L10n.tr("settings.appearance")) {
                Picker(L10n.tr("settings.appearance"), selection: $preferences.appearance) {
                    ForEach(Appearance.allCases) { Text(L10n.tr("appearance.\($0.rawValue)")).tag($0) }
                }
            }
            Section(L10n.tr("settings.security")) {
                Toggle(app.biometrics.name, isOn: Binding(get: { preferences.biometrics }, set: { enable in Task { await changeBiometrics(enable) } }))
                    .disabled(busy || (!app.biometrics.available && !preferences.biometrics))
                Text(L10n.tr("settings.biometry.body")).font(.footnote)
            }
            Section(L10n.tr("notifications.title")) {
                Text(L10n.tr(notificationKey))
                if app.notifications.status == .notDetermined {
                    Button(L10n.tr("onboarding.1.action")) { Task { do { try await app.notifications.request() } catch { self.error = FriendlyError.message(error) } } }
                }
                Button(L10n.tr("settings.system")) { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                if let error = app.notifications.registrationError { Text(error).font(.footnote) }
            }
            if let error { Section { FailureView(message: error) } }
        }.scrollContentBackground(.hidden).brandBackground().navigationTitle(L10n.tr("settings.title")).mainToolbar().task { await app.notifications.refresh() }
    }
    private var notificationKey: String {
        switch app.notifications.status { case .authorized, .provisional, .ephemeral: return "notifications.allowed"; case .denied: return "notifications.denied"; default: return "notifications.notSet" }
    }
    private func changeBiometrics(_ enable: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        // An unlocked, server-authenticated session can recover after biometry
        // becomes unavailable. The locked root offers sign-out + fresh login.
        if !enable && !app.biometrics.available && !app.locked { app.preferences.biometrics = false; return }
        do { try await app.biometrics.authenticate(reason: L10n.tr("biometry.reason")); app.preferences.biometrics = enable }
        catch { self.error = FriendlyError.message(error) }
    }
}
