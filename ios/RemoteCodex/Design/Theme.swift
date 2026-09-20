import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
    var subtitle: String {
        switch self {
        case .light: return "Always use the bright theme."
        case .dark: return "Always use the dark theme."
        case .system: return "Follow the operating system appearance."
        }
    }
}

struct RcColors {
    let appBg: Color
    let panel: Color
    let surface: Color
    let surfaceStrong: Color
    let muted: Color
    let hover: Color
    let fg: Color
    let fgSoft: Color
    let fgMuted: Color
    let border: Color
    let borderStrong: Color
    let accentSoft: Color
    let accentBorder: Color
    let accentStrong: Color
    let accentSolid: Color
    let accentSolidHover: Color
    let accentSolidFg: Color
    let dangerBg: Color
    let dangerBorder: Color
    let dangerFg: Color
    let successFg: Color
    let successBg: Color
    let warningFg: Color
    let warningBg: Color
    let warningBorder: Color
    let overlay: Color

    static let dark = RcColors(
        appBg: Color(hex: 0x0C0F11),
        panel: Color(hex: 0x0F1317),
        surface: Color(hex: 0x1C242A),
        surfaceStrong: Color(hex: 0x1C242A),
        muted: Color(hex: 0x1C242A),
        hover: Color(hex: 0x202A30),
        fg: Color(hex: 0xF4F7F6),
        fgSoft: Color(hex: 0xC1CAD1),
        fgMuted: Color(hex: 0xA2AFB9),
        border: Color(hex: 0x263038),
        borderStrong: Color(hex: 0x36434D),
        accentSoft: Color(hex: 0x102B23),
        accentBorder: Color(hex: 0x215240),
        accentStrong: Color(hex: 0x00CC76),
        accentSolid: Color(hex: 0x00CC76),
        accentSolidHover: Color(hex: 0x16DE89),
        accentSolidFg: Color(hex: 0x082016),
        dangerBg: Color(hex: 0xEF656B, alpha: 0.13),
        dangerBorder: Color(hex: 0xEF656B, alpha: 0.34),
        dangerFg: Color(hex: 0xFFC2C0),
        successFg: Color(hex: 0x98DDB4),
        successBg: Color(hex: 0x5ABB88, alpha: 0.13),
        warningFg: Color(hex: 0xFFD69A),
        warningBg: Color(hex: 0xEAAA40, alpha: 0.13),
        warningBorder: Color(hex: 0xEAAA40, alpha: 0.34),
        overlay: Color(hex: 0x040402, alpha: 0.78)
    )

    static let light = RcColors(
        appBg: Color(hex: 0xE0E4E0),
        panel: Color(hex: 0xEAEEEA),
        surface: Color(hex: 0xE5E9E5),
        surfaceStrong: Color(hex: 0xD9DED9),
        muted: Color(hex: 0xD2D7D2),
        hover: Color(hex: 0xCFD4CF),
        fg: Color(hex: 0x121416),
        fgSoft: Color(hex: 0x5B6269),
        fgMuted: Color(hex: 0x555F58),
        border: Color(hex: 0xC3C8C3),
        borderStrong: Color(hex: 0xADB3AE),
        accentSoft: Color(hex: 0xE5F8F0),
        accentBorder: Color(hex: 0xA4CDBB),
        accentStrong: Color(hex: 0x007849),
        accentSolid: Color(hex: 0x008B53),
        accentSolidHover: Color(hex: 0x007849),
        accentSolidFg: Color(hex: 0xF6F9F6),
        dangerBg: Color(hex: 0xBD2D3E, alpha: 0.10),
        dangerBorder: Color(hex: 0xBD2D3E, alpha: 0.24),
        dangerFg: Color(hex: 0x830A21),
        successFg: Color(hex: 0x004721),
        successBg: Color(hex: 0x5ABB88, alpha: 0.10),
        warningFg: Color(hex: 0x683700),
        warningBg: Color(hex: 0xD1900B, alpha: 0.10),
        warningBorder: Color(hex: 0xD1900B, alpha: 0.24),
        overlay: Color(hex: 0x11171B, alpha: 0.46)
    )
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Rc {
    static let radius: CGFloat = 6
    static let panelRadius: CGFloat = 8
    static let touch: CGFloat = 44
}
