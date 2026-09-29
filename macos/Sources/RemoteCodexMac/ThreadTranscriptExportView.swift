import SwiftUI
import RemoteCodexCore

struct ThreadTranscriptExportView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var turns: [ExportTurnSummary] = []
    @State private var loaded = false
    @State private var mode = "latest"
    @State private var limitChoice = 10
    @State private var selected: Set<String> = []
    @State private var includeTokenAndPrice = true
    @State private var busy = false
    @State private var failure: String?
    private let limitChoices = [3, 10, 20, 0]
    private func limitLabel(_ value: Int) -> String { value == 0 ? "All" : "\(value)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Download transcript").font(.title2.bold()); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Save a readable copy of your conversation as HTML.").foregroundStyle(Palette.muted)
            if let failure { Text(failure).foregroundStyle(.red) }
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $mode) { Text("Latest turns").tag("latest"); Text("Choose turns").tag("custom") }.pickerStyle(.radioGroup).labelsHidden()
                if !loaded { ProgressView().controlSize(.small) }
                else if mode == "latest" {
                    Picker("Turns", selection: $limitChoice) { ForEach(limitChoices, id: \.self) { Text(limitLabel($0)).tag($0) } }.pickerStyle(.segmented).frame(width: 260)
                } else {
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
                Toggle("Include token usage and price", isOn: $includeTokenAndPrice)
            }.padding(12).glassBar()
            Spacer(minLength: 0)
            Button { Task { await export() } } label: {
                HStack { Image(systemName: "arrow.down.to.line"); Text(busy ? "Exporting…" : "Export HTML") }
            }.buttonStyle(.borderedProminent).disabled(busy || !loaded || (mode == "custom" && selected.isEmpty))
        }.padding(24).frame(width: 420, height: 460).glassBar()
            .task { await load() }
    }
    private func load() async {
        do { let result = try await state.exportTurns(); turns = result.turns; loaded = true }
        catch { failure = error.localizedDescription }
    }
    private func export() async {
        busy = true; failure = nil; state.error = nil; defer { busy = false }
        if mode == "latest" {
            await state.exportTranscript(mode: "latest", limit: limitChoice == 0 ? nil : limitChoice, includeTokenAndPrice: includeTokenAndPrice)
        } else {
            await state.exportTranscript(mode: "selected", limit: nil, turnIds: Array(selected), includeTokenAndPrice: includeTokenAndPrice)
        }
        if state.error == nil { dismiss() } else { failure = state.error; state.error = nil }
    }
}
