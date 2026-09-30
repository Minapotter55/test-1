package app.nazzel.data

import android.content.Context
import app.nazzel.core.AudioFormat
import app.nazzel.core.DownloadOptions
import app.nazzel.core.MediaMode
import app.nazzel.core.VideoQuality

/** Default download options, remembered between sessions. */
class Settings(context: Context) {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    var defaults: DownloadOptions
        get() {
            val mode = if (prefs.getBoolean("audioOnly", false)) {
                MediaMode.Audio(enumOr(prefs.getString("audioFormat", null), AudioFormat.MP3))
            } else {
                MediaMode.Video(
                    enumOr(prefs.getString("quality", null), VideoQuality.P1080),
                    prefs.getBoolean("prefer60", true),
                )
            }
            return DownloadOptions(
                mode = mode,
                subtitles = prefs.getBoolean("subtitles", false),
                subtitleLanguages = prefs.getString("subtitleLanguages", "ar,en") ?: "ar,en",
            )
        }
        set(value) {
            prefs.edit().apply {
                when (val m = value.mode) {
                    is MediaMode.Video -> {
                        putBoolean("audioOnly", false)
                        putString("quality", m.quality.name)
                        putBoolean("prefer60", m.prefer60Fps)
                    }
                    is MediaMode.Audio -> {
                        putBoolean("audioOnly", true)
                        putString("audioFormat", m.format.name)
                    }
                }
                putBoolean("subtitles", value.subtitles)
                putString("subtitleLanguages", value.subtitleLanguages)
            }.apply()
        }

    private inline fun <reified T : Enum<T>> enumOr(name: String?, fallback: T): T =
        name?.let { runCatching { enumValueOf<T>(it) }.getOrNull() } ?: fallback
}
