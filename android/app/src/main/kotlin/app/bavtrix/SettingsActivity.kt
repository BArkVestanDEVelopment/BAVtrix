package app.bavtrix

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
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
            MaterialTheme(colorScheme = darkColorScheme()) {
                Surface(Modifier.fillMaxSize()) { SettingsScreen() }
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

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text("Настройки", style = MaterialTheme.typography.headlineMedium)
        Text("Дождь", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
        SliderRow("Плотность", cfg.spawnRate * 100, 5f..97f, { "%.0f%%".format(it) }) { update(cfg.copy(spawnRate = it / 100)) }
        SliderRow("Разброс скоростей", cfg.speedVariance, 1f..20f, { "%.0f".format(it) }) { update(cfg.copy(speedVariance = it)) }
        SliderRow("Время шага, мс", cfg.refreshMs, 10f..300f, { "%.0f".format(it) }) { update(cfg.copy(refreshMs = it)) }
        SliderRow("Размер символов", cfg.glyphSize, 8f..30f, { "%.0f dp".format(it) }) { update(cfg.copy(glyphSize = it)) }
        SliderRow("Спецстрока", cfg.specialProbability * 100, 0f..100f, { "%.0f%%".format(it) }) { update(cfg.copy(specialProbability = it / 100)) }

        Text("Шлейф", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
        SliderRow("Мин. длина", cfg.trailMin.toFloat(), 2f..100f, { "%.0f".format(it) }) { update(cfg.copy(trailMin = it.toInt())) }
        SliderRow("Макс. длина (0 = авто)", cfg.trailMax.toFloat(), 0f..200f, { "%.0f".format(it) }) { update(cfg.copy(trailMax = it.toInt())) }

        Text("Мерцание", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
        SliderRow("Символы в шлейфе", cfg.flicker * 100, 0f..100f, { "%.0f%%".format(it) }) { update(cfg.copy(flicker = it / 100)) }
        SliderRow("Голова потока", cfg.headFlicker * 100, 0f..100f, { "%.0f%%".format(it) }) { update(cfg.copy(headFlicker = it / 100)) }
        SliderRow("Яркость головы", cfg.headBrightness * 100, 50f..200f, { "%.0f%%".format(it) }) { update(cfg.copy(headBrightness = it / 100)) }

        Text("Цвет", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            presets.chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { p ->
                        FilterChip(
                            selected = cfg.fade == p.fade && cfg.fg == p.fg,
                            onClick = { update(cfg.copy(fg = p.fg, fade = p.fade)) },
                            label = { Text(p.name) },
                        )
                    }
                }
            }
        }

        OutlinedButton(
            onClick = {
                SettingsStore.reset(context)
                cfg = RainConfig()
            },
            modifier = Modifier.padding(top = 16.dp),
        ) { Text("Сбросить настройки") }
        Button(onClick = { (context as? ComponentActivity)?.finish() }, modifier = Modifier.fillMaxWidth()) {
            Text("Готово")
        }
        Text(
            "BAVtrix 1.0 · BArkVestan_Development · GPL-2.0",
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(top = 8.dp),
        )
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
            Text(title)
            Text(format(value), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Slider(value = value.coerceIn(range), onValueChange = onChange, valueRange = range)
    }
}
