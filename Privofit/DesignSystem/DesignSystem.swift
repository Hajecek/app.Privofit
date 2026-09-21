import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
enum Brand {
    static let lime = Color(hex: 0xC6F21A)
    static let limeDeep = Color(hex: 0x8FBF00)
    static let ink = Color(hex: 0x101714)
    static let night = Color(hex: 0x0B1210)
    static let fog = Color(hex: 0xE8F0E4)
    static let danger = Color("Danger")
    static let alert = Color(hex: 0xDC2F2A)
    static let sky = Color(hex: 0x3E8FD6)
    enum Space { static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 20
        static let lg: CGFloat = 32 }
    enum Radius { static let field: CGFloat = 14
        static let card: CGFloat = 26
        static let hero: CGFloat = 34 }
    static func background(_ scheme: ColorScheme) -> Color { Color("Background") }
    static func surface(_ scheme: ColorScheme) -> Color { Color("Surface") }
    static func text(_ scheme: ColorScheme) -> Color { Color("PrimaryText") }
}
struct BrandMark: View {
    var size: CGFloat = 44
    var showsName = true
    var body: some View {
        Group {
            if showsName {
                Image("BrandLogo")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(height: max(size, 22))
            } else {
                Image("BrandIcon")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Privofit")
    }
}
struct PrimaryButton: View {
    let title: String
    var symbol: String = "arrow.up.right"
    var busy = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { if busy { ProgressView().tint(Brand.ink) }; Text(title).font(.headline); Spacer(minLength: 8); Image(systemName: symbol) }
                .padding(.horizontal, 22).padding(.vertical, 19).frame(minHeight: 58).frame(maxWidth: .infinity)
                .foregroundStyle(Brand.ink).background(Brand.lime, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).disabled(busy)
    }
}
struct BrandCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.surface(scheme), in: RoundedRectangle(cornerRadius: Brand.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.card).strokeBorder(Brand.text(scheme).opacity(0.06)))
            .shadow(color: .black.opacity(scheme == .dark ? 0.08 : 0.04), radius: 12, y: 5)
    }
}
struct BrandFieldStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.padding(16).frame(minHeight: 52)
            .background(Brand.surface(scheme), in: RoundedRectangle(cornerRadius: Brand.Radius.field))
            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.field).strokeBorder(Brand.text(scheme).opacity(0.12)))
    }
}
extension View {
    func brandField() -> some View { modifier(BrandFieldStyle()) }
    func brandBackground() -> some View { modifier(BrandBackground()) }
    func clearTopChrome() -> some View { modifier(ClearTopChrome()) }
}
struct BrandBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .clearTopChrome()
            .background(Brand.background(scheme).ignoresSafeArea())
            .foregroundStyle(Brand.text(scheme))
    }
}
struct ClearTopChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .scrollEdgeEffectHidden(true, for: .top)
    }
}
enum BrandChrome {
    static func applyTransparentNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
        UINavigationBar.appearance().isTranslucent = true
    }
}
enum SystemFeedback {
    static func denied() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
struct StatusBadge: View {
    let title: String
    var symbol = "checkmark.seal"
    var body: some View { Label(title, systemImage: symbol).font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8).background(Brand.lime.opacity(0.16), in: Capsule()) }
}
struct FailureView: View {
    let message: String
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "exclamationmark.circle").font(.subheadline)
            if let retry { Button(L10n.tr("common.retry"), action: retry).buttonStyle(.bordered).frame(minHeight: 44) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.danger.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
    }
}
struct SkeletonCard: View {
    var body: some View { BrandCard { VStack(alignment: .leading, spacing: 16) { Text(L10n.tr("skeleton.membership")).font(.headline); Text(L10n.tr("skeleton.body")); ProgressView() } }.redacted(reason: .placeholder).accessibilityLabel(L10n.tr("common.loading")) }
}
struct NativeGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency { content.background(.background, in: Capsule()) }
        else if #available(iOS 26.0, *) { content.glassEffect(.regular, in: .capsule) }
        else { content.background(.ultraThinMaterial, in: Capsule()) }
    }
}
struct LiquidGlassBar: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var corner: CGFloat = 28
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if reduceTransparency {
            content.background(.thinMaterial, in: shape)
        } else {
            content.glassEffect(.regular.interactive(), in: shape)
        }
    }
}
extension View {
    func nativeGlass() -> some View { modifier(NativeGlass()) }
    func liquidGlassBar(corner: CGFloat = 28) -> some View { modifier(LiquidGlassBar(corner: corner)) }
}
struct Avatar: View {
    let name: String
    var size: CGFloat = 32
    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(size < 40 ? .subheadline.bold() : .title3.bold())
            .foregroundStyle(Brand.ink)
            .frame(width: size, height: size)
            .background(Brand.lime, in: Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}
struct MainToolbarModifier: ViewModifier {
    @Environment(AppModel.self) private var app
    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .clearTopChrome()
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { app.tab = .dashboard } label: {
                        BrandMark(size: 28, showsName: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Privofit")
                    LiveFloorButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        if app.isGuest { app.showGuestGate = true } else { app.showInbox = true }
                    } label: {
                        Image(systemName: "bell")
                    }
                    .accessibilityLabel(L10n.tr("notifications.title"))
                    Button { app.tab = .profile } label: {
                        Avatar(name: app.member?.firstName ?? "P", size: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("tab.profile"))
                }
            }
    }
}
extension View {
    func mainToolbar() -> some View { modifier(MainToolbarModifier()) }
}

