import SwiftUI

@main struct PrivofitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel
    init() { _model = State(initialValue: AppFactory.make()) }
    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
                .preferredColorScheme(model.preferences.appearance == .system ? nil : model.preferences.appearance == .dark ? .dark : .light)
                .tint(Color("AccentColor"))
        }
    }
}
@MainActor enum AppFactory {
    static func make() -> AppModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo")
            || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || Configuration.apiURL == nil {
            let args = ProcessInfo.processInfo.arguments
            let service = MockGymService()
            service.accessAllowed = !args.contains("--deny-door")
            service.doorOutcome = args.contains("--accepted-door") ? .accepted : .confirmedOpen
            let defaults = UserDefaults(suiteName: "cz.privofit.demo")!
            if args.contains("--reset") { defaults.removePersistentDomain(forName: "cz.privofit.demo") }
            let preferences = Preferences(defaults: defaults)
            let biometricProvider: any BiometricAuthenticating
            if args.contains("--no-biometry") { biometricProvider = UnavailableBiometrics() }
            else { biometricProvider = BiometricService() }
            let app = AppModel(service: service, preferences: preferences,
                               biometrics: biometricProvider,
                               vault: KeychainVault(service: "cz.privofit.demo"))
            return app
        }
        #endif
        let vault = KeychainVault()
        return AppModel(service: LiveGymService(baseURL: Configuration.apiURL, vault: vault), vault: vault)
    }
}
#if DEBUG
@MainActor struct UnavailableBiometrics: BiometricAuthenticating {
    var available: Bool { false }
    var name: String { L10n.tr("biometry.unavailable") }
    func authenticate(reason: String) async throws { throw AppFailure.biometricsUnavailable }
}
#endif
