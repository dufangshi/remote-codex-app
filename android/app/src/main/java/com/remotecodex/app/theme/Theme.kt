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
    appBg = Color(0xFF0D0C08),
    panel = Color(0xFF15140F),
    surface = Color(0xFF12100D),
    surfaceStrong = Color(0xFF1C1B15),
    muted = Color(0xFF22201B),
    hover = Color(0xFF25231C),
    fg = Color(0xFFEDEBE5),
    fgSoft = Color(0xFFBDBAB2),
    fgMuted = Color(0xFF8F8C83),
    border = Color(0xFF2C2A23),
    borderStrong = Color(0xFF3A382F),
    accentSoft = Color(0xFF30220D),
    accentBorder = Color(0xFF79561E),
    accentStrong = Color(0xFFF6C071),
    accentSolid = Color(0xFFEAAA40),
    accentSolidHover = Color(0xFFF8BB5E),
    accentSolidFg = Color(0xFF1A1207),
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
    appBg = Color(0xFFEFF4F6),
    panel = Color(0xFFF8FCFD),
    surface = Color(0xFFE9F0F2),
    surfaceStrong = Color(0xFFDFE8EB),
    muted = Color(0xFFD6E0E3),
    hover = Color(0xFFDAE7EC),
    fg = Color(0xFF151C1F),
    fgSoft = Color(0xFF39444B),
    fgMuted = Color(0xFF59656D),
    border = Color(0xFFC4D0D4),
    borderStrong = Color(0xFFA7B8BD),
    accentSoft = Color(0xFFF8E5CB),
    accentBorder = Color(0xFFBC8B3F),
    accentStrong = Color(0xFF874E00),
    accentSolid = Color(0xFFD1900B),
    accentSolidHover = Color(0xFFC67D00),
    accentSolidFg = Color(0xFF1A1207),
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
