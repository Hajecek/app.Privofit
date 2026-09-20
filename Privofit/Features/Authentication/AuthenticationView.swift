import SwiftUI

struct AuthenticationView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var identifier = ""
    @State private var password = ""
    @State private var touched = false
    @State private var registration = false
    @State private var reset = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.tr("redesign.authWelcome")).font(.largeTitle.weight(.bold)).tracking(-1)
                            Text(L10n.tr("redesign.authSubtitle")).font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if !typeSize.isAccessibilitySize { AccessToken().scaleEffect(0.83).frame(width: 120, height: 150) }
                    }.padding(.top, 14)
                    if app.isDemo {
                        StatusBadge(title: L10n.tr("demo.badge"), symbol: "hammer")
                        Text(L10n.tr("demo.credentials")).font(.footnote).foregroundStyle(.secondary)
                    }
                    ProviderButtons()
                    HStack(spacing: 14) {
                        Rectangle().fill(.secondary.opacity(0.18)).frame(height: 1)
                        Text(L10n.tr("redesign.orAccount")).font(.caption).foregroundStyle(.secondary).fixedSize()
                        Rectangle().fill(.secondary.opacity(0.18)).frame(height: 1)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        FieldLabel(title: L10n.tr("auth.identifier")) {
                            HStack(spacing: 12) {
                                Image(systemName: "person").foregroundStyle(.secondary)
                                TextField(L10n.tr("redesign.identifierExample"), text: $identifier).textContentType(.username)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityIdentifier("login.identifier")
                                    .onChange(of: identifier) { _, _ in touched = true }
                            }.brandField()
                        }
                        FieldLabel(title: L10n.tr("auth.password")) {
                            PasswordField(title: L10n.tr("redesign.passwordPlaceholder"), text: $password).accessibilityIdentifier("login.password")
                        }
                        if touched && !InputValidator.identifier(identifier) { Text(L10n.tr("validation.identifier")).font(.caption).foregroundStyle(Brand.danger) }
                        HStack { Spacer(); Button(L10n.tr("auth.forgot")) { reset = true }.font(.subheadline.weight(.medium)).frame(minHeight: 44) }.padding(.top, -12)
                        if let error = app.error { FailureView(message: error) }
                        PrimaryButton(title: L10n.tr("auth.login"), symbol: "arrow.right", busy: app.busy) {
                            touched = true
                            Task { await app.login(identifier: identifier, password: password) }
                        }.disabled(!InputValidator.login(identifier, password)).accessibilityIdentifier("login.submit")
                        if app.isDemo {
                            Button(L10n.tr("demo.quickLogin")) {
                                identifier = DemoAccount.identifier
                                password = DemoAccount.password
                                Task { await app.login(identifier: DemoAccount.identifier, password: DemoAccount.password) }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("login.demo")
                        }
                    }
                    VStack(spacing: 4) {
                        Text(L10n.tr("redesign.newHere")).font(.subheadline).foregroundStyle(.secondary)
                        Button(L10n.tr("auth.create")) { registration = true }.font(.headline).frame(minHeight: 44)
                    }.frame(maxWidth: .infinity).padding(.bottom, 16)
                }.padding(.horizontal, 24).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }.brandBackground().scrollDismissesKeyboard(.interactively)
                .navigationBarTitleDisplayMode(.inline)
                .clearTopChrome()
                .toolbar {
                    ToolbarItem(placement: .principal) { BrandMark(size: 26) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.tr("redesign.explore")) { app.enterGuest() }
                            .accessibilityLabel(L10n.tr("auth.guest")).accessibilityIdentifier("auth.guest")
                    }
                }
                .disabled(app.busy)
                .sheet(isPresented: $registration) { RegistrationView().environment(app).privacyShield() }
                .sheet(isPresented: $reset) { PasswordActionView(mode: .reset).environment(app).privacyShield() }
                .onAppear {
                    if app.isDemo {
                        if identifier.isEmpty { identifier = DemoAccount.identifier }
                        if password.isEmpty { password = DemoAccount.password }
                    }
                    if app.registrationRequested { registration = true; app.registrationRequested = false }
                }
        }
    }
}
struct ProviderButtons: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Button { Task { await app.appleLogin() } } label: {
                Label("Apple", systemImage: "apple.logo").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }.accessibilityLabel(L10n.tr("auth.apple"))
            Button { Task { await app.googleLogin() } } label: {
                HStack(spacing: 8) { Text("G").font(.title3.weight(.bold)); Text("Google").font(.headline) }.frame(maxWidth: .infinity, minHeight: 52)
            }.accessibilityLabel(L10n.tr("auth.google"))
        }.buttonStyle(.bordered).tint(.primary).disabled(app.busy)
    }
}
struct PasswordField: View {
    let title: String
    @Binding var text: String
    var isNew = false
    @State private var reveal = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock").foregroundStyle(.secondary)
            Group {
                if reveal { TextField(title, text: $text) }
                else { SecureField(title, text: $text) }
            }.textContentType(isNew ? .newPassword : .password).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye").frame(width: 44, height: 44).foregroundStyle(.secondary) }
                .accessibilityLabel(L10n.tr(reveal ? "auth.hidePassword" : "auth.showPassword"))
        }.padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 5)
            .background(Color("Surface"), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.12)))
    }
}
struct RegistrationView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var name = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var emailTouched = false
    private var input: RegistrationInput { .init(firstName: name, username: username, email: email, password: password) }
    private var valid: Bool {
        if step == 0 { return InputValidator.identifier(name) && InputValidator.username(username) }
        if step == 1 { return InputValidator.email(email) }
        return InputValidator.registration(input) && password == confirmation
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 8) {
                        ForEach(0..<3) { index in Capsule().fill(index <= step ? Color("AccentColor") : Color.primary.opacity(0.09)).frame(height: 4) }
                    }.accessibilityLabel(L10n.tr("redesign.registration.\(step).title")).padding(.top, 20)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("redesign.registration.\(step).title")).font(.largeTitle.weight(.bold)).tracking(-1)
                        Text(L10n.tr("redesign.registration.\(step).body")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if step == 0 {
                        MemberPass(name: name.isEmpty ? L10n.tr("pass.yourName") : name).padding(.vertical, 6)
                        ProviderButtons()
                        FieldLabel(title: L10n.tr("profile.name")) { TextField(L10n.tr("profile.name"), text: $name).textContentType(.givenName).brandField() }
                        FieldLabel(title: L10n.tr("profile.username")) {
                            TextField(L10n.tr("profile.username"), text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().brandField()
                                .onChange(of: username) { _, value in
                                    username = value.lowercased().replacingOccurrences(of: " ", with: "")
                                }
                        }
                        if !username.isEmpty && !InputValidator.username(username) {
                            Text(L10n.tr("validation.username")).font(.caption).foregroundStyle(Brand.danger)
                        }
                    } else if step == 1 {
                        Image(systemName: "envelope").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(Color("AccentColor")).frame(maxWidth: .infinity, minHeight: 140).accessibilityHidden(true)
                        FieldLabel(title: L10n.tr("profile.email")) {
                            TextField(L10n.tr("redesign.emailExample"), text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().brandField()
                                .onChange(of: email) { _, _ in emailTouched = true }
                        }
                        if emailTouched && !InputValidator.email(email) { Text(L10n.tr("validation.email")).font(.caption).foregroundStyle(Brand.danger) }
                    } else {
                        AccessToken().frame(maxWidth: .infinity)
                        FieldLabel(title: L10n.tr("auth.password")) { PasswordField(title: L10n.tr("auth.password"), text: $password, isNew: true) }
                        FieldLabel(title: L10n.tr("auth.confirmPassword")) { PasswordField(title: L10n.tr("auth.confirmPassword"), text: $confirmation, isNew: true) }
                        if !password.isEmpty && !InputValidator.password(password) {
                            Text(L10n.tr("validation.passwordLength")).font(.caption).foregroundStyle(Brand.danger)
                        } else if !confirmation.isEmpty && password != confirmation {
                            Text(L10n.tr("validation.passwordMatch")).font(.caption).foregroundStyle(Brand.danger)
                        }
                        Text(L10n.tr("registration.passwordPolicy")).font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = app.error { FailureView(message: error) }
                    PrimaryButton(title: L10n.tr(step == 2 ? "auth.create" : "common.continue"), symbol: "arrow.right", busy: app.busy) {
                        if step < 2 { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { step += 1 } }
                        else { Task { await app.register(input); if app.member != nil { dismiss() } } }
                    }.disabled(!valid).accessibilityIdentifier("registration.next")
                }.padding(.horizontal, 24).padding(.bottom, 32).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }.brandBackground().scrollDismissesKeyboard(.interactively)
                .navigationTitle(L10n.tr("auth.create")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if step > 0 { Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { step -= 1 } } label: { Image(systemName: "chevron.left") }.accessibilityLabel(L10n.tr("common.back")) }
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(L10n.tr("common.close")) }
                }.disabled(app.busy)
        }.interactiveDismissDisabled(app.busy)
    }
}
enum PasswordAction { case reset, change }
struct PasswordActionView: View {
    let mode: PasswordAction
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var identifier = ""
    @State private var current = ""
    @State private var new = ""
    @State private var busy = false
    @State private var result: String?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if app.isDemo { Text(L10n.tr("demo.notice")).font(.caption) }
                if mode == .reset { TextField(L10n.tr("auth.identifier"), text: $identifier).textContentType(.username).textInputAutocapitalization(.never) }
                else { PasswordField(title: L10n.tr("password.current"), text: $current); PasswordField(title: L10n.tr("password.new"), text: $new, isNew: true) }
                if let result { Text(result) }
                if let error { FailureView(message: error) }
                Button(L10n.tr("common.submit")) { Task { await submit() } }.disabled(busy || (mode == .reset ? !InputValidator.identifier(identifier) : current.isEmpty || new.isEmpty))
                if busy { ProgressView() }
            }.scrollContentBackground(.hidden).brandBackground()
                .navigationTitle(L10n.tr(mode == .reset ? "auth.forgot" : "password.change"))
                .toolbar { Button(L10n.tr("common.close")) { dismiss() } }
        }
    }
    private func submit() async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do {
            if mode == .reset { try await app.service.requestPasswordReset(identifier: identifier); result = L10n.tr("password.resetSent") }
            else { try await app.service.changePassword(current: current, new: new); result = L10n.tr("password.changed"); current = ""; new = "" }
        } catch { self.error = FriendlyError.message(error); if mode == .change { app.handle(error) } }
    }
}
