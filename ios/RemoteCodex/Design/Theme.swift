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
        appBg: Color(hex: 0x0D0C08),
        panel: Color(hex: 0x15140F),
        surface: Color(hex: 0x12100D),
        surfaceStrong: Color(hex: 0x1C1B15),
        muted: Color(hex: 0x22201B),
        hover: Color(hex: 0x25231C),
        fg: Color(hex: 0xEDEBE5),
        fgSoft: Color(hex: 0xBDBAB2),
        fgMuted: Color(hex: 0x8F8C83),
        border: Color(hex: 0x2C2A23),
        borderStrong: Color(hex: 0x3A382F),
        accentSoft: Color(hex: 0x30220D),
        accentBorder: Color(hex: 0x79561E),
        accentStrong: Color(hex: 0xF6C071),
        accentSolid: Color(hex: 0xEAAA40),
        accentSolidHover: Color(hex: 0xF8BB5E),
        accentSolidFg: Color(hex: 0x1A1207),
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
        appBg: Color(hex: 0xEFF4F6),
        panel: Color(hex: 0xF8FCFD),
        surface: Color(hex: 0xE9F0F2),
        surfaceStrong: Color(hex: 0xDFE8EB),
        muted: Color(hex: 0xD6E0E3),
        hover: Color(hex: 0xDAE7EC),
        fg: Color(hex: 0x151C1F),
        fgSoft: Color(hex: 0x39444B),
        fgMuted: Color(hex: 0x59656D),
        border: Color(hex: 0xC4D0D4),
        borderStrong: Color(hex: 0xA7B8BD),
        accentSoft: Color(hex: 0xF8E5CB),
        accentBorder: Color(hex: 0xBC8B3F),
        accentStrong: Color(hex: 0x874E00),
        accentSolid: Color(hex: 0xD1900B),
        accentSolidHover: Color(hex: 0xC67D00),
        accentSolidFg: Color(hex: 0x1A1207),
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
