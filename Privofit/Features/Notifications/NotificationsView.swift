import SwiftUI

struct NotificationsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { FailureView(message: error) { Task { await load() } } }
            if app.inbox.isEmpty && !loading && error == nil { ContentUnavailableView(L10n.tr("notifications.empty"), systemImage: "bell") }
            ForEach(app.inbox) { item in
                VStack(alignment: .leading, spacing: 10) { Text(item.title).font(.headline); Text(item.body); Text(item.date, style: .date).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 8)
            }
        }.scrollContentBackground(.hidden).brandBackground().listSectionSpacing(20).navigationTitle(L10n.tr("notifications.title")).mainToolbar().toolbar { Button(L10n.tr("common.close")) { dismiss() } }
            .task { await load(); AppIconBadgeSync.clear() }.refreshable { await load() }
    }
    private func load() async {
        guard app.phase == .authenticated, !loading else { return }; loading = true; defer { loading = false }
        do { let items = try await app.service.inbox(); guard app.phase == .authenticated else { return }; app.inbox = items; error = nil }
        catch { self.error = FriendlyError.message(error); app.handle(error, surface: false) }
    }
}
