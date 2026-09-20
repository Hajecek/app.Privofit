import Foundation
import LocalAuthentication
import UserNotifications
import UIKit
import Observation
import FirebaseCore
import FirebaseMessaging

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
    var apnsToken: String?
    var fcmToken: String?
    var registrationError: String?
    func refresh() async { status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    func request() async throws {
        let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        await refresh()
        if allowed {
            NotificationPreferencesStore.shared.masterEnabled = true
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    func registerIfAllowed() async {
        await refresh()
        if status == .authorized || status == .provisional { UIApplication.shared.registerForRemoteNotifications() }
    }
    var deliveryToken: String? { fcmToken ?? deviceToken }
}
extension Notification.Name {
    static let privofitPushToken = Notification.Name("privofit.push.token")
    static let privofitPushFailure = Notification.Name("privofit.push.failure")
    static let privofitPushReceived = Notification.Name("privofit.push.received")
    static let privofitShowInbox = Notification.Name("privofit.show.inbox")
}
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    static weak var shared: AppDelegate?
    private var firebaseReady = false
    private var authenticated = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Self.shared = self
        firebaseReady = configureFirebaseIfPossible()
        if firebaseReady {
            Messaging.messaging().delegate = self
            print("[FCM] Firebase připraven")
        } else {
            print("[FCM] Chybí GoogleService-Info.plist – FCM token až po přidání Firebase projektu Privofit")
        }
        UNUserNotificationCenter.current().delegate = self
        BrandChrome.applyTransparentNavigationBar()

        // Svolení k notifikacím se vyžaduje v onboardingu, ne hned při startu.
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async {
                if status == .authorized || status == .provisional {
                    UserDefaults.standard.set(true, forKey: "Privofit.notificationsEnabled")
                    application.registerForRemoteNotifications()
                    print("[FCM] Notifikace již povoleny, registruji na APNS…")
                }
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[FCM] APNS token přijat (\(deviceToken.count) B)")
        NotificationCenter.default.post(name: .privofitPushToken, object: token, userInfo: ["kind": "apns"])

        guard firebaseReady else { return }
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { token, error in
            DispatchQueue.main.async {
                if let error {
                    print("[FCM] Chyba při načtení tokenu: \(error.localizedDescription)")
                    return
                }
                if let token {
                    print("[FCM] ✅ FCM token přijat")
                    NotificationCenter.default.post(name: .privofitPushToken, object: token, userInfo: ["kind": "fcm"])
                }
                AppDelegate.shared?.syncNotificationTopics()
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[FCM] ⚠️ APNS registrace selhala (pravděpodobně simulátor): \(error.localizedDescription)")
        NotificationCenter.default.post(name: .privofitPushFailure, object: nil)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        guard NotificationPreferencesStore.shouldPresent(userInfo: userInfo) else {
            completionHandler([])
            return
        }
        AppIconBadgeSync.increment()
        NotificationCenter.default.post(name: .privofitPushReceived, object: nil, userInfo: userInfo as? [String: Any])
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        NotificationCenter.default.post(name: .privofitPushReceived, object: nil, userInfo: userInfo as? [String: Any])
        NotificationCenter.default.post(name: .privofitShowInbox, object: nil)
        completionHandler()
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let allowed = NotificationPreferencesStore.shouldPresent(userInfo: userInfo)
        if allowed {
            NotificationCenter.default.post(
                name: .privofitPushReceived,
                object: nil,
                userInfo: userInfo as? [String: Any]
            )
            if application.applicationState != .active {
                AppIconBadgeSync.increment()
            }
        }
        completionHandler(.newData)
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // Na backend neposíláme tady – ukládáme až po přihlášení.
        guard let fcmToken else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .privofitPushToken, object: fcmToken, userInfo: ["kind": "fcm"])
        }
    }

    func updateAuthentication(isLoggedIn: Bool) {
        authenticated = isLoggedIn
        if isLoggedIn {
            syncNotificationTopics()
            if let token = currentDeliveryToken() {
                NotificationCenter.default.post(name: .privofitPushToken, object: token, userInfo: ["kind": firebaseReady ? "fcm" : "apns"])
            }
        } else {
            authenticated = false
            AppIconBadgeSync.clear()
        }
    }

    func syncNotificationPreferences() {
        syncNotificationTopics()
        if authenticated, let token = currentDeliveryToken() {
            NotificationCenter.default.post(name: .privofitPushToken, object: token, userInfo: ["kind": firebaseReady ? "fcm" : "apns"])
        }
    }

    private func currentDeliveryToken() -> String? {
        if firebaseReady, let token = Messaging.messaging().fcmToken, !token.isEmpty { return token }
        return nil
    }

    private func syncNotificationTopics() {
        guard firebaseReady else { return }
        Task { @MainActor in
            NotificationPreferencesStore.shared.applyTopicSubscriptions(
                subscribe: { Messaging.messaging().subscribe(toTopic: $0) { _ in } },
                unsubscribe: { Messaging.messaging().unsubscribe(fromTopic: $0) { _ in } }
            )
        }
    }

    private func configureFirebaseIfPossible() -> Bool {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let appID = plist["GOOGLE_APP_ID"] as? String, !appID.isEmpty,
              appID.contains(":ios:") else { return false }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return FirebaseApp.app() != nil
    }
}
