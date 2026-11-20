package app.bavtrix

import android.content.pm.ApplicationInfo
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.bavtrix.core.RainConfig
import app.bavtrix.core.Rgba

private class ColorPreset(val name: String, val fg: Rgba, val fade: Rgba)

private val presets = listOf(
    ColorPreset("Зелёный", Rgba(187, 255, 187), Rgba(0, 128, 0)),
    ColorPreset("Синий", Rgba(190, 225, 255), Rgba(0, 90, 170)),
    ColorPreset("Красный", Rgba(255, 205, 205), Rgba(170, 0, 0)),
    ColorPreset("Янтарный", Rgba(255, 240, 190), Rgba(190, 120, 0)),
    ColorPreset("Фиолетовый", Rgba(230, 205, 255), Rgba(110, 0, 170)),
    ColorPreset("Белый", Rgba(255, 255, 255), Rgba(120, 120, 120)),
)

class SettingsActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            BavShieldTheme {
                Surface(Modifier.fillMaxSize(), color = Brand.Bg) { SettingsScreen() }
            }
        }
    }
}

@Composable
private fun SettingsScreen() {
    val context = LocalContext.current
    var cfg by remember { mutableStateOf(SettingsStore.load(context)) }
    fun update(new: RainConfig) {
        cfg = new
        SettingsStore.save(context, new)
    }
    val pickPicture = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null && PictureStore.save(context, uri)) {
            update(cfg.copy(usePicture = true, pictureVersion = cfg.pictureVersion + 1))
        }
    }
    // Debug builds only (adb): turn the picture on without going through the system picker.
    val debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    if (debuggable) {
        val activity = context as? ComponentActivity
        LaunchedEffect(Unit) {
            if (activity?.intent?.getBooleanExtra("debugUsePicture", false) == true) {
                update(cfg.copy(usePicture = true, pictureVersion = cfg.pictureVersion + 1))
            }
        }
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 22.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        GlowTitle("Настройки")
        Text("BAVtrix · цифровой дождь", color = Brand.Text2, modifier = Modifier.padding(start = 2.dp))

        SectionTitle("Дождь")
        NeonCard {
            SliderRow("Плотность", cfg.spawnRate * 100, 5f..97f, { "%.0f%%".format(it) }) { update(cfg.copy(spawnRate = it / 100)) }
            SliderRow("Разброс скоростей", cfg.speedVariance, 1f..20f, { "%.0f".format(it) }) { update(cfg.copy(speedVariance = it)) }
            SliderRow("Время шага, мс", cfg.refreshMs, 10f..300f, { "%.0f".format(it) }) { update(cfg.copy(refreshMs = it)) }
            SliderRow("Размер символов", cfg.glyphSize, 5f..30f, { "%.0f dp".format(it) }) { update(cfg.copy(glyphSize = it)) }
            SliderRow("Спецстрока", cfg.specialProbability * 100, 0f..100f, { "%.0f%%".format(it) }) { update(cfg.copy(specialProbability = it / 100)) }
        }

        SectionTitle("Шлейф")
        NeonCard {
            SliderRow("Мин. длина", cfg.trailMin.toFloat(), 2f..100f, { "%.0f".format(it) }) { update(cfg.copy(trailMin = it.toInt())) }
            SliderRow("Макс. длина (0 = авто)", cfg.trailMax.toFloat(), 0f..200f, { "%.0f".format(it) }) { update(cfg.copy(trailMax = it.toInt())) }
        }

        SectionTitle("Мерцание")
        NeonCard {
            SliderRow("Символы в шлейфе", cfg.flicker * 100, 0f..100f, { "%.0f%%".format(it) }) { update(cfg.copy(flicker = it / 100)) }
            SliderRow("Голова потока", cfg.headFlicker * 100, 0f..100f, { "%.0f%%".format(it) }) { update(cfg.copy(headFlicker = it / 100)) }
            SliderRow("Яркость головы", cfg.headBrightness * 100, 50f..200f, { "%.0f%%".format(it) }) { update(cfg.copy(headBrightness = it / 100)) }
        }

        SectionTitle("Картинка сквозь символы")
        NeonCard {
            Text(
                "Выбранная картинка проступает через символы дождя, как обои рабочего стола на компьютере.",
                style = MaterialTheme.typography.bodySmall,
                color = Brand.Text2,
            )
            SwitchRow("Показывать картинку", cfg.usePicture) {
                update(cfg.copy(usePicture = it, pictureVersion = cfg.pictureVersion + 1))
            }
            Text("Смешивание", color = Brand.Text, modifier = Modifier.padding(top = 4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("Copy" to 0, "OR" to 1, "AND" to 2).forEach { (name, mode) ->
                    BrandChip(name, cfg.pictureBlend == mode) { update(cfg.copy(pictureBlend = mode)) }
                }
            }
            Text(
                "Copy: символы показывают саму картинку. OR: к картинке добавляется цвет шлейфа. AND: картинка окрашивается цветом шлейфа.",
                style = MaterialTheme.typography.bodySmall,
                color = Brand.Text2,
            )
            SwitchRow("Заполнить весь экран (обрезать)", cfg.pictureCover) { update(cfg.copy(pictureCover = it)) }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(top = 6.dp)) {
                NeonButton(onClick = { pickPicture.launch("image/*") }) { Text("Выбрать картинку") }
                NeonOutlinedButton(onClick = {
                    PictureStore.delete(context)
                    update(cfg.copy(usePicture = false, pictureVersion = cfg.pictureVersion + 1))
                }) { Text("Убрать") }
            }
        }

        SectionTitle("Цвет")
        NeonCard {
            presets.chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { p ->
                        BrandChip(p.name, cfg.fade == p.fade && cfg.fg == p.fg) { update(cfg.copy(fg = p.fg, fade = p.fade)) }
                    }
                }
            }
        }

        Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NeonOutlinedButton(
                onClick = {
                    SettingsStore.reset(context)
                    cfg = RainConfig()
                },
                danger = true,
            ) { Text("Сбросить") }
            NeonButton(onClick = { (context as? ComponentActivity)?.finish() }, modifier = Modifier.weight(1f)) {
                Text("Готово")
            }
        }
        Text(
            "BAVtrix 1.0 · © 2026 BArkVestan Development",
            style = MaterialTheme.typography.bodySmall,
            color = Brand.Text2,
            modifier = Modifier.padding(top = 10.dp),
        )
        var showLicenses by remember { mutableStateOf(false) }
        NeonOutlinedButton(onClick = { showLicenses = true }, modifier = Modifier.padding(top = 8.dp)) { Text("Лицензии") }
        if (showLicenses) LicensesDialog { showLicenses = false }
    }
}

