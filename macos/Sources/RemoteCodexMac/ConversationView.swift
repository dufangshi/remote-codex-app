import SwiftUI
import RemoteCodexCore

struct ConversationView: View {
    @EnvironmentObject var state: AppState
    @State private var followLatest = true
    var body: some View {
        VStack(spacing: 0) {
            if state.showingSearch {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Find in loaded history", text: $state.conversationQuery).textFieldStyle(.plain)
                    Text("\(matching.count) turns").font(.caption).foregroundStyle(Palette.muted)
                    IconButton(title: "Close search", icon: "xmark") { state.showingSearch = false; state.conversationQuery = "" }
                }.padding(.horizontal, 24).padding(.vertical, 6).background(Palette.panel)
            }
            if let error = state.threadError { InlineError(message: error) { state.threadError = nil } }
            if let detail = state.detail {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 30) {
                            if state.hasOlderHistory {
                                Button(state.historyLoading ? "Loading…" : "Earlier messages") {
                                    let anchor = state.history.first?.id
                                    Task { await state.loadOlderHistory(); if let anchor { proxy.scrollTo(anchor, anchor: .top) } }
                                }.buttonStyle(.plain).foregroundStyle(Palette.muted).disabled(state.historyLoading).frame(maxWidth: .infinity)
                            }
                            ForEach(matching) { turn in NativeTurnView(turn: turn, thread: detail.thread.id).id(turn.id) }
                            if state.history.isEmpty {
                                ContentUnavailableView("Ready when you are", systemImage: "sparkles", description: Text("Send a message to start working with your agent.")).padding(.top, 70)
                            }
                            Color.clear.frame(height: 1).id("latest")
                                .onAppear { followLatest = true }.onDisappear { followLatest = false }
                        }.padding(.horizontal, 36).padding(.vertical, 28).frame(maxWidth: 1000).frame(maxWidth: .infinity)
                    }.scrollIndicators(.never)
                        .onAppear { proxy.scrollTo("latest", anchor: .bottom) }
                        .onChange(of: state.history.last?.items.last?.text) { _, _ in if followLatest { proxy.scrollTo("latest", anchor: .bottom) } }
                        .onChange(of: state.history.count) { old, new in if followLatest && new > old { proxy.scrollTo("latest", anchor: .bottom) } }
                        .overlay(alignment: .bottom) {
                            if !followLatest {
                                Button { proxy.scrollTo("latest", anchor: .bottom) } label: { Image(systemName: "arrow.down.to.line").padding(10) }
                                    .buttonStyle(.plain).foregroundStyle(Palette.accent).background(Palette.surface, in: Capsule()).padding(8).help("Jump to latest")
                            }
                        }
                }
                ForEach(detail.pendingRequests) { NativeRequestView(request: $0) }
                composer
            } else if state.threadLoading {
                Spacer(); ProgressView("Opening encrypted conversation…").foregroundStyle(Palette.muted); Spacer()
            } else {
                ContentUnavailableView(state.threadID == nil ? "Your workspace, ready." : "Couldn’t open conversation",
                    systemImage: state.threadID == nil ? "bubble.left.and.bubble.right" : "exclamationmark.bubble",
                    description: Text(state.threadError ?? "Choose a conversation or start a new chat."))
                if state.threadID != nil { Button("Retry") { Task { await state.refreshThread() } }.padding() }
            }
        }.background(Palette.background).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var matching: [Turn] {
        let q = state.conversationQuery.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? state.history : state.history.filter { $0.items.contains { $0.text.localizedCaseInsensitiveContains(q) } }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !state.images.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(state.images) { attachment in
                            HStack {
                                if let image = attachment.image { Image(nsImage: image).resizable().scaledToFit().frame(width: 46, height: 40) }
                                Text(attachment.name).font(.caption).lineLimit(1)
                                Button { state.images.removeAll { $0.id == attachment.id } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                            }.padding(8).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.scrollIndicators(.never)
            }
            NativeComposer(text: $state.draft) { Task { await state.send() } }.frame(height: 82)
                .overlay(alignment: .topLeading) {
                    if state.draft.isEmpty { Text("Message your agent…").foregroundStyle(Palette.muted.opacity(0.65)).padding(.top, 6).padding(.leading, 5).allowsHitTesting(false) }
                }
            HStack(spacing: 10) {
                Menu {
                    Button("Summarize conversation") { state.draft += "Summarize our conversation and the next steps." }
                    Button("Review workspace changes") { state.draft += "Review the current workspace changes." }
                } label: { Image(systemName: "command").frame(width: 24, height: 24) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Prompt shortcuts")
                IconButton(title: "Attach images", icon: "plus") { state.addImages() }
                Spacer(minLength: 4)
                Button { Task { await state.prepareThreadSettings() } } label: {
                    HStack(spacing: 5) {
                        Text(state.detail?.thread.model ?? "Model").lineLimit(1).truncationMode(.middle)
                        Text("· " + (state.detail?.thread.reasoningEffort ?? "Auto")).fixedSize()
                        Image(systemName: "chevron.down").font(.caption2)
                    }.font(.system(size: 12)).foregroundStyle(Palette.muted)
                }.buttonStyle(.plain).disabled(state.active)
                if state.active {
                    IconButton(title: "Stop Current Turn", icon: "stop.fill") { Task { await state.interrupt() } }
                }
                Button { Task { await state.send() } } label: {
                    Group {
                        if state.sending { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.up").font(.system(size: 19, weight: .semibold)) }
                    }.frame(width: 38, height: 38).background(Palette.accent, in: Circle()).foregroundStyle(.black)
                }.buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command)
                    .disabled(state.sending || (state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.images.isEmpty))
                    .accessibilityIdentifier("sendMessage").accessibilityLabel(state.active ? "Steer" : "Send Prompt")
            }
        }.padding(16).background(Palette.panel, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.border, lineWidth: 1.5))
            .padding(.horizontal, 28).padding(.bottom, 18).padding(.top, 8)
    }
}

