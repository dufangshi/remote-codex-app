package com.remotecodex.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.remotecodex.app.theme.LocalRcColors
import com.remotecodex.app.theme.TouchTarget
import com.remotecodex.app.theme.rcColors

val RcRadius = RoundedCornerShape(6.dp)

@Composable
fun RcPage(
    modifier: Modifier = Modifier,
    scroll: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = rcColors
    val columnModifier = modifier
        .fillMaxSize()
        .background(colors.appBg)
        .statusBarsPadding()
        .navigationBarsPadding()
        .imePadding()
    if (scroll) {
        Column(
            modifier = columnModifier.verticalScroll(rememberScrollState()),
            content = content,
        )
    } else {
        Column(modifier = columnModifier, content = content)
    }
}

@Composable
fun ProductHeader(
    title: String,
    modifier: Modifier = Modifier,
    backLabel: String? = null,
    onBack: (() -> Unit)? = null,
    onOpenNav: (() -> Unit)? = null,
    onOpenAccount: (() -> Unit)? = null,
    accountLabel: String? = null,
    actions: @Composable RowScope.() -> Unit = {},
) {
    val colors = rcColors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(colors.appBg.copy(alpha = 0.94f))
            .border(width = 0.dp, color = colors.border)
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .height(TouchTarget + 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onOpenNav != null) {
            IconButton(label = "Open Navigation", onClick = onOpenNav) {
                Icon(Icons.Filled.Menu, contentDescription = null, tint = colors.fg, modifier = Modifier.size(18.dp))
            }
        }
        if (onBack != null) {
            IconButton(label = backLabel ?: "Back", onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = colors.fg, modifier = Modifier.size(18.dp))
            }
        }
        Text(
            text = title,
            color = colors.fg,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 8.dp)
                .testTag("pageTitle"),
        )
        actions()
        if (onOpenAccount != null && !accountLabel.isNullOrBlank()) {
            Box(
                modifier = Modifier
                    .size(TouchTarget)
                    .clip(CircleShape)
                    .border(1.dp, colors.border, CircleShape)
                    .background(colors.surfaceStrong)
                    .clickable(onClick = onOpenAccount)
                    .semantics { contentDescription = "Relay account menu for $accountLabel" }
                    .testTag("accountMenuButton"),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = accountLabel.take(2).uppercase(),
                    color = colors.fg,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
    Box(
        Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(colors.border),
    )
}

@Composable
fun IconButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    val colors = rcColors
    Box(
        modifier = modifier
            .size(TouchTarget)
            .clip(RcRadius)
            .clickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = label }
            .testTag(label),
        contentAlignment = Alignment.Center,
    ) {
        content()
    }
}