/** The licence texts of the third-party components, read from the app's assets. */
@Composable
private fun LicensesDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val text = remember {
        runCatching { context.assets.open("THIRD_PARTY_NOTICES.txt").bufferedReader().use { it.readText() } }
            .getOrElse { "THIRD_PARTY_NOTICES.txt is missing from the app." }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = onDismiss) { Text("Закрыть") } },
        title = { Text("Лицензии") },
        text = { Column(Modifier.verticalScroll(rememberScrollState())) { Text(text, style = MaterialTheme.typography.bodySmall) } },
    )
}

@Composable
private fun BrandChip(label: String, selected: Boolean, onClick: () -> Unit) {
    NoTouchPadding { FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label) },
        modifier = if (selected) Modifier.siteGlow(layers = SoftGlow) else Modifier,
        shape = RoundedCornerShape(50),
        colors = FilterChipDefaults.filterChipColors(
            containerColor = Brand.Glass,
            labelColor = Brand.Text2,
            selectedContainerColor = Brand.Glass,
            selectedLabelColor = Brand.Green,
        ),
        border = BorderStroke(1.dp, if (selected) Brand.Green.copy(alpha = 0.7f) else Brand.GlassBorder),
    ) }
}

@Composable
private fun SwitchRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = Brand.Text, modifier = Modifier.weight(1f).padding(end = 12.dp))
        Switch(checked = checked, onCheckedChange = onChange, colors = brandSwitchColors())
    }
}

@Composable
private fun SliderRow(
    title: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    format: (Float) -> String,
    onChange: (Float) -> Unit,
) {
    Column {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(title, color = Brand.Text)
            Text(format(value), color = Brand.Green)
        }
        Slider(value = value.coerceIn(range), onValueChange = onChange, valueRange = range, colors = brandSliderColors())
    }
}
