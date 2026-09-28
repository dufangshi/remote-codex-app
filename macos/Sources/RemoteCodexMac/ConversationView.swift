import SwiftUI
import RemoteCodexCore

struct ConversationView: View {
    @EnvironmentObject var state: AppState
    @State private var followLatest = true
    var body: some View {
        Group {
            if let detail = state.detail {
                VStack(spacing: 0) {
                    header(detail)
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 28) {
                                ForEach(detail.turns) { turn in
                                    VStack(alignment: .leading, spacing: 18) {
                                        ForEach(turn.items) { item in MessageView(item: item, threadID: detail.thread.id) }
                                        if let error = turn.error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout).textSelection(.enabled) }
                                        HStack(spacing: 6) {
                                            Image(systemName: turn.status == "completed" ? "checkmark.circle" : "circle.dotted")
                                            Text(turn.status.capitalized)
                                            if let model = turn.model { Text("·"); Text(model).lineLimit(1).truncationMode(.middle) }
                                            if let effort = turn.reasoningEffort { Text(effort).fixedSize() }
                                        }.font(.caption).foregroundStyle(.secondary)
                                    }.id(turn.id)
                                }
                                if detail.turns.isEmpty {
                                    ContentUnavailableView("Ready when you are", systemImage: "sparkles", description: Text("Send a message to start working with your agent."))
                                        .frame(maxWidth: .infinity).padding(.top, 70)
                                }
                                Color.clear.frame(height: 1).id("latest")
                                    .onAppear { followLatest = true }.onDisappear { followLatest = false }
                            }.padding(28).frame(maxWidth: 850).frame(maxWidth: .infinity, alignment: .center)
                        }
                        .onChange(of: detail.turns.last?.items.last?.text) { _, _ in
                            if followLatest { proxy.scrollTo("latest", anchor: .bottom) }
                        }
                        .onChange(of: detail.turns.count) { _, _ in
                            if followLatest { proxy.scrollTo("latest", anchor: .bottom) }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if !followLatest {
                                Button { proxy.scrollTo("latest", anchor: .bottom); followLatest = true } label: { Image(systemName: "arrow.down") }
                                    .buttonStyle(.bordered).clipShape(Circle()).padding(16).help("Jump to latest")
                            }
                        }
                    }
                    if !detail.pendingRequests.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(detail.pendingRequests) { request in
                                HStack {
                                    Image(systemName: "hand.raised").foregroundStyle(.orange)
                                    VStack(alignment: .leading) {
                                        Text(request.title).font(.callout.weight(.medium))
                                        if let description = request.description { Text(description).font(.caption).lineLimit(3) }
                                    }
                                    Spacer()
                                    if request.kind.lowercased().contains("approval") {
                                        Button("Deny") { Task { await state.respond(request, allow: false) } }
                                        Button("Allow") { Task { await state.respond(request, allow: true) } }.buttonStyle(.borderedProminent)
                                    } else { Button("Respond in Browser") { state.openWeb() } }
                                }
                            }
                        }.padding(14).background(.orange.opacity(0.08))
                    }
                    composer
                }.background(Color(nsColor: .textBackgroundColor))
            } else {
                ContentUnavailableView(state.threadID == nil ? "Make room for your next idea" : "Opening conversation…", systemImage: "terminal",
                    description: Text(state.threadID == nil ? "Choose a thread or start a new conversation. Your devices do the work; your Mac brings it together." : "Establishing an encrypted device connection."))
            }
        }
        .toolbar {
            Button { state.openWeb() } label: { Label("Open in Browser", systemImage: "arrow.up.right.square") }.help("Advanced thread actions in web client")
            Button { Task { await state.refreshThread() } } label: { Label("Refresh Thread", systemImage: "arrow.clockwise") }
        }
    }
    private func header(_ detail: ThreadDetail) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(detail.thread.title).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(detail.thread.agentId ?? detail.thread.provider)
                    if let model = detail.thread.model { Text("/ \(model)").lineLimit(1).truncationMode(.middle) }
                    Text(detail.thread.reasoningEffort ?? "Auto").fixedSize()
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if state.active {
                ProgressView().controlSize(.small)
                Text("Working").font(.caption).foregroundStyle(.secondary)
            } else { Label("Encrypted", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary) }
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !state.images.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(state.images) { attachment in
                            VStack(spacing: 4) {
                                if let image = attachment.image { Image(nsImage: image).resizable().scaledToFit().frame(width: 72, height: 56).clipShape(RoundedRectangle(cornerRadius: 6)) }
                                HStack {
                                    Text(attachment.name).font(.caption2).lineLimit(1).frame(maxWidth: 85)
                                    Button { state.images.removeAll { $0.id == attachment.id } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            NativeComposer(text: $state.draft) { Task { await state.send() } }
                .frame(minHeight: 62, maxHeight: 130).accessibilityIdentifier("messageInput")
                .overlay(alignment: .topLeading) {
                    if state.draft.isEmpty { Text("Message your agent…").foregroundStyle(.tertiary).padding(.leading, 5).padding(.top, 1).allowsHitTesting(false) }
                }
            HStack {
                Button { state.addImages() } label: { Image(systemName: "photo.badge.plus") }.buttonStyle(.plain).help("Attach images")
                Text("⌘ Return to send").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                if state.active { Button("Stop", role: .destructive) { Task { await state.interrupt() } }.buttonStyle(.bordered) }
                Button { Task { await state.send() } } label: {
                    Label(state.sending ? "Sending…" : (state.active ? "Steer" : "Send"), systemImage: "arrow.up")
                }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                    .disabled(state.sending || (state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.images.isEmpty))
                    .accessibilityIdentifier("sendMessage")
            }
        }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.08)))
            .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 10)
    }
}

