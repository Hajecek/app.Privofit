import SwiftUI
struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        VStack(spacing: 28) {
            Spacer(); BrandMark(size: 64).scaleEffect(appeared || reduceMotion ? 1 : 0.94)
            Text(L10n.tr("launch.tagline")).font(.subheadline).multilineTextAlignment(.center)
            ProgressView().tint(Brand.lime); Spacer()
        }.padding(28).frame(maxWidth: .infinity).brandBackground()
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { appeared = true } }
    }
}
