package me.magnum.melonds.ui.common

import android.os.SystemClock
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.unit.dp
import me.magnum.melonds.R
import me.magnum.melonds.ui.theme.watermelon
import kotlin.math.PI
import kotlin.math.sin

class BrandIntroTarget {
    var bounds by mutableStateOf(Rect.Zero)
}

val LocalBrandIntroTarget = staticCompositionLocalOf<BrandIntroTarget?> { null }

@Composable
fun WatermelonLaunchIntro(startedAtMillis: Long?, alternative: Boolean, onFinished: () -> Unit, content: @Composable () -> Unit) {
    var finished by rememberSaveable { mutableStateOf(false) }
    val running = startedAtMillis != null && !finished
    val finish = {
        finished = true
        onFinished()
    }
    val target = remember { BrandIntroTarget() }
    Box(Modifier.fillMaxSize()) {
        CompositionLocalProvider(LocalBrandIntroTarget provides if (running) target else null) {
            content()
        }
        if (running) {
            val duration = if (alternative) 1150 else 1450
            val remaining = remember(startedAtMillis) {
                (duration - (SystemClock.uptimeMillis() - requireNotNull(startedAtMillis))).coerceIn(0L, duration.toLong()).toInt()
            }
            val progress = remember { Animatable(1f - remaining.toFloat() / duration) }
            LaunchedEffect(Unit) {
                progress.animateTo(1f, tween(remaining, easing = LinearEasing))
                finish()
            }
            BackHandler(onBack = finish)
            val face = ImageBitmap.imageResource(if (alternative) R.drawable.watermelon_icon_alt else R.drawable.watermelon_icon_default)
            val cleanPieces = if (alternative) null else ImageBitmap.imageResource(R.drawable.watermelon_intro_pieces)
            val melon = ImageBitmap.imageResource(R.drawable.watermelon_library)
            val melonBounds = melon.watermelonLogoBounds()
            val background = watermelon.bg
            val faceMask = remember { Path().apply { addOval(Rect(-.075f, -.075f, 1.075f, 1.075f)) } }
            val eye = remember {
                Path().apply {
                    moveTo(.106f, .334f)
                    cubicTo(.11f, .1f, .46f, .1f, .467f, .334f)
                    lineTo(.386f, .334f)
                    cubicTo(.38f, .2f, .20f, .2f, .189f, .334f)
                    close()
                }
            }
            val mouth = remember {
                Path().apply {
                    moveTo(.073f, .399f)
                    lineTo(.919f, .399f)
                    lineTo(.946f, .421f)
                    cubicTo(.942f, .674f, .745f, .846f, .496f, .846f)
                    cubicTo(.247f, .846f, .055f, .678f, .044f, .426f)
                    close()
                }
            }
            val pieces = remember { DefaultIntroShapes() }
            Canvas(Modifier.fillMaxSize().pointerInput(Unit) {
                detectTapGestures { finish() }
            }) {
                val t = progress.value
                val travel = FastOutSlowInEasing.transform(t.phase(if (alternative) .56f else .76f, 1f))
                val startEdge = minOf(168.dp.toPx(), size.minDimension * .44f)
                val hasTarget = target.bounds != Rect.Zero
                val endEdge = if (hasTarget) target.bounds.width * melon.width / melonBounds.width else startEdge
                val edge = startEdge + (endEdge - startEdge) * travel
                val start = Offset((size.width - startEdge) / 2, (size.height - startEdge) / 2)
                val end = if (hasTarget) target.bounds.topLeft - Offset(
                    melonBounds.left * endEdge / melon.width,
                    melonBounds.top * endEdge / melon.height,
                ) else start
                val origin = start + (end - start) * travel
                drawRect(background.copy(alpha = 1f - FastOutSlowInEasing.transform(t.phase(if (alternative) .48f else .68f, .94f))))
                translate(origin.x, origin.y) {
                    scale(edge, edge, Offset.Zero) {
                        if (alternative) drawAlternateIntro(face, melon, faceMask, eye, mouth, t)
                        else drawDefaultIntro(face, requireNotNull(cleanPieces), melon, faceMask, pieces, t)
                    }
                }
            }
        }
    }
}

private fun Float.phase(start: Float, end: Float) = ((this - start) / (end - start)).coerceIn(0f, 1f)

private fun DrawScope.drawUnitImage(image: ImageBitmap, alpha: Float = 1f, colorFilter: ColorFilter? = null) {
    if (alpha <= 0f) return
    scale(1f / image.width, 1f / image.height, Offset.Zero) {
        drawImage(image, alpha = alpha, colorFilter = colorFilter)
    }
}

