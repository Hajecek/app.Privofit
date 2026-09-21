import SwiftUI

struct MembershipView: View {
    @Environment(AppModel.self) private var app
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if app.isDemo { StatusBadge(title: L10n.tr("demo.badge"), symbol: "hammer") }
                if loading { SkeletonCard() }
                if app.isGuest { Text(L10n.tr("guest.membership")).foregroundStyle(.secondary) }
                else if let membership = app.membership {
                    MemberPass(name: app.member?.firstName ?? "Privofit").padding(.vertical, 12)
                    MembershipSummary(membership: membership)
                }
                if let error { FailureView(message: error) { Task { await load() } } }
                Text(L10n.tr("membership.offers")).font(.title2.bold())
                if app.offers.isEmpty && !loading && error == nil { ContentUnavailableView(L10n.tr("membership.noOffers"), systemImage: "creditcard") }
                ForEach(app.offers) { offer in
                    BrandCard { VStack(alignment: .leading, spacing: 16) {
                        Text(offer.name).font(.title2.bold()); Text(offer.description).foregroundStyle(.secondary); Text(offer.priceDescription).font(.headline)
                        if app.isGuest { PrimaryButton(title: L10n.tr("membership.choose")) { app.showGuestGate = true } }
                        else { ConfiguredLink(title: L10n.tr("membership.checkout"), key: "CheckoutURL") }
                    } }
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.brandBackground().navigationTitle(L10n.tr("tab.membership")).mainToolbar().task { await load() }.refreshable { await load() }
    }
    private func load() async {
        guard !loading else { return }; loading = true; error = nil; defer { loading = false }
        do { app.offers = try await app.service.offers() } catch { self.error = FriendlyError.message(error) }
        if !app.isGuest {
            do { let result = try await app.service.membership(); guard app.phase == .authenticated else { return }; app.membership = result }
            catch { self.error = FriendlyError.message(error); app.handle(error, surface: false) }
        }
    }
}
struct MembershipSummary: View {
    let membership: Membership
    var body: some View {
        BrandCard { VStack(alignment: .leading, spacing: 16) {
            HStack { Text(membership.title).font(.title2.bold()); Spacer(); Image(systemName: "creditcard") }
            StatusBadge(title: L10n.tr("membership.status.\(membership.status.rawValue)"), symbol: membership.isActive ? "checkmark.seal" : "pause.circle")
            if let from = membership.validFrom { LabeledContent(L10n.tr("membership.from")) { Text(from, style: .date) } }
            LabeledContent(L10n.tr("membership.until")) { Text(membership.validUntil, style: .date) }
            if let entries = membership.remainingEntries { LabeledContent(L10n.tr("membership.entries"), value: entries.formatted()) }
        } }
    }
}
