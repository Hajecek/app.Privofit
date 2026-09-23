import AuthenticationServices
import CryptoKit
import Security
import UIKit

@MainActor final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleCredential, Error>?
    private var nonce = ""
    private var state = ""
    private var controller: ASAuthorizationController?
    private var anchor: ASPresentationAnchor?
    func signIn() async throws -> AppleCredential {
        guard continuation == nil else { throw AppFailure.unavailable }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive }).flatMap(\.windows).first(where: \.isKeyWindow) else { throw AppFailure.unavailable }
        anchor = window; nonce = try randomToken(); state = try randomToken()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        request.state = state
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller; controller.delegate = self; controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchor ?? ASPresentationAnchor() }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              credential.state == state,
              let data = credential.identityToken, let token = String(data: data, encoding: .utf8),
              let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8) else { finish(.failure(AppFailure.invalidResponse)); return }
        // Backend must verify signature, issuer, audience, expiry and hashed nonce.
        let name = credential.fullName
        finish(.success(AppleCredential(
            identityToken: token,
            authorizationCode: code,
            rawNonce: nonce,
            givenName: name?.givenName,
            familyName: name?.familyName
        )))
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let failure = error as? ASAuthorizationError, failure.code == .canceled { finish(.failure(AppFailure.cancelled)) }
        else { finish(.failure(AppFailure.unavailable)) }
    }
    private func finish(_ result: Result<AppleCredential, Error>) {
        continuation?.resume(with: result); continuation = nil; controller = nil; anchor = nil; nonce = ""; state = ""
    }
    private func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AppFailure.unavailable }
        return Data(bytes).base64EncodedString()
    }
}
