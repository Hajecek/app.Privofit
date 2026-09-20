import AuthenticationServices
import CryptoKit
import Security
import UIKit

// OAuth public-client flow: Google returns a code; ONLY our HTTPS API exchanges it
// and verifies the resulting identity (issuer, audience, nonce). No client secret in iOS.
@MainActor final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var window: UIWindow?
    func signIn() async throws -> GoogleCredential {
        guard session == nil, let clientID = Configuration.googleClientID,
              let redirect = Configuration.googleRedirect, let redirectURL = URL(string: redirect),
              let scheme = redirectURL.scheme, scheme != "http", scheme != "https" else { throw AppFailure.notConfigured("Google OAuth") }
        window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.windows.first(where: \.isKeyWindow)
        guard window != nil else { throw AppFailure.unavailable }
        let verifier = try random(); let state = try random(); let nonce = try random()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = ["client_id": clientID, "redirect_uri": redirect, "response_type": "code",
                          "scope": "openid email profile", "state": state, "nonce": nonce,
                          "code_challenge": challenge, "code_challenge_method": "S256"].map { URLQueryItem(name: $0.key, value: $0.value) }
        defer { session = nil; window = nil }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let flow = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: scheme) { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: error == nil ? AppFailure.invalidResponse : AppFailure.cancelled) }
            }
            flow.presentationContextProvider = self
            session = flow
            if !flow.start() { session = nil; continuation.resume(throwing: AppFailure.unavailable) }
        }
        guard callback.scheme == redirectURL.scheme, callback.host == redirectURL.host, callback.path == redirectURL.path,
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state,
              items.first(where: { $0.name == "error" }) == nil,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw AppFailure.invalidResponse }
        return .init(authorizationCode: code, codeVerifier: verifier, redirectURI: redirect, clientID: clientID, nonce: nonce)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window ?? ASPresentationAnchor() }
    private func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AppFailure.unavailable }
        return Data(bytes).base64URL
    }
}
private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
