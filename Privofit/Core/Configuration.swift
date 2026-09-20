import Foundation

enum DemoAccount {
    static let identifier = "alex"
    static let password = "demo-password"
}
enum Configuration {
    static func value(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.contains("$("), !value.contains("DOPLNIT") else { return nil }
        return value
    }
    static func httpsURL(_ key: String) -> URL? {
        guard let raw = value(key), let url = URL(string: raw), url.scheme == "https",
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    static var apiURL: URL? { httpsURL("APIBaseURL") }
    static var googleClientID: String? { value("GoogleClientID") }
    static var googleRedirect: String? { value("GoogleRedirectURI") }
    static var applePayMerchantID: String? { value("ApplePayMerchantID") }
}
enum InputValidator {
    static func identifier(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    static func email(_ value: String) -> Bool { value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil }
    // Login must not reject valid legacy passwords by inventing a backend length policy.
    static func login(_ identifier: String, _ password: String) -> Bool { self.identifier(identifier) && !password.isEmpty }
    static func registration(_ input: RegistrationInput) -> Bool {
        identifier(input.firstName) && identifier(input.username) && email(input.email) && !input.password.isEmpty
    }
}
enum L10n {
    static func tr(_ key: String) -> String { String(localized: String.LocalizationValue(key)) }
}
enum FriendlyError {
    static func message(_ error: Error) -> String {
        guard let error = error as? AppFailure else { return L10n.tr("error.generic") }
        switch error {
        case .notConfigured: return L10n.tr("error.configuration")
        case .unauthorized: return L10n.tr("error.session")
        case .forbidden: return L10n.tr("error.denied")
        case .offline: return L10n.tr("error.offline")
        case .biometricsUnavailable: return L10n.tr("error.biometry")
        case .cancelled: return L10n.tr("error.cancelled")
        default: return L10n.tr("error.generic")
        }
    }
}
