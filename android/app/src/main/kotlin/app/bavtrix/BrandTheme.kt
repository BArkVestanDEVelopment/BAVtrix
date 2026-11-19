package app.bavtrix

import android.graphics.BlurMaskFilter
import android.graphics.Paint
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.LocalMinimumInteractiveComponentSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SliderColors
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.SwitchColors
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.min

/**
 * BAVSHIELD brand, taken from the website: Tektur font, dark glass plates with a hairline border,
 * the brand green #39FF88, and the outward `box-shadow` glow on pills and badges.
 */
object Brand {
    val Green = Color(0xFF39FF88)
    val Red = Color(0xFFFF3939)
    val Bg = Color(0xFF0A0D0B) // --bg
    val Glass = Color(0xDB1F2227) // --glass: rgba(31,34,39,.86)
    val GlassBorder = Color(0x1CFFFFFF) // --glass-border: rgba(255,255,255,.11)
    val Text = Color(0xFFF5F6F7) // --text
    val Text2 = Color(0xA8F5F6F7) // --text-2: .66
    val Text3 = Color(0x75F5F6F7) // --text-3: .46
}

val Tektur = FontFamily(
    Font(R.font.tektur_regular, FontWeight.Normal),
    Font(R.font.tektur_medium, FontWeight.Medium),
    Font(R.font.tektur_semibold, FontWeight.SemiBold),
    Font(R.font.tektur_bold, FontWeight.Bold),
)

private fun Typography.withFont(f: FontFamily) = Typography(
    displayLarge = displayLarge.copy(fontFamily = f),
    displayMedium = displayMedium.copy(fontFamily = f),
    displaySmall = displaySmall.copy(fontFamily = f),
    headlineLarge = headlineLarge.copy(fontFamily = f),
    headlineMedium = headlineMedium.copy(fontFamily = f),
    headlineSmall = headlineSmall.copy(fontFamily = f),
    titleLarge = titleLarge.copy(fontFamily = f),
    titleMedium = titleMedium.copy(fontFamily = f),
    titleSmall = titleSmall.copy(fontFamily = f),
    bodyLarge = bodyLarge.copy(fontFamily = f),
    bodyMedium = bodyMedium.copy(fontFamily = f),
    bodySmall = bodySmall.copy(fontFamily = f),
    labelLarge = labelLarge.copy(fontFamily = f),
    labelMedium = labelMedium.copy(fontFamily = f),
    labelSmall = labelSmall.copy(fontFamily = f),
)

@Composable
fun BavShieldTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Brand.Green,
            onPrimary = Color.Black,
            secondary = Brand.Green,
            background = Brand.Bg,
            onBackground = Brand.Text,
            surface = Brand.Bg,
            onSurface = Brand.Text,
            surfaceVariant = Brand.Glass,
            onSurfaceVariant = Brand.Text2,
            outline = Brand.GlassBorder,
        ),
        typography = Typography().withFont(Tektur),
        content = content,
    )
}

/** CSS-like glow layers: blur radius in px and opacity (`0 0 8px .9, 0 0 20px .5, 0 0 40px .2`). */
val StrongGlow = listOf(8f to 0.9f, 20f to 0.5f, 40f to 0.2f)
val SoftGlow = listOf(4f to 0.5f, 10f to 0.25f, 18f to 0.1f)

/**
 * `box-shadow: 0 0 Bpx` equivalent: the glow is drawn only OUTSIDE the element's rounded box
 * (an outer blur of a filled box), so the element itself stays clean, like on the website.
 */
fun Modifier.siteGlow(
    color: Color = Brand.Green,
    corner: Dp = 999.dp,
    layers: List<Pair<Float, Float>> = StrongGlow,
): Modifier = drawBehind {
    val radius = min(corner.toPx(), min(size.width, size.height) / 2f)
    drawIntoCanvas { canvas ->
        val native = canvas.nativeCanvas
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
        val box = android.graphics.Path().apply {
            addRoundRect(0f, 0f, size.width, size.height, radius, radius, android.graphics.Path.Direction.CW)
        }
        // Like CSS box-shadow, the glow exists only outside the box: cut the box out of the clip.
        native.save()
        native.clipOutPath(box)
        for ((blur, alpha) in layers) {
            paint.color = color.copy(alpha = alpha).toArgb()
            // CSS blur B has a Gaussian sigma of B/2; Skia's blur "radius" is (sigma - 0.5) / 0.577.
            val sigma = blur.dp.toPx() / 2f
            paint.maskFilter = BlurMaskFilter(((sigma - 0.5f) / 0.57735f).coerceAtLeast(1f), BlurMaskFilter.Blur.NORMAL)
            native.drawRoundRect(0f, 0f, size.width, size.height, radius, radius, paint)
        }
        native.restore()
    }
}

/** A "plate": neutral dark glass with a hairline border (no glow, like the website cards). */
@Composable
fun NeonCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(22.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(Brand.Glass, shape)
            .border(1.dp, Brand.GlassBorder, shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        content = content,
    )
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(),
        modifier = modifier.padding(start = 4.dp, top = 14.dp),
        color = Brand.Green,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 2.sp,
    )
}

@Composable
fun GlowTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        modifier = modifier,
        style = TextStyle(color = Brand.Text, fontSize = 30.sp, fontWeight = FontWeight.Bold, fontFamily = Tektur),
    )
}

/** `glass-pill`: glass background, hairline border, green text and the outward green glow. */
@Composable
fun NeonButton(onClick: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    NoTouchPadding {
        Button(
            onClick = onClick,
            modifier = modifier.siteGlow(),
            shape = RoundedCornerShape(50),
            colors = ButtonDefaults.buttonColors(containerColor = Brand.Glass, contentColor = Brand.Green),
            elevation = ButtonDefaults.buttonElevation(0.dp, 0.dp, 0.dp, 0.dp, 0.dp),
            border = BorderStroke(1.dp, Brand.GlassBorder),
        ) { content() }
    }
}

/**
 * Material pads small controls to a 48dp touch target OUTSIDE the modifier chain, so a glow drawn by
 * the modifier would surround that invisible box instead of the visible pill. Switch the padding off.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun NoTouchPadding(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides Dp.Unspecified, content = content)
}

/** Secondary `glass-pill`: same look; red for dangerous actions (the brand red). */
@Composable
fun NeonOutlinedButton(onClick: () -> Unit, modifier: Modifier = Modifier, danger: Boolean = false, content: @Composable () -> Unit) {
    val c = if (danger) Brand.Red else Brand.Green
    NoTouchPadding {
        OutlinedButton(
            onClick = onClick,
            modifier = modifier.siteGlow(color = c, layers = if (danger) StrongGlow else SoftGlow),
            shape = RoundedCornerShape(50),
            colors = ButtonDefaults.outlinedButtonColors(containerColor = Brand.Glass, contentColor = c),
            border = BorderStroke(1.dp, Brand.GlassBorder),
        ) { content() }
    }
}

@Composable
fun brandSliderColors(): SliderColors = SliderDefaults.colors(
    thumbColor = Brand.Green,
    activeTrackColor = Brand.Green,
    inactiveTrackColor = Color.White.copy(alpha = 0.12f),
)

@Composable
fun brandSwitchColors(): SwitchColors = SwitchDefaults.colors(
    checkedThumbColor = Color.Black,
    checkedTrackColor = Brand.Green,
    checkedBorderColor = Brand.Green,
    uncheckedThumbColor = Brand.Text2,
    uncheckedTrackColor = Brand.Glass,
    uncheckedBorderColor = Brand.GlassBorder,
)
