import UIKit
import UserNotifications

enum AppIconBadgeSync {
    static func increment() {
        Task { @MainActor in
            let current = UIApplication.shared.applicationIconBadgeNumber
            try? await UNUserNotificationCenter.current().setBadgeCount(max(0, current + 1))
        }
    }

    static func clear() {
        Task { @MainActor in
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }
}
