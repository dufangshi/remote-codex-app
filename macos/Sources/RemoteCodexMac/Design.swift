import SwiftUI

enum Palette {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let n = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255, alpha: 1)
        })
    }
    static let background = adaptive(0xE1E5E1, 0x0C0F11)
    static let panel = adaptive(0xEBEEEB, 0x0F1317)
    static let chrome = adaptive(0xD6DCD7, 0x141A1F)
    static let surface = adaptive(0xE5E9E5, 0x1C242A)
    static let border = adaptive(0xC3CCC5, 0x263038)
    static let text = adaptive(0x121416, 0xF4F7F6)
    static let muted = adaptive(0x5B6269, 0xA2AFB9)
    static let accent = adaptive(0x008B53, 0x00CC76)
    static let selected = adaptive(0xC7D8CF, 0x263943)
}
struct WorkbenchButton: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(8).contentShape(RoundedRectangle(cornerRadius: 8))
            .background(selected ? Palette.accent.opacity(0.12) : configuration.isPressed ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(selected ? Palette.accent : Palette.muted)
    }
}
struct IconButton: View {
    let title: String
    let icon: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 17)).frame(width: 24, height: 24) }
            .buttonStyle(WorkbenchButton(selected: selected)).help(title).accessibilityLabel(title)
    }
}

struct InlineError: View {
    let message: String
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.10))
    }
}

extension View {
    @ViewBuilder func controlGlass() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        #else
        self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        #endif
    }
}
