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
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(title: "Download transcript", subtitle: "Save a readable copy of your conversation as HTML.", close: { dismiss() })
            if let failure { Text(failure).font(.system(size: 12)).foregroundStyle(.red) }
            SheetCard {
                SelectableRow(title: "Latest turns", selected: mode == "latest") { mode = "latest" }
                if mode == "latest" {
                    HStack(spacing: 6) {
                        ForEach(limitChoices, id: \.self) { value in
                            Button(limitLabel(value)) { limitChoice = value }
                                .buttonStyle(WorkbenchButton(selected: limitChoice == value)).frame(maxWidth: .infinity)
                        }
                    }.padding(.leading, 26)
                }
                SelectableRow(title: "Choose turns", selected: mode == "custom") { mode = "custom" }
                if mode == "custom" {
                    if !loaded { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
                    else {
                        HStack { Text("\(selected.count) selected").font(.system(size: 11)).foregroundStyle(Palette.muted); Spacer(); Button("Clear selection") { selected.removeAll() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent) }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(turns) { turn in
                                    SelectableCheckRow(title: "Turn \(turn.turnNumber)", subtitle: turn.userPromptPreview?.isEmpty == false ? turn.userPromptPreview! : "No prompt text", checked: selected.contains(turn.turnId)) {
                                        if selected.contains(turn.turnId) { selected.remove(turn.turnId) } else { selected.insert(turn.turnId) }
                                    }
                                }
                            }
                        }.frame(maxHeight: 140).background(Palette.background, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Divider().overlay(Palette.border)
                Toggle("Include token usage and price", isOn: $includeTokenAndPrice)
            }
            Spacer(minLength: 0)
            Button { Task { await export() } } label: {
                HStack { Image(systemName: "arrow.down.to.line"); Text(busy ? "Exporting…" : "Export HTML") }
                    .frame(maxWidth: .infinity).padding(.vertical, 2)
            }.buttonStyle(.borderedProminent).tint(Palette.accent).controlSize(.large)
                .disabled(busy || (mode == "custom" && (!loaded || selected.isEmpty)))
        }.padding(24).frame(width: 420, height: 480).glassBar()
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
