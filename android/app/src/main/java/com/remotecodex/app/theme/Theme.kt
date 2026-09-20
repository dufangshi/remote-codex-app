package com.remotecodex.app.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

enum class ThemeMode { System, Light, Dark }

@Immutable
data class RcColors(
    val appBg: Color,
    val panel: Color,
    val surface: Color,
    val surfaceStrong: Color,
    val muted: Color,
    val hover: Color,
    val fg: Color,
    val fgSoft: Color,
    val fgMuted: Color,
    val border: Color,
    val borderStrong: Color,
    val accentSoft: Color,
    val accentBorder: Color,
    val accentStrong: Color,
    val accentSolid: Color,
    val accentSolidHover: Color,
    val accentSolidFg: Color,
    val dangerBg: Color,
    val dangerBorder: Color,
    val dangerFg: Color,
    val successFg: Color,
    val successBg: Color,
    val warningFg: Color,
    val warningBg: Color,
    val warningBorder: Color,
    val overlay: Color,
)

val DarkColors = RcColors(
    appBg = Color(0xFF0C0F11),
    panel = Color(0xFF0F1317),
    surface = Color(0xFF1C242A),
    surfaceStrong = Color(0xFF1C242A),
    muted = Color(0xFF1C242A),
    hover = Color(0xFF202A30),
    fg = Color(0xFFF4F7F6),
    fgSoft = Color(0xFFC1CAD1),
    fgMuted = Color(0xFFA2AFB9),
    border = Color(0xFF263038),
    borderStrong = Color(0xFF36434D),
    accentSoft = Color(0xFF102B23),
    accentBorder = Color(0xFF215240),
    accentStrong = Color(0xFF00CC76),
    accentSolid = Color(0xFF00CC76),
    accentSolidHover = Color(0xFF16DE89),
    accentSolidFg = Color(0xFF082016),
    dangerBg = Color(0x21EF656B),
    dangerBorder = Color(0x57EF656B),
    dangerFg = Color(0xFFFFC2C0),
    successFg = Color(0xFF98DDB4),
    successBg = Color(0x215ABB88),
    warningFg = Color(0xFFFFD69A),
    warningBg = Color(0x21EAAA40),
    warningBorder = Color(0x57EAAA40),
    overlay = Color(0xC7040402),
)

val LightColors = RcColors(
    appBg = Color(0xFFE0E4E0),
    panel = Color(0xFFEAEEEA),
    surface = Color(0xFFE5E9E5),
    surfaceStrong = Color(0xFFD9DED9),
    muted = Color(0xFFD2D7D2),
    hover = Color(0xFFCFD4CF),
    fg = Color(0xFF121416),
    fgSoft = Color(0xFF5B6269),
    fgMuted = Color(0xFF555F58),
    border = Color(0xFFC3C8C3),
    borderStrong = Color(0xFFADB3AE),
    accentSoft = Color(0xFFE5F8F0),
    accentBorder = Color(0xFFA4CDBB),
    accentStrong = Color(0xFF007849),
    accentSolid = Color(0xFF008B53),
    accentSolidHover = Color(0xFF007849),
    accentSolidFg = Color(0xFFF6F9F6),
    dangerBg = Color(0x1ABD2D3E),
    dangerBorder = Color(0x3DBD2D3E),
    dangerFg = Color(0xFF830A21),
    successFg = Color(0xFF004721),
    successBg = Color(0x1A5ABB88),
    warningFg = Color(0xFF683700),
    warningBg = Color(0x1AD1900B),
    warningBorder = Color(0x3DD1900B),
    overlay = Color(0x7511171B),
)

val LocalRcColors = staticCompositionLocalOf { DarkColors }

val TopbarHeight = 56.dp
val TouchTarget = 44.dp
val PageGutter = 16.dp

@Composable
fun RemoteCodexTheme(
    mode: ThemeMode,
    content: @Composable () -> Unit,
) {
    val dark = when (mode) {
        ThemeMode.Dark -> true
        ThemeMode.Light -> false
        ThemeMode.System -> isSystemInDarkTheme()
    }
    CompositionLocalProvider(LocalRcColors provides if (dark) DarkColors else LightColors) {
        content()
    }
}

val rcColors: RcColors
    @Composable get() = LocalRcColors.current
