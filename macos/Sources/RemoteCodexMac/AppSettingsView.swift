import SwiftUI
import RemoteCodexCore

/// Local preferences only - the same UserDefaults keys the old WebView-based
/// settings sheet used to persist (see the former SettingsBrowser.persistPreferences).
struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("native-font-size") private var fontSize = 16
    @AppStorage("native-auto-collapse") private var autoCollapse = true
    @AppStorage("native-reasoning-summaries") private var reasoningSummaries = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Settings").font(.title2.bold()); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            Form {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Stepper("Text size: \(fontSize)pt", value: Binding(
                    get: { fontSize }, set: { fontSize = $0.clampedFontSize }
                ), in: 12...22)
                Toggle("Auto-collapse completed turns", isOn: $autoCollapse)
                Toggle("Show reasoning summaries", isOn: $reasoningSummaries)
            }
        }.padding(28).frame(width: 420).glassBar()
    }
}
