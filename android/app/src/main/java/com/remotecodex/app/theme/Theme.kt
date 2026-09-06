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
    val warningFg: Color,
    val warningBg: Color,
    val warningBorder: Color,
    val overlay: Color,
)

val DarkColors = RcColors(
    appBg = Color(0xFF24231F),
    panel = Color(0xFF2E2D28),
    surface = Color(0xFF2A2924),
    surfaceStrong = Color(0xFF36352F),
    muted = Color(0xFF3D3C35),
    hover = Color(0xFF403E36),
    fg = Color(0xFFF1EFE8),
    fgSoft = Color(0xFFC9C6BB),
    fgMuted = Color(0xFFA3A090),
    border = Color(0xFF48473E),
    borderStrong = Color(0xFF57564C),
    accentSoft = Color(0xFF3A3420),
    accentBorder = Color(0xFF8A6B2A),
    accentStrong = Color(0xFFF0C56A),
    accentSolid = Color(0xFFE0B14A),
    accentSolidHover = Color(0xFFE8C05C),
    accentSolidFg = Color(0xFF2F2A16),
    dangerBg = Color(0xFF3A2220),
    dangerBorder = Color(0xFF7A3A34),
    dangerFg = Color(0xFFE8A39A),
    successFg = Color(0xFF8FD4B0),
    warningFg = Color(0xFFF0C56A),
    warningBg = Color(0xFF3A3420),
    warningBorder = Color(0xFF8A6B2A),
    overlay = Color(0xC71A1916),
)

val LightColors = RcColors(
    appBg = Color(0xFFF3F6F7),
    panel = Color(0xFFFBFCFD),
    surface = Color(0xFFEEF2F5),
    surfaceStrong = Color(0xFFE4EAEF),
    muted = Color(0xFFDCE3E9),
    hover = Color(0xFFE4EBF1),
    fg = Color(0xFF2A3340),
    fgSoft = Color(0xFF4B5565),
    fgMuted = Color(0xFF667084),
    border = Color(0xFFCDD6DE),
    borderStrong = Color(0xFFB3BEC8),
    accentSoft = Color(0xFFF6E7C4),
    accentBorder = Color(0xFFC3922E),
    accentStrong = Color(0xFF8A5A12),
    accentSolid = Color(0xFFD4A017),
    accentSolidHover = Color(0xFFC3922E),
    accentSolidFg = Color(0xFF2F2A16),
    dangerBg = Color(0xFFF8E4E1),
    dangerBorder = Color(0xFFE2B4AD),
    dangerFg = Color(0xFF8A2E28),
    successFg = Color(0xFF2F7A56),
    warningFg = Color(0xFF8A5A12),
    warningBg = Color(0xFFF6E7C4),
    warningBorder = Color(0xFFE2C37A),
    overlay = Color(0x751A2330),
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
