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
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Share as link").font(.title2.bold()); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Anyone with the link can read the selected prompts, images and final replies.").foregroundStyle(Palette.muted)
            if let failure { Text(failure).foregroundStyle(.red) }
            VStack(alignment: .leading, spacing: 10) {
                Text("Turns to share").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                Picker("", selection: $scope) {
                    Text("All current turns" + (loaded ? " (\(turns.count))" : "")).tag("all")
                    Text("Choose turns").tag("selected")
                }.pickerStyle(.radioGroup).labelsHidden()
                if !loaded { ProgressView().controlSize(.small) }
                else if scope == "selected" {
                    HStack { Text("\(selected.count) selected").font(.caption).foregroundStyle(Palette.muted); Spacer(); Button("Clear selection") { selected.removeAll() } }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(turns) { turn in
                                Button {
                                    if selected.contains(turn.turnId) { selected.remove(turn.turnId) } else { selected.insert(turn.turnId) }
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: selected.contains(turn.turnId) ? "checkmark.square.fill" : "square").foregroundStyle(selected.contains(turn.turnId) ? Palette.accent : Palette.muted)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Turn \(turn.turnNumber)").font(.system(size: 13, weight: .medium))
                                            Text(turn.userPromptPreview?.isEmpty == false ? turn.userPromptPreview! : "No prompt text").font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                                        }
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(maxHeight: 160)
                }
            }.padding(12).glassBar()
            Button { Task { await create() } } label: {
                HStack { Image(systemName: "link"); Text(busy ? "Creating link…" : "Create & copy link") }
            }.buttonStyle(.borderedProminent).disabled(busy || !loaded || (scope == "selected" ? selected.isEmpty : turns.isEmpty))
            if copiedID != nil { Label("Read-only link copied", systemImage: "checkmark").foregroundStyle(Palette.accent) }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(links) { link in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text((link.live == true ? "Live" : "Snapshot") + " · \(link.turnCount) turns · " + timestamp(link.createdAt)).font(.caption).foregroundStyle(Palette.muted)
                                Spacer()
                                Button { Task { await revoke(link) } } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.red).help("Revoke link")
                            }
                            HStack {
                                Text(url(for: link)).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                Spacer()
                                Button { copy(link) } label: { Image(systemName: copiedID == link.id ? "checkmark" : "doc.on.doc") }.buttonStyle(.plain)
                            }
                        }.padding(10).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if links.isEmpty { Text("No links shared yet.").font(.caption).foregroundStyle(Palette.muted) }
                }
            }
        }.padding(24).frame(width: 460, height: 560).glassBar()
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
