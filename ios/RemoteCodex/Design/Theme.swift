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
    let accentSoft: Color
    let accentBorder: Color
    let accentStrong: Color
    let accentSolid: Color
    let accentSolidFg: Color
    let dangerBg: Color
    let dangerBorder: Color
    let dangerFg: Color
    let successFg: Color
    let warningFg: Color
    let overlay: Color

    static let dark = RcColors(
        appBg: Color(hex: 0x24231F),
        panel: Color(hex: 0x2E2D28),
        surface: Color(hex: 0x2A2924),
        surfaceStrong: Color(hex: 0x36352F),
        muted: Color(hex: 0x3D3C35),
        hover: Color(hex: 0x403E36),
        fg: Color(hex: 0xF1EFE8),
        fgSoft: Color(hex: 0xC9C6BB),
        fgMuted: Color(hex: 0xA3A090),
        border: Color(hex: 0x48473E),
        accentSoft: Color(hex: 0x3A3420),
        accentBorder: Color(hex: 0x8A6B2A),
        accentStrong: Color(hex: 0xF0C56A),
        accentSolid: Color(hex: 0xE0B14A),
        accentSolidFg: Color(hex: 0x2F2A16),
        dangerBg: Color(hex: 0x3A2220),
        dangerBorder: Color(hex: 0x7A3A34),
        dangerFg: Color(hex: 0xE8A39A),
        successFg: Color(hex: 0x8FD4B0),
        warningFg: Color(hex: 0xF0C56A),
        overlay: Color.black.opacity(0.72)
    )

    static let light = RcColors(
        appBg: Color(hex: 0xF3F6F7),
        panel: Color(hex: 0xFBFCFD),
        surface: Color(hex: 0xEEF2F5),
        surfaceStrong: Color(hex: 0xE4EAEF),
        muted: Color(hex: 0xDCE3E9),
        hover: Color(hex: 0xE4EBF1),
        fg: Color(hex: 0x2A3340),
        fgSoft: Color(hex: 0x4B5565),
        fgMuted: Color(hex: 0x667084),
        border: Color(hex: 0xCDD6DE),
        accentSoft: Color(hex: 0xF6E7C4),
        accentBorder: Color(hex: 0xC3922E),
        accentStrong: Color(hex: 0x8A5A12),
        accentSolid: Color(hex: 0xD4A017),
        accentSolidFg: Color(hex: 0x2F2A16),
        dangerBg: Color(hex: 0xF8E4E1),
        dangerBorder: Color(hex: 0xE2B4AD),
        dangerFg: Color(hex: 0x8A2E28),
        successFg: Color(hex: 0x2F7A56),
        warningFg: Color(hex: 0x8A5A12),
        overlay: Color.black.opacity(0.35)
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
    static let touch: CGFloat = 44
}