private struct NativeTurnView: View {
    @EnvironmentObject var state: AppState
    let turn: Turn
    let thread: String
    @State private var toolsOpen = false
    @State private var usageOpen = false
    @State private var forkConfirm = false
    private var tools: [HistoryItem] { turn.items.filter { !["userMessage", "user", "agentMessage", "assistantMessage", "assistant", "image"].contains($0.kind) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(turn.items.filter { ["userMessage", "user"].contains($0.kind) }) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(timestamp(turn.startedAt)).font(.system(size: 11)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .trailing)
                    MessageView(item: item, threadID: thread)
                }
            }
            ForEach(turn.items.filter { ["agentMessage", "assistantMessage", "assistant", "image"].contains($0.kind) }) { MessageView(item: $0, threadID: thread) }
            HStack(spacing: 10) {
                Circle().fill(turn.status == "inProgress" ? Palette.accent : Palette.muted).frame(width: 6, height: 6)
                Button { toolsOpen.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tools.isEmpty ? "checkmark" : "chevron.right").font(.caption)
                        Text(durationLabel)
                    }
                }.buttonStyle(.plain).popover(isPresented: $toolsOpen, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("Turn activity").font(.headline); Spacer(); Button("Done") { toolsOpen = false } }
                        ScrollView { LazyVStack(alignment: .leading, spacing: 12) { ForEach(tools) { MessageView(item: $0, threadID: thread) } } }
                        if tools.isEmpty { Text("No tool steps in this turn.").foregroundStyle(Palette.muted) }
                    }.padding(20).frame(width: 660, height: 450)
                }
                if !tools.isEmpty { Text("\(tools.count) steps") }
                if let model = turn.model { Text(model).lineLimit(1).truncationMode(.middle) }
                if let effort = turn.reasoningEffort { Text("· " + effort).fixedSize() }
                Spacer(minLength: 0)
                if let usage = turn.tokenUsage {
                    Button(short(usage.total.totalTokens) + " tok") { usageOpen.toggle() }.buttonStyle(.plain)
                        .popover(isPresented: $usageOpen) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Token usage").font(.headline)
                                LabeledContent("Input", value: usage.total.inputTokens.formatted())
                                LabeledContent("Cached", value: usage.total.cachedInputTokens.formatted())
                                LabeledContent("Output", value: usage.total.outputTokens.formatted())
                                if let price = turn.priceEstimate { LabeledContent("Estimated API cost", value: price.totalUsd.formatted(.currency(code: "USD"))) }
                            }.padding(20).frame(width: 280)
                        }
                }
                Menu {
                    Button("Copy turn") { copy(turn.items.map(\.text).joined(separator: "\n\n")) }
                    Button("Fork from this turn…") { forkConfirm = true }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
            if let error = turn.error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red).textSelection(.enabled) }
        }.confirmationDialog("Fork from this turn?", isPresented: $forkConfirm) {
            Button("Create Fork") { Task { await state.fork(turn: turn.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Creates a separate conversation. The original remains unchanged.") }
    }
    private var durationLabel: String {
        if turn.status == "inProgress" { return "Working…" }
        if let start = date(turn.startedAt), let end = date(turn.completedAt) {
            let s = max(0, Int(end.timeIntervalSince(start)))
            return "Worked for " + (s >= 60 ? "\(s / 60)m \(s % 60)s" : "\(s)s")
        }
        return turn.status.capitalized
    }
}

struct MessageView: View {
    @EnvironmentObject var state: AppState
    let item: HistoryItem
    let threadID: String
    @State private var expanded = false
    @State private var fetched: HistoryItem?
    @State private var failure: String?
    private var isUser: Bool { ["userMessage", "user"].contains(item.kind) }
    private var message: Bool { ["userMessage", "user", "agentMessage", "assistantMessage", "assistant"].contains(item.kind) }
    var body: some View {
        if message {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(MessageSegment.parse(item.text)) { segment in
                    if let text = segment.text {
                        if isUser { Text(text).font(.system(size: 15)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                        else { MarkdownContent(text: text) }
                    }
                    if let path = segment.photoPath { NativeImage(path: path, threadID: threadID) }
                }
            }.padding(isUser ? 16 : 0)
                .frame(maxWidth: isUser ? 620 : .infinity, alignment: .leading)
                .background(isUser ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                .contextMenu { Button("Copy message") { copy(item.text) } }
        } else if item.kind == "image", let path = item.assetPath ?? item.detailText {
            NativeImage(path: path, threadID: threadID)
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                MarkdownContent(text: fetched?.detailText ?? fetched?.text ?? item.detailText ?? item.text).padding(.top, 10)
                if let failure { Text(failure).foregroundStyle(.red).font(.caption) }
            } label: {
                Label(item.previewText ?? item.text.components(separatedBy: .newlines).first ?? item.kind,
                      systemImage: item.kind.lowercased().contains("reason") ? "brain" : "terminal")
                    .font(.system(size: 12)).lineLimit(2).foregroundStyle(Palette.muted)
            }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                .task(id: expanded) {
                    if expanded, fetched == nil, item.hasDeferredDetail == true {
                        do { fetched = try await state.itemDetail(thread: threadID, item: item.id) }
                        catch { if !Task.isCancelled { failure = error.localizedDescription } }
                    }
                }
        }
    }
}

struct NativeImage: View {
    @EnvironmentObject var state: AppState
    let path: String
    let threadID: String
    @State private var image: NSImage?
    @State private var error: String?
    @State private var preview = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image {
                Button { preview = true } label: {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 320, maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).help("Open image preview")
            } else if let error { Label(error, systemImage: "photo").font(.caption).foregroundStyle(Palette.muted) }
            else { ProgressView().controlSize(.small).frame(width: 100, height: 60) }
            Text((path as NSString).lastPathComponent).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1)
        }.task(id: path) {
            do { image = try await state.image(path: path, thread: threadID) } catch { self.error = error.localizedDescription }
        }.sheet(isPresented: $preview) {
            VStack {
                HStack { Spacer(); Button("Done") { preview = false }.keyboardShortcut(.cancelAction) }
                if let image { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.padding(20).frame(width: 800, height: 600).background(Palette.background)
        }
    }
}

struct MarkdownContent: View {
    let text: String
    @State private var full = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(MarkdownParser.blocks(String(text.prefix(full ? 1_000_000 : 24_000))).enumerated()), id: \.offset) { _, block in
                render(block)
            }
            if !full && text.count > 24_000 { Button("Show full message") { full = true } }
        }.font(.system(size: 15)).foregroundStyle(Palette.text).lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func render(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let value): inline(value)
        case .heading(let level, let value):
            inline(value).font(.system(size: level == 1 ? 26 : level == 2 ? 22 : 18, weight: .semibold)).padding(.top, 6)
        case .list(let marker, let value):
            HStack(alignment: .top, spacing: 12) { Text(marker).frame(minWidth: 18); inline(value) }.padding(.leading, 12)
        case .quote(let value):
            HStack(spacing: 14) { Palette.accent.opacity(0.6).frame(width: 3); inline(value).foregroundStyle(Palette.muted) }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
        case .rule: Divider().overlay(Palette.border)
        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                HStack { Text(language.isEmpty ? "Code" : language).font(.caption); Spacer(); Button { copy(code) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copy code") }
                    .foregroundStyle(Palette.muted).padding(12).background(Palette.surface)
                ScrollView(.horizontal) {
                    Text(code).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false).padding(14)
                }.scrollIndicators(.never)
            }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 10)).clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border))
        case .table(let header, let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow { ForEach(Array(header.enumerated()), id: \.offset) { _, value in inline(value).fontWeight(.semibold).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface) } }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, value in inline(value).padding(12).frame(maxWidth: .infinity, alignment: .leading).overlay(alignment: .top) { Palette.border.frame(height: 1) } } }
                    }
                }.background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
            }.scrollIndicators(.never)
        }
    }
    private func inline(_ value: String) -> some View {
        Text((try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value))
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .tint(Palette.accent)
    }
}

