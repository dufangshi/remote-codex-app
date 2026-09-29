import SwiftUI

extension Int { var clampedFontSize: Int { (12...22).contains(self) ? self : 16 } }
struct TextSizePreference: DynamicProperty {
    @AppStorage("native-font-size") private var value = 16
    func points(_ base: CGFloat) -> CGFloat { base * CGFloat(value.clampedFontSize) / 16 }
}

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
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(8).contentShape(RoundedRectangle(cornerRadius: 8))
            .background(selected ? Palette.accent.opacity(0.12) : configuration.isPressed || hovered ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(selected ? Palette.accent : Palette.muted)
            .onHover { hovered = $0 }
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
    func composerMenuSurface(radius: CGFloat = 12) -> some View {
        self.background(Palette.panel, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.border))
            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }
    /// Edge-to-edge translucent chrome for full-bleed bars (rail, topbar, sidebar)
    /// that have no visible rounded edge to frame.
    func glassBar() -> some View { modifier(GlassBar()) }
    /// Floating, rounded glass surface with a frosted top-edge highlight, for
    /// popovers, sheets and other chrome that visibly floats above content.
    func glassPanel(cornerRadius: CGFloat = 16) -> some View { modifier(GlassPanel(cornerRadius: cornerRadius)) }
}

private struct GlassBar: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency { content.background(Palette.chrome) }
        else { glassBackground(content) }
    }
    @ViewBuilder private func glassBackground(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { content.glassEffect(.regular, in: Rectangle()) }
        else { content.background(.regularMaterial) }
        #else
        content.background(.regularMaterial)
        #endif
    }
}

private struct GlassPanel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius) }
    private var highlight: LinearGradient { LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0)], startPoint: .top, endPoint: .bottom) }
    func body(content: Content) -> some View {
        Group { if reduceTransparency { content.background(Palette.panel, in: shape) } else { glassBackground(content) } }
            .overlay(shape.strokeBorder(reduceTransparency ? AnyShapeStyle(Palette.border) : AnyShapeStyle(highlight), lineWidth: 1))
    }
    @ViewBuilder private func glassBackground(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { content.glassEffect(.regular, in: shape) }
        else { content.background(.regularMaterial, in: shape) }
        #else
        content.background(.regularMaterial, in: shape)
        #endif
    }
}

struct SlashToolIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width / 16, y: rect.minY + y * rect.height / 16) }
        p.move(to: point(10.75, 2.5)); p.addLine(to: point(5.25, 13.5))
        p.move(to: point(4.25, 5.25)); p.addLine(to: point(6.5, 5.25))
        p.move(to: point(9.5, 10.75)); p.addLine(to: point(11.75, 10.75))
        return p
    }
}

/// Title + circular close button, for the native Settings/Share/Permissions/
/// Transcript sheets that replaced the old embedded web dialog.
struct SheetHeader: View {
    let title: String
    var subtitle: String? = nil
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(title).font(.system(size: 20, weight: .bold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).padding(7)
                    .background(Palette.surface, in: Circle()).accessibilityLabel("Close")
            }
            if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.muted) }
        }
    }
}

/// A selectable card row, used instead of raw AppKit radio buttons for a
/// more deliberately-designed look matching the web app's option lists.
struct SelectableRow: View {
    let title: String
    var subtitle: String? = nil
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Palette.accent : Palette.muted).font(.system(size: 16)).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                }
                Spacer(minLength: 0)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Palette.accent.opacity(0.10) : Palette.surface, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Palette.accent.opacity(0.5) : Palette.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

/// A checkbox-style row for multi-select lists (e.g. picking transcript turns).
struct SelectableCheckRow: View {
    let title: String
    var subtitle: String? = nil
    let checked: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? Palette.accent : Palette.muted).font(.system(size: 15)).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 6).padding(.horizontal, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Small rounded-capsule status label, e.g. "Live" / "Snapshot" on a share link.
struct StatusBadge: View {
    let text: String
    var tint: Color = Palette.accent
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.5)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule()).foregroundStyle(tint)
    }
}

/// A rounded card grouping related content, for sheet sections.
struct SheetCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
    }
}

struct MenuRowStyle: ButtonStyle {
    var selected = false
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14)).padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .foregroundStyle(selected ? Palette.accent : Palette.text)
            .background(hovered || configuration.isPressed ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
            .onHover { hovered = $0 }
    }
}
