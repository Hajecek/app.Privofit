import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @State private var password = false
    @State private var deleteConfirmation = false
    @State private var deleting = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) { Avatar(name: app.member?.firstName ?? "P", size: 48); VStack(alignment: .leading, spacing: 4) {
                    Text(app.member?.firstName ?? L10n.tr("guest.name")).font(.title2.bold())
                    if let member = app.member { Text(member.username).foregroundStyle(.secondary); Text(member.email).font(.subheadline) }
                    else { Text(L10n.tr("guest.profile")).foregroundStyle(.secondary) }
                } }
                if app.isGuest { Button(L10n.tr("auth.login")) { app.showGuestGate = true } }
                else if let plan = app.membership { Label(plan.title, systemImage: "creditcard") }
            }
            Section {
                NavigationLink { SettingsView() } label: { Label(L10n.tr("settings.title"), systemImage: "gearshape") }
                Button { if app.isGuest { app.showGuestGate = true } else { app.showInbox = true } } label: { Label(L10n.tr("notifications.title"), systemImage: "bell") }
                Button { if app.isGuest { app.showGuestGate = true } else { password = true } } label: { Label(L10n.tr("password.change"), systemImage: "key") }
            }
            Section {
                ConfiguredLink(title: L10n.tr("profile.support"), key: "SupportURL")
                ConfiguredLink(title: L10n.tr("profile.terms"), key: "TermsURL")
                ConfiguredLink(title: L10n.tr("profile.privacy"), key: "PrivacyURL")
            }
            if !app.isGuest {
                Section {
                    Button(L10n.tr("auth.signout")) { Task { await app.logout() } }.disabled(deleting || app.busy)
                    Button(L10n.tr("account.delete"), role: .destructive) { deleteConfirmation = true }.disabled(deleting || app.busy)
                    if deleting { ProgressView() }
                    if let error { FailureView(message: error) }
                }
            }
            Section { Text(L10n.tr(app.isDemo ? "demo.notice" : "profile.footer")).font(.caption).foregroundStyle(.secondary) }
        }.scrollContentBackground(.hidden).brandBackground().listSectionSpacing(20).navigationTitle(L10n.tr("tab.profile")).mainToolbar()
            .sheet(isPresented: $password) { PasswordActionView(mode: .change).environment(app).privacyShield() }
            .confirmationDialog(L10n.tr("account.delete.title"), isPresented: $deleteConfirmation, titleVisibility: .visible) {
                Button(L10n.tr("account.delete"), role: .destructive) { Task { await delete() } }
                Button(L10n.tr("common.cancel"), role: .cancel) { }
            } message: { Text(L10n.tr("account.delete.body")) }
    }
    private func delete() async {
        guard !deleting, app.phase == .authenticated else { return }; deleting = true; defer { deleting = false }
        do {
            if app.preferences.biometrics { try await app.biometrics.authenticate(reason: L10n.tr("account.delete.title")) }
            try await app.service.deleteAccount()
            await app.logout()
        } catch { self.error = FriendlyError.message(error); app.handle(error) }
    }
}
struct ConfiguredLink: View {
    let title: String
    let key: String
    @State private var unavailable = false
    var body: some View {
        Group {
            if let url = Configuration.httpsURL(key) { Link(destination: url) { Label(title, systemImage: "arrow.up.right") }.frame(minHeight: 44) }
            else { Button(title) { unavailable = true }.frame(minHeight: 44) }
        }.alert(L10n.tr("link.unavailable"), isPresented: $unavailable) { Button(L10n.tr("common.ok"), role: .cancel) { } } message: { Text(L10n.tr("link.unavailable.body")) }
    }
}