private struct NativeRequestView: View {
    @EnvironmentObject var state: AppState
    let request: ActionRequest
    @State private var answers: [String: [String]] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(request.title, systemImage: "hand.raised").font(.headline)
            if let description = request.description { Text(description).font(.callout) }
            ForEach(request.questions ?? []) { question in
                Text(question.question).font(.callout)
                let value = Binding(get: { (answers[question.id] ?? []).joined(separator: ", ") }, set: { answers[question.id] = [$0] })
                if question.isSecret { SecureField("Answer", text: value).textFieldStyle(.roundedBorder) }
                else { TextField("Answer", text: value).textFieldStyle(.roundedBorder) }
                if let options = question.options {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(options, id: \.label) { option in
                            Button {
                                if question.multiSelect == true {
                                    var selected = answers[question.id] ?? []
                                    if selected.contains(option.label) { selected.removeAll { $0 == option.label } } else { selected.append(option.label) }
                                    answers[question.id] = selected
                                } else { answers[question.id] = [option.label] }
                            } label: { Label(option.label, systemImage: answers[question.id]?.contains(option.label) == true ? "checkmark.circle.fill" : "circle") }.help(option.description)
                        }
                    }
                }
            }
            Button("Submit response") { Task { await state.respond(request, answers: answers) } }
                .buttonStyle(.borderedProminent).disabled((request.questions ?? []).contains { (answers[$0.id] ?? []).allSatisfy { $0.isEmpty } })
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.accent.opacity(0.08))
    }
}

private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
private func date(_ value: String?) -> Date? {
    guard let value else { return nil }; let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}
private func timestamp(_ value: String?) -> String { date(value)?.formatted(date: .abbreviated, time: .shortened) ?? "" }
private func short(_ n: Int) -> String { n >= 1_000_000 ? String(format: "%.1fm", Double(n) / 1_000_000) : n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)" }
