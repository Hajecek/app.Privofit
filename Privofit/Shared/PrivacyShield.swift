import SwiftUI

struct PrivacyShield: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content.overlay {
            if scenePhase != .active {
                Brand.night.ignoresSafeArea().overlay { BrandMark(size: 36) }.accessibilityHidden(true)
            }
        }
    }
}
extension View { func privacyShield() -> some View { modifier(PrivacyShield()) } }
