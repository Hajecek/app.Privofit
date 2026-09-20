import Foundation
import SwiftUI

/// Typ push oznámení, který jde v nastavení zapnout / vypnout.
enum NotificationChannel: String, CaseIterable, Identifiable, Sendable {
    case reservations
    case door
    case membership
    case gym

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reservations: return L10n.tr("notifications.channel.reservations")
        case .door: return L10n.tr("notifications.channel.door")
        case .membership: return L10n.tr("notifications.channel.membership")
        case .gym: return L10n.tr("notifications.channel.gym")
        }
    }

    var subtitle: String {
        switch self {
        case .reservations: return L10n.tr("notifications.channel.reservations.body")
        case .door: return L10n.tr("notifications.channel.door.body")
        case .membership: return L10n.tr("notifications.channel.membership.body")
        case .gym: return L10n.tr("notifications.channel.gym.body")
        }
    }

    var apiKey: String { rawValue }
    var fcmTopic: String { "pf_\(apiKey)" }

    static func resolve(userInfo: [AnyHashable: Any]) -> NotificationChannel {
        let key = payloadString(userInfo, keys: ["key", "notification_key", "type", "notification_type", "category", "kind", "channel"])
        let title = alertTitle(from: userInfo)
        let body = alertBody(from: userInfo)
        let haystack = [key, title, body]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased()

        if haystack.contains("reserv") || haystack.contains("rezerv") || haystack.contains("trening") || haystack.contains("workout") {
            return .reservations
        }
        if haystack.contains("door") || haystack.contains("vstup") || haystack.contains("entry") || haystack.contains("access") {
            return .door
        }
        if haystack.contains("member") || haystack.contains("clenst") || haystack.contains("pass") {
            return .membership
        }
        return .gym
    }

    private static func payloadString(_ userInfo: [AnyHashable: Any], keys: [String]) -> String {
        for key in keys {
            if let value = userInfo[key] as? String, !value.isEmpty { return value }
            if let value = userInfo[key] as? NSNumber { return value.stringValue }
        }
        return ""
    }

    private static func alertTitle(from userInfo: [AnyHashable: Any]) -> String {
        let title = payloadString(userInfo, keys: ["title", "notification_title"])
        if !title.isEmpty { return title }
        guard let aps = userInfo["aps"] as? [AnyHashable: Any] else { return "" }
        if let alert = aps["alert"] as? [AnyHashable: Any] {
            return (alert["title"] as? String) ?? ""
        }
        return ""
    }

    private static func alertBody(from userInfo: [AnyHashable: Any]) -> String {
        let body = payloadString(userInfo, keys: ["body", "message", "notification_body"])
        if !body.isEmpty { return body }
        guard let aps = userInfo["aps"] as? [AnyHashable: Any] else { return "" }
        if let alert = aps["alert"] as? String { return alert }
        if let alert = aps["alert"] as? [AnyHashable: Any] {
            return (alert["body"] as? String) ?? ""
        }
        return ""
    }
}

@MainActor
final class NotificationPreferencesStore: ObservableObject {
    static let shared = NotificationPreferencesStore()

    private enum Keys {
        static let master = "settings.notifications.master"
        static func channel(_ id: String) -> String { "settings.notifications.channel.\(id)" }
    }

    private let defaults: UserDefaults

    @Published var masterEnabled: Bool {
        didSet {
            defaults.set(masterEnabled, forKey: Keys.master)
            defaults.set(masterEnabled, forKey: "Privofit.notificationsEnabled")
        }
    }

    private var channelEnabled: [NotificationChannel: Bool]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMaster = defaults.object(forKey: Keys.master) as? Bool
        let legacyEnabled = defaults.object(forKey: "Privofit.notificationsEnabled") as? Bool
        masterEnabled = storedMaster ?? legacyEnabled ?? true

        var map: [NotificationChannel: Bool] = [:]
        for channel in NotificationChannel.allCases {
            map[channel] = defaults.object(forKey: Keys.channel(channel.rawValue)) as? Bool ?? true
        }
        channelEnabled = map
    }

    func isEnabled(_ channel: NotificationChannel) -> Bool {
        channelEnabled[channel] ?? true
    }

    func setEnabled(_ channel: NotificationChannel, _ enabled: Bool) {
        objectWillChange.send()
        channelEnabled[channel] = enabled
        defaults.set(enabled, forKey: Keys.channel(channel.rawValue))
    }

    /// Má se push v popředí vůbec ukázat. Čte přímo UserDefaults, aby šlo volat i mimo main thread.
    nonisolated static func shouldPresent(userInfo: [AnyHashable: Any]) -> Bool {
        let defaults = UserDefaults.standard
        let master = defaults.object(forKey: Keys.master) as? Bool
            ?? defaults.object(forKey: "Privofit.notificationsEnabled") as? Bool
            ?? true
        guard master else { return false }
        let channel = NotificationChannel.resolve(userInfo: userInfo)
        return defaults.object(forKey: Keys.channel(channel.rawValue)) as? Bool ?? true
    }

    func apiPayload() -> PushNotificationPreferences {
        var channels: [String: Bool] = [:]
        for channel in NotificationChannel.allCases {
            channels[channel.apiKey] = isEnabled(channel)
        }
        return PushNotificationPreferences(enabled: masterEnabled, channels: channels)
    }

    func applyTopicSubscriptions(subscribe: (String) -> Void, unsubscribe: (String) -> Void) {
        for channel in NotificationChannel.allCases {
            let want = masterEnabled && isEnabled(channel)
            if want { subscribe(channel.fcmTopic) } else { unsubscribe(channel.fcmTopic) }
        }
        if masterEnabled && isEnabled(.gym) {
            subscribe("all_users")
        } else {
            unsubscribe("all_users")
        }
    }
}
