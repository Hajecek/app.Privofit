import AuthenticationServices
import UIKit

// The app opens the website Google login. The server exchanges the code with the
// web client secret and returns a one-time ticket on the privofit:// scheme.
@MainActor final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let scheme = "privofit"
    private var session: ASWebAuthenticationSession?
    private var window: UIWindow?
    func signIn() async throws -> GoogleCredential {
        guard session == nil, let start = Self.startURL() else { throw AppFailure.notConfigured("Google") }
        window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.windows.first(where: \.isKeyWindow)
        guard window != nil else { throw AppFailure.unavailable }
        defer { session = nil; window = nil }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let flow = ASWebAuthenticationSession(url: start, callbackURLScheme: scheme) { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AppFailure.cancelled)
                } else {
                    continuation.resume(throwing: error == nil ? AppFailure.invalidResponse : AppFailure.unavailable)
                }
            }
            flow.prefersEphemeralWebBrowserSession = true
            flow.presentationContextProvider = self
            session = flow
            if !flow.start() { session = nil; continuation.resume(throwing: AppFailure.unavailable) }
        }
        guard callback.scheme == scheme,
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else { throw AppFailure.invalidResponse }
        if let message = items.first(where: { $0.name == "error" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            throw AppFailure.rejected(String(message.prefix(180)))
        }
        guard let ticket = items.first(where: { $0.name == "ticket" })?.value, !ticket.isEmpty else { throw AppFailure.invalidResponse }
        return .init(ticket: ticket)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window ?? ASPresentationAnchor() }
    static func startURL() -> URL? {
        guard let api = Configuration.apiURL else { return nil }
        guard var components = URLComponents(url: api, resolvingAgainstBaseURL: false) else { return nil }
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        let suffix = "/api/v1"
        if path.hasSuffix(suffix) { path.removeLast(suffix.count) }
        components.path = path + "/prihlaseni/google"
        components.query = nil
        components.fragment = nil
        components.queryItems = [URLQueryItem(name: "mobile", value: "1")]
        return components.url
    }
}