struct LiveFloorButton: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presented = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let presence = GymPresence.resolve(app.reservations, now: context.date)
            Button {
                if app.isGuest {
                    app.showGuestGate = true
                    return
                }
                presented = true
                Task { await app.refreshReservations() }
            } label: {
                HStack(spacing: 6) {
                    LivePulse(tint: tint(presence), active: !app.isGuest && !reduceMotion)
                    Text(L10n.tr("home.live.kicker"))
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(foreground(presence))
                .background(background(presence), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.live")
            .accessibilityLabel(accessibilityText(presence))
        }
        .popover(isPresented: $presented) {
            LiveFloorDetail()
                .presentationCompactAdaptation(.popover)
        }
    }

    private func tint(_ presence: GymPresence) -> Color {
        if app.isGuest || (app.loading && app.reservations.isEmpty) { return .secondary }
        if case .occupied = presence { return Brand.alert }
        return Brand.ink
    }

    private func foreground(_ presence: GymPresence) -> Color {
        if case .occupied = presence, !app.isGuest { return Brand.fog }
        return Brand.ink
    }

    private func background(_ presence: GymPresence) -> Color {
        if app.isGuest || (app.loading && app.reservations.isEmpty) { return Color.primary.opacity(0.08) }
        if case .occupied = presence { return Brand.ink }
        return Brand.lime
    }

    private func accessibilityText(_ presence: GymPresence) -> String {
        "\(L10n.tr("home.live.kicker")). \(statusTitle(presence))"
    }

    private func statusTitle(_ presence: GymPresence) -> String {
        if app.isGuest { return L10n.tr("home.live.guest") }
        if case .occupied = presence { return L10n.tr("home.live.occupied") }
        return L10n.tr("home.live.free")
    }
}

struct LiveFloorDetail: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let presence = GymPresence.resolve(app.reservations)
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("home.live.kicker"))
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            Text(title(presence))
                .font(.title3.weight(.bold))
            if case .occupied(let reservation) = presence {
                Text(ReservationCalendar.timeRange(reservation.start, reservation.end))
                    .font(.headline.monospacedDigit())
                Text(reservation.room)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(width: 280, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func title(_ presence: GymPresence) -> String {
        if case .occupied = presence { return L10n.tr("home.live.occupied") }
        return L10n.tr("home.live.free")
    }
}

private struct LivePulse: View {
    var tint: Color
    var active: Bool
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 8, height: 8)
            .background {
                Circle()
                    .stroke(tint.opacity(0.35), lineWidth: 4)
                    .scaleEffect(active && expanded ? 2.1 : 1)
                    .opacity(active && expanded ? 0 : 0.9)
            }
            .frame(width: 22, height: 22)
            .onAppear { restart(active) }
            .onChange(of: active) { _, isActive in restart(isActive) }
            .accessibilityHidden(true)
    }

    private func restart(_ isActive: Bool) {
        guard isActive else { expanded = false; return }
        expanded = false
        withAnimation(.easeOut(duration: 1.25).repeatForever(autoreverses: false)) { expanded = true }
    }
}

// Shared semantic scales; SF adapts to Dynamic Type and the system language.
typealias PrivofitColors = Brand
typealias PrivofitSpacing = Brand.Space
typealias PrivofitRadius = Brand.Radius
enum PrivofitTypography {
    static let display: Font = .largeTitle.weight(.heavy)
    static let heading: Font = .title2.bold()
    static let body: Font = .body
    static let caption: Font = .caption
}
enum PrivofitShadow {
    static let radius: CGFloat = 20
    static let y: CGFloat = 8
}
