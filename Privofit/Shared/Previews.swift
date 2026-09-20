#if DEBUG
import SwiftUI

@MainActor struct PreviewHost<Content: View>: View {
    @State private var app: AppModel
    @State private var ready = false
    private let content: (AppModel) -> Content
    init(guest: Bool = false, inactive: Bool = false, @ViewBuilder content: @escaping (AppModel) -> Content) {
        let service = MockGymService(); service.inactiveMembership = inactive
        let defaults = UserDefaults(suiteName: "preview.\(UUID().uuidString)")!
        let model = AppModel(service: service, preferences: Preferences(defaults: defaults), biometrics: UnavailableBiometrics())
        _app = State(initialValue: model); self.content = content
        self.guest = guest
    }
    let guest: Bool
    var body: some View {
        Group { if ready { content(app) } else { LaunchView() } }.environment(app).preferredColorScheme(.dark)
            .task {
                if guest { app.enterGuest() }
                else { await app.login(identifier: "preview", password: "preview") }
                app.finishOnboarding(); await app.loadDashboard(); ready = true
            }
    }
}
@MainActor private func previewDoor(_ app: AppModel, _ state: DoorState) -> DoorView {
    let model = DoorModel(app: app); model.previewState(state); return DoorView(model: model)
}
#Preview("Login") { AuthenticationView().environment(AppModel(service: MockGymService())) }
#Preview("Registration") { RegistrationView().environment(AppModel(service: MockGymService())) }
#Preview("Lock animation") { DoorPortal(opened: true).frame(height: 400).background(Brand.lime) }
#Preview("Onboarding") { OnboardingView().environment(AppModel(service: MockGymService())) }
#Preview("Member dashboard") { PreviewHost { _ in NavigationStack { DashboardView() } } }
#Preview("Guest dashboard") { PreviewHost(guest: true) { _ in NavigationStack { DashboardView() } } }
#Preview("Active membership") { PreviewHost { _ in NavigationStack { MembershipView() } } }
#Preview("Inactive membership") { PreviewHost(inactive: true) { _ in NavigationStack { MembershipView() } } }
#Preview("Ready door") { PreviewHost { app in previewDoor(app, .idle) } }
#Preview("Sending door") { PreviewHost { app in previewDoor(app, .sending) } }
#Preview("Confirmed door") { PreviewHost { app in previewDoor(app, .confirmed) } }
#Preview("Denied door") { PreviewHost { app in previewDoor(app, .denied("")) } }
#Preview("API error") { PreviewHost { app in previewDoor(app, .failed("")) } }
#Preview("Empty reservations") { PreviewHost { _ in NavigationStack { ReservationsView() } } }
#endif
