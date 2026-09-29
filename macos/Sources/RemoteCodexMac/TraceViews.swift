import SwiftUI
import RemoteCodexCore

struct TraceTimestamp: View {
    let value: String
    let start: String?
    @State private var absolute = false
    private var textSize = TextSizePreference()
    private var label: String {
        guard !absolute, let created = date(value), let began = date(start) else { return timestamp(value) }
        let seconds = max(0, Int(created.timeIntervalSince(began)))
        return seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
    }
    var body: some View {
        Button(label) { absolute.toggle() }.buttonStyle(.plain).font(.system(size: textSize.points(11))).foregroundStyle(Palette.muted)
            .help(timestamp(value)).accessibilityLabel("Toggle timestamp, currently \(label)")
    }
}

struct TraceGroupView: View {
    let items: [HistoryItem]
    let thread: String
    @State private var expanded = false
    private var textSize = TextSizePreference()
    private var command: Bool { items.first?.kind == "commandExecution" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: command ? "square.stack" : "wrench.and.screwdriver").frame(width: 28, height: 28).overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border))
                    Text("\(command ? "Ran" : "Used") \(items.count) \(command ? "commands" : "tool calls")")
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 11))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(Palette.muted).font(.system(size: textSize.points(14)))
                .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(items.count) \(command ? "command" : "tool") entries")
            if expanded {
                VStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        TraceToolView(item: item, thread: thread, index: index + 1)
                    }
                }.padding(.leading, 28)
            }
        }
    }
}

struct TraceToolView: View {
    @EnvironmentObject var state: AppState
    let item: HistoryItem
    let thread: String
    var index: Int? = nil
    @State private var open = false
    @State private var detail: HistoryItem?
    @State private var loading = false
    @State private var failure: String?
    @State private var retry = 0
    private var textSize = TextSizePreference()
    private var command: Bool { item.kind == "commandExecution" }
    private var output: String { [detail?.detailText, detail?.text, item.detailText, item.text].compactMap { $0 }.first { !$0.isEmpty } ?? "No output." }
    var body: some View {
        Button { open = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let index { Text(String(format: "%02d", index)).font(.system(size: textSize.points(12), design: .monospaced)).foregroundStyle(Palette.muted) }
                else { Image(systemName: command ? "terminal" : "wrench"); Text(command ? "Ran" : "Used").foregroundStyle(Palette.muted) }
                Text(TimelineProjection.label(item).components(separatedBy: .newlines).first ?? item.kind).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if item.status == "inProgress" { ProgressView().controlSize(.mini) }
            }.font(.system(size: textSize.points(14))).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(index.map { "Open grouped command \($0)" } ?? (command ? "Open full command" : "Open full tool call"))
            .sheet(isPresented: $open) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text(command ? "Command Output" : "Activity details").font(.headline); Spacer(); Button("Copy") { copy(output) }; Button("Close") { open = false }.keyboardShortcut(.cancelAction) }
                    Text(TimelineProjection.label(item)).font(.system(size: textSize.points(13), design: .monospaced)).textSelection(.enabled).lineLimit(4)
                    if loading { ProgressView() }
                    if let failure { Text(failure).foregroundStyle(.red); Button("Retry") { retry += 1 } }
                    ScrollView([.horizontal, .vertical]) {
                        Text(output).font(.system(size: textSize.points(13), design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false).padding(12)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.background)
                }.padding(20).frame(width: 760, height: 520).background(Palette.panel)
                    .task(id: retry) {
                        guard detail == nil else { return }; loading = true; defer { loading = false }
                        do { detail = try await state.itemDetail(thread: thread, item: item.id); failure = nil }
                        catch { if !Task.isCancelled { failure = error.localizedDescription } }
                    }
            }
    }
}
