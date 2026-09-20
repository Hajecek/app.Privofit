import Foundation
import LocalAuthentication
import UserNotifications
import UIKit
import Observation

@MainActor protocol BiometricAuthenticating {
    func authenticate(reason: String) async throws
    var available: Bool { get }
    var name: String { get }
}
@MainActor struct BiometricService: BiometricAuthenticating {
    var name: String {
        let context = LAContext(); var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return L10n.tr("biometry.unavailable") }
        return context.biometryType == .faceID ? "Face ID" : "Touch ID"
    }
    var available: Bool { var error: NSError?; return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) }
    func authenticate(reason: String) async throws {
        let context = LAContext(); context.localizedCancelTitle = L10n.tr("common.cancel")
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { throw AppFailure.biometricsUnavailable }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            guard success else { throw AppFailure.cancelled }
        } catch let error as LAError {
            if [.userCancel, .systemCancel, .appCancel].contains(error.code) { throw AppFailure.cancelled }
            throw AppFailure.biometricsUnavailable
        }
    }
}
@MainActor @Observable final class NotificationService {
    var status: UNAuthorizationStatus = .notDetermined
    var deviceToken: String?
    var registrationError: String?
    func refresh() async { status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    func request() async throws {
        let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        await refresh()
        if allowed { UIApplication.shared.registerForRemoteNotifications() }
    }
    func registerIfAllowed() async {
        await refresh()
        if status == .authorized || status == .provisional { UIApplication.shared.registerForRemoteNotifications() }
    }
}
extension Notification.Name {
    static let privofitPushToken = Notification.Name("privofit.push.token")
    static let privofitPushFailure = Notification.Name("privofit.push.failure")
    static let privofitShowInbox = Notification.Name("privofit.show.inbox")
}
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BrandChrome.applyTransparentNavigationBar()
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .privofitPushToken, object: token)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .privofitPushFailure, object: nil)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Ignore arbitrary payload URLs/actions. A notification can only open the inbox.
        NotificationCenter.default.post(name: .privofitShowInbox, object: nil)
        completionHandler()
    }
}
