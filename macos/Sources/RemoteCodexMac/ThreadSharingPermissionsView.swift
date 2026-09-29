import SwiftUI
import RemoteCodexCore

private struct PermissionEntry: Identifiable {
    let grant: Grant
    let isShare: Bool
    var id: String { grant.id }
}

struct ThreadSharingPermissionsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var inviting = false
    @State private var editing: PermissionEntry?
    @State private var revoking: PermissionEntry?
    @State private var busy = false
    private var entries: [PermissionEntry] {
        let shares = (state.portal?.sharedByMe ?? []).filter { $0.threadId == state.threadID }.map { PermissionEntry(grant: $0, isShare: true) }
        let grants = (state.portal?.grantsByMe ?? []).filter { $0.deviceId == state.deviceID && $0.scope == "device" }.map { PermissionEntry(grant: $0, isShare: false) }
        return shares + grants
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Sharing permissions").font(.title2.bold()); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Choose who can view or collaborate on this thread.").foregroundStyle(Palette.muted)
            if let error = state.error { InlineError(message: error) { state.error = nil } }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(entries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.grant.targetUsername ?? "Someone").fontWeight(.medium)
                                Text((entry.isShare ? "" : "Whole device · ") + "Thread: \(entry.grant.threadAccess ?? "read") · Workspace: \(entry.grant.workspaceAccess ?? "none")")
                                    .font(.caption).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Button("Edit") { editing = entry }
                            Button("Revoke", role: .destructive) { revoking = entry }
                        }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if entries.isEmpty { Text("Only you can access this thread.").font(.caption).foregroundStyle(Palette.muted).padding(.vertical, 8) }
                }
            }
            Button { inviting = true } label: { Label("Invite someone", systemImage: "person.badge.plus") }.buttonStyle(.borderedProminent)
        }.padding(24).frame(width: 460, height: 480).glassBar()
            .task { await state.refreshPortal() }
            .sheet(isPresented: $inviting) {
                AccessEditor(thread: ThreadShareTarget(
                    deviceId: state.deviceID ?? "", threadId: state.threadID ?? "",
                    threadTitle: state.detail?.thread.title,
                    workspaceId: state.detail?.thread.workspaceId,
                    workspaceLabel: state.workspaces.first { $0.id == state.detail?.thread.workspaceId }?.label
                ), grant: nil, isShare: true)
            }
            .sheet(item: $editing) { entry in AccessEditor(grant: entry.grant, isShare: entry.isShare) }
            .confirmationDialog("Revoke shared access?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } })) {
                Button("Revoke access", role: .destructive) { if let entry = revoking { Task { await revoke(entry) } }; revoking = nil }
            } message: { Text("The recipient's shared access will stop working immediately.") }
    }
    private func revoke(_ entry: PermissionEntry) async {
        guard let api = state.client else { return }; busy = true; state.error = nil; defer { busy = false }
        do { try await api.relayVoid("/relay/\(entry.isShare ? "shares" : "grants")/\(entry.grant.id)", method: "DELETE"); await state.refreshPortal() }
        catch { state.error = error.localizedDescription }
    }
}