private fun DrawScope.drawAlternateIntro(face: ImageBitmap, melon: ImageBitmap, faceMask: Path, eye: Path, mouth: Path, t: Float) {
    if (t >= .74f) {
        drawUnitImage(melon)
        return
    }
    val reveal = FastOutSlowInEasing.transform(t.phase(.1f, .55f))
    val fold = FastOutSlowInEasing.transform(t.phase(.12f, .65f))
    drawCircle(Color(0xFFEEA336), radius = .575f, center = Offset(.5f, .5f), alpha = 1f - reveal)
    clipPath(faceMask) {
        clipPath(mouth, ClipOp.Difference) { drawUnitImage(face, 1f - reveal) }
    }
    translate(0f, -.123f * reveal) {
        clipPath(mouth) { drawUnitImage(face, 1f - reveal) }
    }
    if (reveal == 0f) return
    repeat(2) { i ->
        val x = if (i == 0) .2865f else .7045f
        translate((.4955f - x) * fold, .253f * fold) {
            rotate((if (i == 0) -180f else 180f) * fold, Offset(x, .247f)) {
                scale(1f + 1.5f * fold, 1f + 1.5f * fold, Offset(x, .247f)) {
                    translate(if (i == 0) 0f else .418f, 0f) {
                        clipPath(eye) {
                            translate(if (i == 0) 0f else -.418f, 0f) {
                                drawUnitImage(face, reveal * (1f - t.phase(.57f, .74f)),
                                    ColorFilter.tint(Color(0xFF326F65).copy(alpha = t.phase(.38f, .7f)), BlendMode.SrcAtop))
                            }
                        }
                    }
                }
            }
        }
    }
    translate(0f, .123f * (1f - reveal)) {
        drawUnitImage(melon, reveal)
    }
}

private class DefaultIntroShapes {
    val topBounds = Rect(.174f, .098f, .827f, .476f)
    val bottomBounds = Rect(.174f, .519f, .824f, .899f)
    val top = Path().apply { addRoundRect(RoundRect(topBounds, CornerRadius(.023f))) }
    val bottom = Path().apply { addRoundRect(RoundRect(bottomBounds, CornerRadius(.023f))) }
    val pen = Path().apply {
        moveTo(.574f, .726f)
        quadraticTo(.566f, .719f, .582f, .699f)
        lineTo(.580f, .669f)
        lineTo(.878f, .142f)
        quadraticTo(.887f, .126f, .900f, .134f)
        quadraticTo(.952f, .153f, .937f, .190f)
        lineTo(.916f, .257f)
        quadraticTo(.890f, .308f, .845f, .306f)
        lineTo(.623f, .668f)
        quadraticTo(.608f, .696f, .594f, .700f)
        lineTo(.582f, .723f)
        close()
    }
}

private fun DrawScope.drawDefaultIntro(face: ImageBitmap, cleanPieces: ImageBitmap, melon: ImageBitmap, faceMask: Path, shapes: DefaultIntroShapes, t: Float) {
    if (t >= .76f) {
        drawUnitImage(melon)
        return
    }
    if (t <= .03f) {
        drawCircle(Color(0xFF62BAB9), radius = .575f, center = Offset(.5f, .5f))
        clipPath(faceMask) { drawUnitImage(face) }
        return
    }
    val reveal = FastOutSlowInEasing.transform(t.phase(.03f, .4f))
    val arrange = FastOutSlowInEasing.transform(t.phase(.06f, .46f))
    val join = FastOutSlowInEasing.transform(t.phase(.49f, .68f))
    val morph = FastOutSlowInEasing.transform(t.phase(.58f, .76f))
    drawCircle(Color(0xFF62BAB9), radius = .575f, center = Offset(.5f, .5f), alpha = 1f - reveal)
    clipPath(faceMask) {
        clipPath(shapes.top, ClipOp.Difference) {
            clipPath(shapes.bottom, ClipOp.Difference) {
                clipPath(shapes.pen, ClipOp.Difference) { drawUnitImage(face, 1f - reveal) }
            }
        }
    }
    repeat(2) { i ->
        val rect = if (i == 0) shapes.topBounds else shapes.bottomBounds
        val path = if (i == 0) shapes.top else shapes.bottom
        val direction = if (i == 0) -1f else 1f
        val destination = Offset((if (i == 0) .6904f else .3156f) - direction * .03f * (1f - join), .572f)
        val offset = (destination - rect.center) * arrange
        translate(offset.x, offset.y) {
            rotate(direction * 90f * arrange, rect.center) {
                val pieceScale = 1f + .13f * arrange
                scale(pieceScale, pieceScale, rect.center) {
                    val cutCenter = if (i == 0) .4625f else .53f
                    val halfCut = .1225f * arrange
                    translate(halfCut, 0f) {
                        clipRect(rect.left, rect.top, cutCenter - halfCut, rect.bottom) {
                            clipPath(path) { drawUnitImage(cleanPieces, 1f - morph) }
                        }
                    }
                    translate(-halfCut, 0f) {
                        clipRect(cutCenter + halfCut, rect.top, rect.right, rect.bottom) {
                            clipPath(path) { drawUnitImage(cleanPieces, 1f - morph) }
                        }
                    }
                }
            }
        }
    }
    drawUnitImage(melon, morph)
    val aim = FastOutSlowInEasing.transform(t.phase(.06f, .4f))
    val tap = sin(PI.toFloat() * t.phase(.4f, .57f))
    translate((.495f - .574f) * aim, (.194f - .721f) * aim + .11f * tap) {
        clipPath(shapes.pen) { drawUnitImage(face, 1f - t.phase(.6f, .75f)) }
    }
    val touch = t.phase(.48f, .66f)
    drawCircle(Color(0xFFFFD99A), radius = .02f + .07f * touch, center = Offset(.495f, .293f),
        alpha = sin(PI.toFloat() * touch).coerceAtLeast(0f) * .7f, style = Stroke(.006f))
}
