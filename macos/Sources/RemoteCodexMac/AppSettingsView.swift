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
            SheetHeader(title: "Settings", close: { dismiss() })
            SheetCard {
                Text("Appearance").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                HStack(spacing: 8) {
                    ForEach([("system", "System"), ("light", "Light"), ("dark", "Dark")], id: \.0) { value, label in
                        Button(label) { appearance = value }
                            .buttonStyle(WorkbenchButton(selected: appearance == value)).frame(maxWidth: .infinity)
                    }
                }
            }
            SheetCard {
                HStack {
                    Text("Text size").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                    Spacer()
                    Text("\(fontSize)pt").font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
                }
                Stepper("", value: Binding(get: { fontSize }, set: { fontSize = $0.clampedFontSize }), in: 12...22).labelsHidden()
            }
            SheetCard {
                Toggle("Auto-collapse completed turns", isOn: $autoCollapse)
                Divider().overlay(Palette.border)
                Toggle("Show reasoning summaries", isOn: $reasoningSummaries)
            }
        }.padding(24).frame(width: 420).glassBar()
    }
}
