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
        guard let raw = value(key), let url = URL(string: raw), url.host != nil,
              url.user == nil, url.password == nil, isAllowedAPIBase(url) else { return nil }
        return url
    }
    static var apiURL: URL? { httpsURL("APIBaseURL") }
    static func isAllowedAPIBase(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, let host = url.host else { return false }
        if url.scheme == "https" { return true }
        #if DEBUG
        return url.scheme == "http" && isLocalHost(host)
        #else
        return false
        #endif
    }
    static func isLocalHost(_ host: String) -> Bool {
        let value = host.lowercased()
        if value == "localhost" || value == "127.0.0.1" || value == "::1" { return true }
        if value.hasPrefix("192.168.") || value.hasPrefix("10.") { return true }
        let parts = value.split(separator: ".")
        if value.hasPrefix("172."), parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) { return true }
        return false
    }
    static var googleClientID: String? { value("GoogleClientID") }
    static var googleRedirect: String? { value("GoogleRedirectURI") }
    static var applePayMerchantID: String? { value("ApplePayMerchantID") }
}
enum InputValidator {
    static func identifier(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    static func email(_ value: String) -> Bool { value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil }
    static func username(_ value: String) -> Bool {
        value.range(of: #"^[a-z0-9._]{3,30}$"#, options: .regularExpression) != nil
    }
    static func password(_ value: String) -> Bool { value.count >= 12 }
    // Login must not reject valid legacy passwords by inventing a backend length policy.
    static func login(_ identifier: String, _ password: String) -> Bool { self.identifier(identifier) && !password.isEmpty }
    static func registration(_ input: RegistrationInput) -> Bool {
        identifier(input.firstName) && username(input.username.lowercased()) && email(input.email) && password(input.password)
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
        case .timeout: return L10n.tr("error.timeout")
        case .rejected(let message): return message
        case .sessionChanged: return L10n.tr("error.sessionChanged")
        case .invalidResponse: return L10n.tr("error.invalidResponse")
        case .unavailable: return L10n.tr("error.unavailable")
        case .http: return L10n.tr("error.generic")
        }
    }
}
