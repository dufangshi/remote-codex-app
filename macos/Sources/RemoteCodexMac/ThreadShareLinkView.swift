import SwiftUI
import RemoteCodexCore

/// Publishes a read-only capability link. The relay always re-fetches the
/// live transcript from the device via the publication token at view time,
/// so the client only needs to mint the token - never a local snapshot.
struct ThreadShareLinkView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var turns: [ExportTurnSummary] = []
    @State private var loaded = false
    @State private var scope = "all"
    @State private var selected: Set<String> = []
    @State private var links: [ThreadPublicLink] = []
    @State private var busy = false
    @State private var failure: String?
    @State private var copiedID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(title: "Share as link", subtitle: "Anyone with the link can read the selected prompts, images and final replies.", close: { dismiss() })
            if let failure { Text(failure).font(.system(size: 12)).foregroundStyle(.red) }
            SheetCard {
                Text("Turns to share").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                SelectableRow(title: "All current turns" + (loaded ? " (\(turns.count))" : ""), selected: scope == "all") { scope = "all" }
                SelectableRow(title: "Choose turns", selected: scope == "selected") { scope = "selected" }
                if !loaded { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
                else if scope == "selected" {
                    HStack { Text("\(selected.count) selected").font(.system(size: 11)).foregroundStyle(Palette.muted); Spacer(); Button("Clear selection") { selected.removeAll() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(turns) { turn in
                                SelectableCheckRow(title: "Turn \(turn.turnNumber)", subtitle: turn.userPromptPreview?.isEmpty == false ? turn.userPromptPreview! : "No prompt text", checked: selected.contains(turn.turnId)) {
                                    if selected.contains(turn.turnId) { selected.remove(turn.turnId) } else { selected.insert(turn.turnId) }
                                }
                            }
                        }
                    }.frame(maxHeight: 150).background(Palette.background, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Button { Task { await create() } } label: {
                HStack { Image(systemName: "link"); Text(busy ? "Creating link…" : "Create & copy link") }
                    .frame(maxWidth: .infinity).padding(.vertical, 2)
            }.buttonStyle(.borderedProminent).tint(Palette.accent).controlSize(.large)
                .disabled(busy || !loaded || (scope == "selected" ? selected.isEmpty : turns.isEmpty))
            if copiedID != nil { Label("Read-only link copied", systemImage: "checkmark").font(.system(size: 12)).foregroundStyle(Palette.accent) }
            Text("Shared links").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(links) { link in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                StatusBadge(text: link.live == true ? "Live" : "Snapshot", tint: link.live == true ? Palette.accent : Palette.muted)
                                Text("\(link.turnCount) turns · " + timestamp(link.createdAt)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                                Spacer()
                                Button { Task { await revoke(link) } } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.red).help("Revoke link")
                            }
                            HStack(spacing: 8) {
                                Text(url(for: link)).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                    .padding(.horizontal, 8).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 6))
                                Button { copy(link) } label: { Image(systemName: copiedID == link.id ? "checkmark" : "doc.on.doc") }.buttonStyle(.plain).foregroundStyle(copiedID == link.id ? Palette.accent : Palette.muted)
                            }
                        }.padding(10).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1))
                    }
                    if links.isEmpty { Text("No links shared yet.").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                }
            }
        }.padding(24).frame(width: 460, height: 600).glassBar()
            .task { await loadTurns(); await loadLinks() }
    }
    private func url(for link: ThreadPublicLink) -> String { (state.client?.origin.absoluteString ?? "") + "/s/" + link.id }
    private func copy(_ link: ThreadPublicLink) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url(for: link), forType: .string); copiedID = link.id }
    private func loadTurns() async {
        do { let result = try await state.exportTurns(); turns = result.turns; selected = Set(result.turns.map(\.turnId)); loaded = true }
        catch { failure = error.localizedDescription }
    }
    private func loadLinks() async {
        guard let api = state.client, let device = state.deviceID, let thread = state.threadID else { return }
        var query = URLComponents(); query.queryItems = [URLQueryItem(name: "deviceId", value: device), URLQueryItem(name: "threadId", value: thread)]
        do { links = try await api.relay("/relay/thread-links?" + (query.percentEncodedQuery ?? "")) }
        catch { failure = error.localizedDescription }
    }
    private func theme() -> String { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light" }
    private func create() async {
        guard let api = state.client, let device = state.deviceID, let thread = state.threadID else { return }
        let turnIds = scope == "all" ? turns.map(\.turnId) : Array(selected)
        guard !turnIds.isEmpty else { return }
        busy = true; failure = nil; defer { busy = false }
        do {
            let publication: CreatePublicationResult = try await api.device(device, "/api/threads/\(thread)/publications", method: "POST", body: ["turnIds": turnIds, "theme": theme()])
            do {
                let link: ThreadPublicLink = try await api.relay("/relay/thread-links", method: "POST", body: ["deviceId": device, "threadId": thread, "publicationToken": publication.token])
                links.insert(link, at: 0); copy(link)
            } catch {
                _ = try? await api.deviceData(device, "/api/publications/\(publication.token)", method: "DELETE")
                throw error
            }
        } catch { failure = error.localizedDescription }
    }
    private func revoke(_ link: ThreadPublicLink) async {
        guard let api = state.client else { return }
        busy = true; failure = nil; defer { busy = false }
        do { try await api.relayVoid("/relay/public-links/\(link.id)", method: "DELETE"); links.removeAll { $0.id == link.id } }
        catch { failure = error.localizedDescription }
    }
}