struct MessageView: View {
    let item: HistoryItem
    let threadID: String
    private var isUser: Bool { ["userMessage", "user"].contains(item.kind) }
    private var isMessage: Bool { isUser || ["agentMessage", "assistantMessage", "assistant"].contains(item.kind) }
    var body: some View {
        if isMessage {
            VStack(alignment: .leading, spacing: 10) {
                Label(isUser ? "YOU" : "AGENT", systemImage: isUser ? "person.crop.circle" : "sparkle")
                    .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                ForEach(MessageSegment.parse(item.text)) { segment in
                    if let text = segment.text { MarkdownContent(text: text) }
                    if let path = segment.photoPath { NativeImage(path: path, threadID: threadID) }
                }
            }.padding(isUser ? 16 : 0).frame(maxWidth: .infinity, alignment: .leading)
                .background(isUser ? Color.accentColor.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 12))
        } else if item.kind == "image", let path = item.assetPath ?? item.detailText {
            NativeImage(path: path, threadID: threadID)
        } else {
            DisclosureGroup {
                Text(item.detailText ?? item.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            } label: {
                Label {
                    Text(item.previewText ?? item.text.components(separatedBy: .newlines).first ?? item.kind).lineLimit(2)
                } icon: { Image(systemName: item.kind.lowercased().contains("reason") ? "brain" : "terminal") }
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct NativeImage: View {
    @EnvironmentObject var state: AppState
    let path: String
    let threadID: String
    @State private var image: NSImage?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 320, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if let error {
                Label(error, systemImage: "photo").font(.caption).foregroundStyle(.secondary)
            } else { ProgressView().controlSize(.small).frame(width: 100, height: 60) }
            Text((path as NSString).lastPathComponent).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }.task(id: path) {
            do { image = try await state.image(path: path, thread: threadID) }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct MarkdownContent: View {
    let text: String
    var body: some View {
        let pieces = text.components(separatedBy: "```")
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { index, piece in
                if index % 2 == 1 {
                    let parts = piece.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                    let code = parts.count > 1 ? String(parts[1]) : piece
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(parts.count > 1 ? String(parts[0]) : "Code").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
                            } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copy code")
                        }
                        ScrollView(.horizontal) {
                            Text(code).font(.system(.callout, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                        }
                    }.padding(14).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                } else if !piece.isEmpty {
                    Text((try? AttributedString(markdown: piece, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(piece))
                        .font(.body).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
