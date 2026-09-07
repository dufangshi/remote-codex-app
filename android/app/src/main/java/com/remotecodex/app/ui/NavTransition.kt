package com.remotecodex.app.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlin.math.max

private val slideSpring = spring<Float>(
    dampingRatio = 0.9f,
    stiffness = Spring.StiffnessMediumLow,
)

@Composable
fun InteractiveStackHost(
    route: AppRoute,
    previous: AppRoute?,
    canSwipeBack: Boolean,
    navigatingForward: Boolean,
    popRequest: Int,
    onPopCommitted: () -> Unit,
    onRequestPop: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable (AppRoute) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val offset = remember { Animatable(0f) }
    var widthPx by remember { mutableFloatStateOf(1f) }
    var booted by remember { mutableStateOf(false) }
    var animatingPop by remember { mutableStateOf(false) }
    val density = LocalDensity.current
    val width = max(widthPx, 1f)

    LaunchedEffect(route) {
        if (!booted) {
            booted = true
            offset.snapTo(0f)
            animatingPop = false
            return@LaunchedEffect
        }
        if (animatingPop) {
            offset.snapTo(0f)
            animatingPop = false
            return@LaunchedEffect
        }
        if (navigatingForward) {
            offset.snapTo(width)
            offset.animateTo(0f, slideSpring)
        } else {
            offset.snapTo(0f)
        }
    }

    LaunchedEffect(popRequest) {
        if (popRequest == 0) return@LaunchedEffect
        animatingPop = true
        try {
            offset.animateTo(max(widthPx, 1f), slideSpring)
        } catch (cancelled: CancellationException) {
            onPopCommitted()
            offset.snapTo(0f)
            animatingPop = false
            throw cancelled
        }
        onPopCommitted()
        offset.snapTo(0f)
        animatingPop = false
    }

    val x = offset.value
    val progress = (x / width).coerceIn(0f, 1f)
    Box(
        modifier
            .fillMaxSize()
            .onSizeChanged { widthPx = it.width.toFloat().coerceAtLeast(1f) },
    ) {
        if (x > 0.5f) {
            previous?.let { behind ->
                Box(
                    Modifier
                        .fillMaxSize()
                        .graphicsLayer {
                            translationX = -width * 0.3f * (1f - progress)
                            scaleX = 0.96f + 0.04f * progress
                            scaleY = 0.96f + 0.04f * progress
                            transformOrigin = TransformOrigin(0f, 0.5f)
                        },
                ) {
                    key(behind) { content(behind) }
                    Box(
                        Modifier
                            .fillMaxSize()
                            .background(Color.Black.copy(alpha = 0.28f * (1f - progress))),
                    )
                }
            }
        }
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer {
                    translationX = x
                    shadowElevation = if (x > 0f) 24f else 0f
                },
        ) {
            key(route) { content(route) }
        }
        if (canSwipeBack && !animatingPop) {
            Box(
                Modifier
                    .align(Alignment.CenterStart)
                    .padding(top = 52.dp)
                    .fillMaxHeight()
                    .width(28.dp)
                    .pointerInput(route, canSwipeBack, width) {
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            val tracker = VelocityTracker()
                            tracker.addPosition(down.uptimeMillis, down.position)
                            val completed = drag(down.id) { change ->
                                tracker.addPosition(change.uptimeMillis, change.position)
                                val next = (offset.value + change.positionChange().x).coerceIn(0f, width)
                                change.consume()
                                scope.launch { offset.snapTo(next) }
                            }
                            if (!completed) {
                                scope.launch { offset.animateTo(0f, slideSpring) }
                                return@awaitEachGesture
                            }
                            val velocity = tracker.calculateVelocity().x
                            val translation = offset.value
                            val shouldPop = translation > width * 0.28f || velocity > with(density) { 420.dp.toPx() }
                            if (shouldPop) {
                                onRequestPop()
                            } else {
                                scope.launch { offset.animateTo(0f, slideSpring) }
                            }
                        }
                    },
            )
        }
    }
}
