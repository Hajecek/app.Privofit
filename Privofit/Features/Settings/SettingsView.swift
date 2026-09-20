import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @ObservedObject private var prefs = NotificationPreferencesStore.shared
    @State private var busy = false
    @State private var error: String?
    @State private var syncTask: Task<Void, Never>?
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
            notificationsSection
            if let error { Section { FailureView(message: error) } }
        }.scrollContentBackground(.hidden).brandBackground().navigationTitle(L10n.tr("settings.title")).mainToolbar()
            .task { await app.notifications.refresh() }
            .onDisappear { syncTask?.cancel() }
    }
    @ViewBuilder private var notificationsSection: some View {
        if app.notifications.status == .denied {
            Section {
                Button(L10n.tr("settings.system")) { openSystemSettings() }
            } header: {
                Text(L10n.tr("notifications.title"))
            } footer: {
                Text(L10n.tr("notifications.denied"))
            }
        } else if app.notifications.status == .notDetermined {
            Section {
                Button(L10n.tr("notifications.enable")) {
                    Task { do { try await app.notifications.request() } catch { self.error = FriendlyError.message(error) } }
                }
            } header: {
                Text(L10n.tr("notifications.title"))
            } footer: {
                Text(L10n.tr("notifications.notSet"))
            }
        } else {
            Section {
                Toggle(isOn: Binding(
                    get: { prefs.masterEnabled },
                    set: { newValue in
                        withAnimation { prefs.masterEnabled = newValue }
                        if newValue { UIApplication.shared.registerForRemoteNotifications() }
                        schedulePreferenceSync()
                    }
                )) {
                    Label(L10n.tr("notifications.push"), systemImage: "bell")
                }
                if prefs.masterEnabled {
                    ForEach(NotificationChannel.allCases) { channel in
                        Toggle(isOn: Binding(
                            get: { prefs.isEnabled(channel) },
                            set: { newValue in
                                prefs.setEnabled(channel, newValue)
                                schedulePreferenceSync()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.title)
                                Text(channel.subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button(L10n.tr("settings.system")) { openSystemSettings() }
                if let error = app.notifications.registrationError { Text(error).font(.footnote) }
            } header: {
                Text(L10n.tr("notifications.title"))
            } footer: {
                Text(L10n.tr("notifications.footer"))
            }
        }
    }
    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
    private func schedulePreferenceSync() {
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await app.syncPushPreferences()
        }
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
