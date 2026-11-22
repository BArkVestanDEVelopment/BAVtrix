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
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            BavShieldTheme {
                val context = LocalContext.current
                Box(Modifier.fillMaxSize()) {
                    AndroidView(factory = { RainView(it) }, modifier = Modifier.fillMaxSize())
                    Column(
                        modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp),
                        horizontalAlignment = Alignment.End,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        NeonButton(onClick = { setAsLiveWallpaper(context) }) { Text(stringResource(R.string.live_wallpaper)) }
                        NeonButton(onClick = { openScreensaverSettings(context) }) { Text(stringResource(R.string.screensaver)) }
                        NeonButton(onClick = { context.startActivity(Intent(context, SettingsActivity::class.java)) }) {
                            Text(stringResource(R.string.settings))
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
