import WidgetKit
import SwiftUI

enum L10n {
    static func tr(_ key: String) -> String { String(localized: String.LocalizationValue(key)) }
}

@main
struct PrivofitWidgetBundle: WidgetBundle {
    var body: some Widget {
        SessionWidget()
        StreakWidget()
        MembershipWidget()
        BookControl()
        SessionLiveActivity()
    }
}