@Composable
fun PrimaryButton(
    label: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    tag: String = label,
    leading: @Composable (() -> Unit)? = null,
    onClick: () -> Unit,
) {
    val colors = rcColors
    val bg = if (enabled) colors.accentSolid else colors.muted
    val fg = if (enabled) colors.accentSolidFg else colors.fgMuted
    Row(
        modifier = modifier
            .height(TouchTarget)
            .clip(RcRadius)
            .background(bg)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp)
            .testTag(tag)
            .semantics { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        if (leading != null) {
            leading()
            Spacer(Modifier.width(8.dp))
        }
        Text(label, color = fg, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun SecondaryButton(
    label: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    tag: String = label,
    leading: @Composable (() -> Unit)? = null,
    onClick: () -> Unit,
) {
    val colors = rcColors
    Row(
        modifier = modifier
            .height(TouchTarget)
            .clip(RcRadius)
            .border(1.dp, colors.border, RcRadius)
            .background(colors.surface)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp)
            .testTag(tag)
            .semantics { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        if (leading != null) {
            leading()
            Spacer(Modifier.width(8.dp))
        }
        Text(label, color = colors.fg, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun RcField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    password: Boolean = false,
    enabled: Boolean = true,
    singleLine: Boolean = true,
    description: String? = null,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    tag: String = label,
) {
    val colors = rcColors
    var visible by remember { mutableStateOf(false) }
    Column(modifier) {
        Text(label, color = colors.fgSoft, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        Spacer(Modifier.height(8.dp))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(TouchTarget)
                .clip(RcRadius)
                .border(1.dp, colors.border, RcRadius)
                .background(colors.surface)
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                enabled = enabled,
                singleLine = singleLine,
                textStyle = TextStyle(color = colors.fg, fontSize = 14.sp),
                cursorBrush = SolidColor(colors.accentSolid),
                visualTransformation = if (password && !visible) PasswordVisualTransformation() else VisualTransformation.None,
                keyboardOptions = keyboardOptions,
                keyboardActions = keyboardActions,
                modifier = Modifier
                    .weight(1f)
                    .testTag(tag)
                    .semantics { contentDescription = label },
                decorationBox = { inner ->
                    if (value.isEmpty() && placeholder.isNotEmpty()) {
                        Box {
                            Text(placeholder, color = colors.fgMuted, fontSize = 14.sp)
                            inner()
                        }
                    } else {
                        inner()
                    }
                },
            )
            if (password) {
                IconButton(label = if (visible) "Hide password" else "Show password", onClick = { visible = !visible }) {
                    Icon(
                        if (visible) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                        contentDescription = null,
                        tint = colors.fgMuted,
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
        }
        if (description != null) {
            Spacer(Modifier.height(6.dp))
            Text(description, color = colors.fgMuted, fontSize = 12.sp)
        }
    }
}

@Composable
fun Notice(text: String, tone: NoticeTone = NoticeTone.Danger, modifier: Modifier = Modifier) {
    val colors = rcColors
    val bg = when (tone) {
        NoticeTone.Danger -> colors.dangerBg
        NoticeTone.Success -> colors.muted
        NoticeTone.Accent -> colors.accentSoft
    }
    val fg = when (tone) {
        NoticeTone.Danger -> colors.dangerFg
        NoticeTone.Success -> colors.successFg
        NoticeTone.Accent -> colors.accentStrong
    }
    val border = when (tone) {
        NoticeTone.Danger -> colors.dangerBorder
        NoticeTone.Success -> colors.border
        NoticeTone.Accent -> colors.accentBorder
    }
    Text(
        text = text,
        color = fg,
        fontSize = 14.sp,
        modifier = modifier
            .fillMaxWidth()
            .clip(RcRadius)
            .border(1.dp, border, RcRadius)
            .background(bg)
            .padding(12.dp)
            .testTag("notice"),
    )
}

enum class NoticeTone { Danger, Success, Accent }

@Composable
fun StatusDot(online: Boolean, modifier: Modifier = Modifier) {
    val colors = rcColors
    Box(
        modifier
            .size(10.dp)
            .clip(CircleShape)
            .background(if (online) colors.successFg else colors.fgMuted),
    )
}

@Composable
fun Mono(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        color = rcColors.fgMuted,
        fontSize = 12.sp,
        fontFamily = FontFamily.Monospace,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier,
    )
}

@Composable
fun ConfirmDialog(
    title: String,
    description: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
    busy: Boolean = false,
) {
    val colors = rcColors
    Box(
        Modifier
            .fillMaxSize()
            .background(colors.overlay)
            .clickable(onClick = onCancel),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .padding(24.dp)
                .widthIn(max = 420.dp)
                .clip(RoundedCornerShape(8.dp))
                .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                .background(colors.panel)
                .clickable(enabled = false, onClick = {})
                .padding(20.dp)
                .testTag("confirmDialog"),
        ) {
            Text(title, color = colors.fg, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(8.dp))
            Text(description, color = colors.fgMuted, fontSize = 14.sp, lineHeight = 20.sp)
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                SecondaryButton("Cancel", modifier = Modifier.weight(1f), tag = "confirmCancel", onClick = onCancel)
                PrimaryButton(if (busy) "Working..." else confirmLabel, enabled = !busy, modifier = Modifier.weight(1f), tag = "confirmOk", onClick = onConfirm)
            }
        }
    }
}

@Composable
fun PromptDialog(
    title: String,
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    onSubmit: () -> Unit,
    onCancel: () -> Unit,
    busy: Boolean = false,
) {
    val colors = rcColors
    Box(
        Modifier
            .fillMaxSize()
            .background(colors.overlay)
            .clickable(onClick = onCancel),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .padding(24.dp)
                .widthIn(max = 420.dp)
                .clip(RoundedCornerShape(8.dp))
                .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                .background(colors.panel)
                .clickable(enabled = false, onClick = {})
                .padding(20.dp),
        ) {
            Text(title, color = colors.fg, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(12.dp))
            RcField(label, value, onValueChange, tag = "dialogField")
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                SecondaryButton("Cancel", modifier = Modifier.weight(1f), onClick = onCancel)
                PrimaryButton(if (busy) "Saving..." else "Save", enabled = !busy && value.isNotBlank(), modifier = Modifier.weight(1f), tag = "dialogSave", onClick = onSubmit)
            }
        }
    }
}

@Composable
fun BrandMark() {
    val colors = rcColors
    Box(
        Modifier
            .size(36.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(colors.accentSoft),
        contentAlignment = Alignment.Center,
    ) {
        Text("RC", color = colors.accentStrong, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun FloatingPanel(
    eyebrow: String,
    title: String,
    description: String,
    backLabel: String,
    onBack: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = rcColors
    RcPage {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 8.dp)
                .clickable(onClick = onBack)
                .padding(8.dp)
                .testTag("floatingBack"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = colors.fgSoft, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(8.dp))
            Text(backLabel, color = colors.fgSoft, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        }
        Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
            Text(eyebrow.uppercase(), color = colors.fgMuted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.sp)
            Spacer(Modifier.height(6.dp))
            Text(title, color = colors.fg, fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(8.dp))
            Text(description, color = colors.fgMuted, fontSize = 14.sp, lineHeight = 22.sp)
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
        Column(Modifier.padding(20.dp), content = content)
    }
}

@Composable
fun MenuSheet(
    title: String,
    subtitle: String,
    onDismiss: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = rcColors
    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .background(colors.overlay.copy(alpha = 0.01f))
                .clickable(onClick = onDismiss),
        )
        Column(
            Modifier
                .padding(start = 12.dp, top = 64.dp)
                .width(256.dp)
                .clip(RoundedCornerShape(8.dp))
                .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                .background(colors.panel)
                .padding(8.dp)
                .testTag("navMenu"),
        ) {
            Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                Text(title, color = colors.fg, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                Text(subtitle, color = colors.fgMuted, fontSize = 12.sp)
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
            Spacer(Modifier.height(4.dp))
            content()
        }
    }
}

@Composable
fun MenuItem(label: String, selected: Boolean = false, onClick: () -> Unit, leading: @Composable (() -> Unit)? = null) {
    val colors = rcColors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RcRadius)
            .background(if (selected) colors.accentSoft else colors.panel)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp)
            .height(TouchTarget)
            .testTag(label),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (leading != null) {
            leading()
            Spacer(Modifier.width(12.dp))
        }
        Text(
            label,
            color = if (selected) colors.accentStrong else colors.fgSoft,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}
