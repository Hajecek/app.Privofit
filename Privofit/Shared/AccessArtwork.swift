import SwiftUI

/// Vector artwork, not a simulated system control. Motion follows confirmed app state.
struct AccessLock: View {
    var unlocked = false
    var tint: Color = Brand.ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.23)
                    .trim(from: 0.06, to: 0.94)
                    .stroke(tint, style: StrokeStyle(lineWidth: w * 0.075, lineCap: .round))
                    .frame(width: w * 0.52, height: w * 0.58)
                    .rotationEffect(.degrees(unlocked ? -30 : 0), anchor: .bottomLeading)
                    .offset(x: unlocked ? -w * 0.08 : 0, y: -w * 0.22)
                RoundedRectangle(cornerRadius: w * 0.17)
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.86)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: w * 0.86, height: w * 0.66).offset(y: w * 0.19)
                VStack(spacing: -2) {
                    Circle().frame(width: w * 0.14, height: w * 0.14)
                    Capsule().frame(width: w * 0.06, height: w * 0.13)
                }.foregroundStyle(Brand.lime).offset(y: w * 0.18)
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }.aspectRatio(0.92, contentMode: .fit)
            .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.72), value: unlocked)
            .accessibilityHidden(true)
    }
}
struct AccessToken: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt: CGSize = .zero
    var body: some View {
        ZStack {
            Circle().fill(Brand.lime.opacity(0.1)).frame(width: 150, height: 150)
            RoundedRectangle(cornerRadius: 28).fill(Brand.limeDeep).frame(width: 94, height: 136)
                .rotationEffect(.degrees(15)).offset(x: 21, y: 5)
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(colors: [Brand.lime, Color(hex: 0xDDED88)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    VStack { Image(systemName: "wave.3.right").font(.caption.bold()); Spacer(); AccessLock().frame(width: 42); Spacer(); Capsule().fill(Brand.ink.opacity(0.25)).frame(width: 25, height: 4) }.padding(16)
                }
                .frame(width: 94, height: 136).rotationEffect(.degrees(-12))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 14)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(tilt.width / 6)), axis: (x: 0, y: 1, z: 0))
        }.frame(width: 180, height: 178)
            .gesture(DragGesture().onChanged { tilt = $0.translation }.onEnded { _ in withAnimation(reduceMotion ? nil : .spring()) { tilt = .zero } })
            .accessibilityHidden(true)
    }
}
struct DoorPortal: View {
    let opened: Bool
    var checking = false
    var denied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var leaf: [Color] {
        denied
            ? [Color(hex: 0xF7C9C6), Color(hex: 0xE07068), Color(hex: 0xC4332E)]
            : [Color(hex: 0xEDF6B1), Brand.lime, Color(hex: 0xA9D02A)]
    }
    var body: some View {
        GeometryReader { geometry in
            let height = min(geometry.size.height - 24, 330)
            let width = height * 0.65
            ZStack {
                Ellipse().fill(Brand.ink.opacity(0.12)).frame(width: width * 1.4, height: 24).blur(radius: 12).offset(y: height / 2 + 7)
                RoundedRectangle(cornerRadius: 27).fill(Brand.ink).frame(width: width + 18, height: height + 18)
                RoundedRectangle(cornerRadius: 21)
                    .fill(LinearGradient(colors: [Color(hex: 0x344B21), Brand.night], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 66, weight: .ultraLight)).foregroundStyle(Brand.lime.opacity(opened ? 0.8 : 0)) }
                    .frame(width: width, height: height)
                RoundedRectangle(cornerRadius: 21)
                    .fill(LinearGradient(colors: leaf, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15).strokeBorder(Brand.ink.opacity(0.12)).padding(12)
                            AccessLock(unlocked: opened).frame(width: width * 0.36)
                            HStack { Spacer(); Capsule().fill(Brand.ink).frame(width: 5, height: 38).padding(.trailing, 22) }
                        }
                    }
                    .frame(width: width, height: height)
                    .rotation3DEffect(.degrees(opened && !reduceMotion ? -74 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
                    .opacity(opened && reduceMotion ? 0.12 : 1)
                    .animation(reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.95, dampingFraction: 0.82).delay(0.55), value: opened)
                if checking { ProgressView().tint(Brand.ink).padding(12).background(denied ? Color(hex: 0xF7C9C6) : Brand.lime, in: Circle()).offset(y: height * 0.36) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.accessibilityHidden(true)
    }
}
struct AccessDeniedShake: GeometryEffect {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let decay = 1 - progress
        let x = sin(progress * .pi * 6) * 18 * decay
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}
struct SectionHeading: View {
    let title: String
    var body: some View { Text(title).font(.title3.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading) }
}
struct FieldLabel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary); content } }
}
