import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        @Bindable var app = app
        ZStack {
            Group {
                switch app.phase {
                case .launching: LaunchView()
                case .signedOut: AuthenticationView()
                case .onboarding: OnboardingView()
                case .authenticated, .guest, .sessionExpired: MainTabs()
                case .restricted: recovery(title: "account.restricted", message: "account.restricted.body")
                }
            }
            .disabled(app.locked).accessibilityHidden(app.locked)
            if app.locked { lockScreen }
            if scenePhase != .active { BrandMark().frame(maxWidth: .infinity, maxHeight: .infinity).brandBackground().accessibilityHidden(true) }
        }
        .brandBackground()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: app.phase)
        .task { await app.boot() }
        .task(id: app.phase) {
            if app.phase == .authenticated, let token = app.notifications.fcmToken { await app.uploadPushToken(token, kind: "fcm") }
        }
        .task(id: app.phase) {
            guard !app.isDemo else { return }
            switch app.phase {
            case .authenticated, .restricted, .guest:
                break
            default:
                return
            }
            await app.tickLive(force: true)
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { break }
                ticks += 1
                await app.tickLive(force: ticks % 15 == 0)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { app.backgrounded() }
            if phase == .active { Task { await app.tickLive(force: true) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .privofitPushToken)) { notification in
            if let token = notification.object as? String {
                let kind = notification.userInfo?["kind"] as? String
                Task { await app.uploadPushToken(token, kind: kind) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .privofitPushFailure)) { _ in app.notifications.registrationError = L10n.tr("notifications.registration.failed") }
        .onReceive(NotificationCenter.default.publisher(for: .privofitPushReceived)) { notification in
            let type = (notification.userInfo?["type"] as? String) ?? ""
            Task {
                if type == "live.sync" {
                    await app.tickLive(force: true)
                } else {
                    await app.syncAccount()
                    await app.tickLive(force: true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .privofitShowInbox)) { _ in
            if app.phase == .authenticated { app.showInbox = true }
        }
        .sheet(isPresented: $app.showGuestGate) { GuestGate().presentationDetents([.medium, .large]) }
    }
    private var lockScreen: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield").font(.largeTitle)
            Text(L10n.tr("lock.title")).font(.title.bold())
            PrimaryButton(title: L10n.tr("lock.unlock"), symbol: "faceid") { Task { await app.unlock() } }
            if let error = app.error { FailureView(message: error) }
            Button(L10n.tr("auth.signout")) { Task { await app.logout() } }.frame(minHeight: 44)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).brandBackground()
    }
    private func recovery(title: String, message: String) -> some View {
        VStack(spacing: 24) {
            BrandMark(); Text(L10n.tr(title)).font(.largeTitle.bold()); Text(L10n.tr(message))
            PrimaryButton(title: L10n.tr("auth.login")) { Task { await app.logout() } }
        }.padding(28)
    }
}
struct MainTabs: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            Tab(L10n.tr("tab.dashboard"), systemImage: "square.grid.2x2", value: AppTab.dashboard) { NavigationStack { DashboardView() } }
            Tab(L10n.tr("tab.reservations"), systemImage: "calendar", value: AppTab.reservations) { NavigationStack { ReservationsView() } }
            Tab(L10n.tr("tab.door"), systemImage: "door.left.hand.open", value: AppTab.door) {
                Color.clear.brandBackground()
            }
            Tab(L10n.tr("tab.membership"), systemImage: "creditcard", value: AppTab.membership) { NavigationStack { MembershipView() } }
            Tab(L10n.tr("tab.profile"), systemImage: "person.crop.circle", value: AppTab.profile) { NavigationStack { ProfileView() } }
        }
        .clearTopChrome()
        .onChange(of: app.tab) { previous, tab in
            guard tab == .door else { return }
            let restore = previous == .door ? AppTab.dashboard : previous
            Task { @MainActor in
                app.tab = restore
                app.requestDoor()
            }
        }
        .fullScreenCover(isPresented: $app.showDoor, onDismiss: {
            if app.tab == .door { app.tab = .dashboard }
        }) {
            DoorView(model: DoorModel(app: app)).environment(app)
                .overlay { if app.locked || app.phase != .authenticated { Brand.night.ignoresSafeArea().overlay { ProgressView() } } }
                .onChange(of: app.locked) { _, locked in if locked { app.showDoor = false } }
                .onChange(of: app.phase) { _, phase in if phase != .authenticated { app.showDoor = false } }
        }
        .sheet(isPresented: $app.showInbox) { NavigationStack { NotificationsView() }.environment(app).privacyShield() }
        .sheet(isPresented: $app.showFloor) {
            NavigationStack { LiveFloorDetail() }
                .environment(app)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}
struct GuestGate: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            Label(L10n.tr("guest.gate.title"), systemImage: "lock.shield").font(.title2.bold())
            Text(L10n.tr("guest.gate.body")).foregroundStyle(.secondary)
            PrimaryButton(title: L10n.tr("auth.login")) { app.registrationRequested = false; dismiss(); app.requireLogin() }
            Button(L10n.tr("auth.create")) { app.registrationRequested = true; dismiss(); app.requireLogin() }.frame(minHeight: 44)
            Button(L10n.tr("common.notNow"), role: .cancel) { dismiss() }.frame(minHeight: 44)
        }.padding(28) }.brandBackground()
    }
}
