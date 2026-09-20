import SwiftUI

struct MemberPass: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt: CGSize = .zero
    let name: String
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack { BrandMark(size: 28); Spacer(); Image(systemName: "wave.3.right").font(.title2).foregroundStyle(Brand.lime) }
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("redesign.digitalPass")).font(.caption.weight(.medium)).foregroundStyle(Brand.fog.opacity(0.65))
                    Text(name).font(.title3.weight(.semibold))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.headline).foregroundStyle(Brand.ink).frame(width: 36, height: 36).background(Brand.lime, in: Circle()).accessibilityHidden(true)
            }
        }.padding(24).foregroundStyle(Brand.fog)
            .background {
                RoundedRectangle(cornerRadius: 26).fill(LinearGradient(colors: [Color(hex: 0x2E3F32), Brand.ink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .topTrailing) { Circle().stroke(Brand.lime.opacity(0.1), lineWidth: 32).frame(width: 150, height: 150).offset(x: 45, y: -65) }.clipShape(RoundedRectangle(cornerRadius: 26))
            }
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Brand.fog.opacity(0.16)))
            .shadow(color: .black.opacity(0.15), radius: 16, y: 10)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(tilt.width / 18)), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(-tilt.height / 22)), axis: (x: 1, y: 0, z: 0))
            .gesture(DragGesture(minimumDistance: 15).onChanged { tilt = $0.translation }.onEnded { _ in withAnimation(reduceMotion ? nil : .spring()) { tilt = .zero } })
            .accessibilityElement(children: .combine)
    }
}
