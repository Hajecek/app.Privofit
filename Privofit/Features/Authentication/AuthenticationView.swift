import PhotosUI
import SwiftUI

struct AuthenticationView: View {
    @Environment(AppModel.self) private var app
    @State private var identifier = ""
    @State private var password = ""
    @State private var touched = false
    @State private var registration = false
    @State private var reset = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    BrandMark(size: 44)
                        .frame(maxWidth: 260)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                    if app.isDemo {
                        VStack(spacing: 8) {
                            StatusBadge(title: L10n.tr("demo.badge"), symbol: "hammer")
                            Text(L10n.tr("demo.credentials")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    ProviderButtons()
                    HStack(spacing: 14) {
                        Rectangle().fill(.secondary.opacity(0.18)).frame(height: 1)
                        Text(L10n.tr("auth.or")).font(.caption).foregroundStyle(.secondary)
                        Rectangle().fill(.secondary.opacity(0.18)).frame(height: 1)
                    }
                    VStack(spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "person").foregroundStyle(.secondary)
                            TextField(L10n.tr("auth.identifier"), text: $identifier)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("login.identifier")
                                .onChange(of: identifier) { _, _ in touched = true }
                        }.brandField()
                        PasswordField(title: L10n.tr("auth.password"), text: $password)
                            .accessibilityIdentifier("login.password")
                        if touched && !InputValidator.identifier(identifier) {
                            Text(L10n.tr("validation.identifier")).font(.caption).foregroundStyle(Brand.danger).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let error = app.error { FailureView(message: error) }
                        PrimaryButton(title: L10n.tr("auth.login"), symbol: "arrow.right", busy: app.busy) {
                            touched = true
                            Task { await app.login(identifier: identifier, password: password) }
                        }
                        .disabled(!InputValidator.login(identifier, password))
                        .accessibilityIdentifier("login.submit")
                        Button(L10n.tr("auth.forgot")) { reset = true }
                            .font(.subheadline.weight(.medium))
                            .frame(minHeight: 44)
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
                        Button(L10n.tr("auth.create")) { registration = true }
                            .font(.headline)
                            .frame(minHeight: 44)
                        Button(L10n.tr("auth.guest")) { app.enterGuest() }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("auth.guest")
                    }
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .brandBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
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
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 12) {
            Button { Task { await app.appleLogin() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                    Text(L10n.tr("auth.apple"))
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(scheme == .dark ? Brand.ink : Color.white)
                .background(scheme == .dark ? Color.white : Brand.ink, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("auth.apple"))
            Button { Task { await app.googleLogin() } } label: {
                HStack(spacing: 10) {
                    Text("G").font(.title3.weight(.bold))
                    Text(L10n.tr("auth.google")).font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Brand.text(scheme))
                .background(Brand.surface(scheme), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Brand.text(scheme).opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("auth.google"))
        }
        .disabled(app.busy)
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
    @State private var name = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var terms = false
    @State private var privacy = false
    @State private var touched = false
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarPreview: Image?
    @State private var avatarJPEG: Data?
    @State private var avatarNotice: String?
    private var input: RegistrationInput {
        .init(
            firstName: name,
            lastName: lastName,
            username: username,
            email: email,
            password: password,
            passwordConfirmation: confirmation,
            acceptedTerms: terms,
            acceptedPrivacy: privacy
        )
    }
    private var valid: Bool { InputValidator.registration(input) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("registration.headline")).font(.largeTitle.weight(.bold))
                        Text(L10n.tr("registration.subtitle")).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    ProviderButtons()
                    HStack(spacing: 14) {
                        Rectangle().fill(.secondary.opacity(0.18)).frame(height: 1)
                        Text(L10n.tr("registration.orEmail")).font(.caption).foregroundStyle(.secondary)
                        Rectangle().fill(.secondary.opacity(0.18)).frame(height: 1)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        FieldLabel(title: L10n.tr("profile.name")) {
                            TextField(L10n.tr("profile.name"), text: $name)
                                .textContentType(.givenName)
                                .brandField()
                                .onChange(of: name) { _, value in name = String(value.prefix(80)) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        FieldLabel(title: L10n.tr("registration.lastName")) {
                            TextField(L10n.tr("registration.lastName"), text: $lastName)
                                .textContentType(.familyName)
                                .brandField()
                                .onChange(of: lastName) { _, value in lastName = String(value.prefix(80)) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    FieldLabel(title: L10n.tr("profile.username")) {
                        TextField(L10n.tr("profile.username"), text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .brandField()
                            .onChange(of: username) { _, value in
                                let mapped = value.lowercased().replacingOccurrences(of: "-", with: "_")
                                let cleaned = String(mapped.filter { ($0 >= "a" && $0 <= "z") || $0.isNumber || $0 == "." || $0 == "_" }.prefix(30))
                                if cleaned != value { username = cleaned }
                            }
                    }
                    Text(L10n.tr("registration.usernameHint")).font(.caption).foregroundStyle(.secondary)
                    FieldLabel(title: L10n.tr("profile.email")) {
                        TextField(L10n.tr("profile.email"), text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .brandField()
                            .onChange(of: email) { _, value in email = String(value.prefix(190)) }
                    }
                    FieldLabel(title: L10n.tr("auth.password")) {
                        PasswordField(title: L10n.tr("auth.password"), text: $password, isNew: true)
                    }
                    Text(L10n.tr("registration.passwordHint")).font(.caption).foregroundStyle(.secondary)
                    FieldLabel(title: L10n.tr("auth.confirmPassword")) {
                        PasswordField(title: L10n.tr("auth.confirmPassword"), text: $confirmation, isNew: true)
                    }
                    avatarPicker
                    ConsentRow(isOn: $terms, title: L10n.tr("registration.terms"), linkTitle: L10n.tr("profile.terms"), urlKey: "TermsURL")
                    ConsentRow(isOn: $privacy, title: L10n.tr("registration.privacy"), linkTitle: L10n.tr("profile.privacy"), urlKey: "PrivacyURL")
                    if let message = validationMessage {
                        Text(message).font(.caption).foregroundStyle(Brand.danger)
                    }
                    Text(L10n.tr("registration.note")).font(.caption).foregroundStyle(.secondary)
                    if let avatarNotice { Text(avatarNotice).font(.caption).foregroundStyle(Brand.danger) }
                    if let error = app.error { FailureView(message: error) }
                    if app.member != nil, avatarNotice != nil {
                        PrimaryButton(title: L10n.tr("common.continue"), symbol: "arrow.right", busy: app.busy) { dismiss() }
                    } else {
                        PrimaryButton(title: L10n.tr("auth.create"), symbol: "arrow.right", busy: app.busy) {
                            touched = true
                            guard valid else { return }
                            Task {
                                let photoSaved = await app.register(input, avatar: avatarJPEG)
                                if app.member != nil {
                                    if photoSaved { dismiss() }
                                    else { avatarNotice = L10n.tr("registration.avatarFailed") }
                                }
                            }
                        }
                        .accessibilityIdentifier("registration.next")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .brandBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L10n.tr("auth.create"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) { dismiss() }
                }
            }
            .disabled(app.busy)
            .onAppear { app.error = nil }
            .onChange(of: photoItem) { _, item in
                Task { await loadAvatar(item) }
            }
        }
        .interactiveDismissDisabled(app.busy)
    }
    private var avatarPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Brand.lime).frame(width: 72, height: 72)
                    if let avatarPreview {
                        avatarPreview.resizable().scaledToFill().frame(width: 72, height: 72).clipShape(Circle())
                    } else {
                        Text(String((name.isEmpty ? "P" : name).prefix(1)).uppercased())
                            .font(.title3.bold())
                            .foregroundStyle(Brand.ink)
                    }
                }
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text(L10n.tr("registration.avatarAdd")).frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            Text(L10n.tr("registration.avatarHint")).font(.caption).foregroundStyle(.secondary)
            if avatarJPEG != nil {
                Button(L10n.tr("registration.avatarRemove")) {
                    photoItem = nil
                    avatarPreview = nil
                    avatarJPEG = nil
                    avatarNotice = nil
                }
                .font(.subheadline)
            }
        }
    }
    private var validationMessage: String? {
        guard touched else { return nil }
        if !InputValidator.personName(name) || !InputValidator.personName(lastName) { return L10n.tr("validation.name") }
        if !InputValidator.username(username) { return L10n.tr("validation.username") }
        if !InputValidator.email(email) { return L10n.tr("validation.email") }
        if !InputValidator.password(password) { return L10n.tr("validation.passwordLength") }
        if password != confirmation { return L10n.tr("validation.passwordMatch") }
        if !terms || !privacy { return L10n.tr("registration.consent") }
        return nil
    }
    private func loadAvatar(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = Self.jpegData(image),
              jpeg.count <= 5_242_880 else {
            avatarPreview = nil
            avatarJPEG = nil
            avatarNotice = L10n.tr("registration.avatarInvalid")
            return
        }
        avatarPreview = Image(uiImage: image)
        avatarJPEG = jpeg
        avatarNotice = nil
    }
    private static func jpegData(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.85)
    }
}
private struct ConsentRow: View {
    @Binding var isOn: Bool
    let title: String
    let linkTitle: String
    let urlKey: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { isOn.toggle() } label: {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isOn ? Brand.limeDeep : .secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isOn ? .isSelected : AccessibilityTraits())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = Configuration.httpsURL(urlKey) {
                    Link(linkTitle, destination: url).font(.subheadline.weight(.semibold))
                }
            }
            .padding(.top, 11)
        }
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
        } catch { self.error = FriendlyError.message(error); if mode == .change { app.handle(error, surface: false) } }
    }
}
