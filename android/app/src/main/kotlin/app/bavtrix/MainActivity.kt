package app.bavtrix

import android.app.WallpaperManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            BavShieldTheme {
                val context = LocalContext.current
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    // Button text and padding follow the screen width (phones and tablets).
                    val buttonText = (maxWidth.value / 30f).coerceIn(11f, 22f).sp
                    val buttonPad = (maxWidth.value / 90f).coerceIn(3f, 10f).dp
                    AndroidView(factory = { RainView(it) }, modifier = Modifier.fillMaxSize())
                    Row(
                        modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(horizontal = 12.dp, vertical = 20.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        NeonButton(onClick = { setAsLiveWallpaper(context) }, modifier = Modifier.weight(1f), contentPadding = PaddingValues(horizontal = buttonPad, vertical = 12.dp)) {
                            Text(stringResource(R.string.live_wallpaper), maxLines = 1, softWrap = false, overflow = TextOverflow.Visible, fontSize = buttonText, textAlign = TextAlign.Center, modifier = Modifier.wrapContentWidth(unbounded = true))
                        }
                        NeonButton(onClick = { openScreensaverSettings(context) }, modifier = Modifier.weight(1f), contentPadding = PaddingValues(horizontal = buttonPad, vertical = 12.dp)) {
                            Text(stringResource(R.string.screensaver), maxLines = 1, softWrap = false, overflow = TextOverflow.Visible, fontSize = buttonText, textAlign = TextAlign.Center, modifier = Modifier.wrapContentWidth(unbounded = true))
                        }
                        NeonButton(
                            onClick = { context.startActivity(Intent(context, SettingsActivity::class.java)) },
                            modifier = Modifier.weight(1f),
                            contentPadding = PaddingValues(horizontal = buttonPad, vertical = 12.dp),
                        ) {
                            Text(stringResource(R.string.settings), maxLines = 1, softWrap = false, overflow = TextOverflow.Visible, fontSize = buttonText, textAlign = TextAlign.Center, modifier = Modifier.wrapContentWidth(unbounded = true))
                        }
                    }
                }
            }
        }
    }

    /** Opens the system screensaver (daydream) settings, where BAVtrix is one of the choices. */
    private fun openScreensaverSettings(context: Context) {
        try {
            context.startActivity(Intent(Settings.ACTION_DREAM_SETTINGS))
        } catch (e: ActivityNotFoundException) {
            context.startActivity(Intent(Settings.ACTION_DISPLAY_SETTINGS))
        }
    }

    /** Opens the system preview for the BAVtrix live wallpaper (or the chooser on devices without it). */
    private fun setAsLiveWallpaper(context: Context) {
        val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).putExtra(
            WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
            ComponentName(context, RainWallpaperService::class.java),
        )
        try {
            context.startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            context.startActivity(Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER))
        }
    }
}
