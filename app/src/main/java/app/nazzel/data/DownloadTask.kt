package app.nazzel.data

import app.nazzel.core.AudioFormat
import app.nazzel.core.DownloadOptions
import app.nazzel.core.MediaMode
import app.nazzel.core.VideoQuality
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

enum class TaskStatus { QUEUED, RUNNING, PROCESSING, PAUSED, DONE, FAILED }

data class DownloadTask(
    val id: String = UUID.randomUUID().toString(),
    val url: String,
    val title: String,
    val thumbnail: String? = null,
    val options: DownloadOptions,
    val status: TaskStatus = TaskStatus.QUEUED,
    val progress: Float = 0f,
    val etaSeconds: Long = -1,
    val error: String? = null,
    /** content:// URIs of the finished files in the public Downloads collection. */
    val outputs: List<String> = emptyList(),
    val createdAt: Long = System.currentTimeMillis(),
) {
    val isFinished get() = status == TaskStatus.DONE || status == TaskStatus.FAILED

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("url", url)
        put("title", title)
        put("thumbnail", thumbnail)
        put("options", options.toJson())
        put("status", status.name)
        put("progress", progress.toDouble())
        put("error", error)
        put("outputs", JSONArray(outputs))
        put("createdAt", createdAt)
    }

    companion object {
        fun fromJson(o: JSONObject): DownloadTask {
            var status = TaskStatus.valueOf(o.getString("status"))
            // A task that was mid-flight when the process died resumes from its .part file.
            if (status == TaskStatus.RUNNING || status == TaskStatus.PROCESSING) status = TaskStatus.QUEUED
            val outputs = o.optJSONArray("outputs")?.let { a -> List(a.length()) { a.getString(it) } }.orEmpty()
            return DownloadTask(
                id = o.getString("id"),
                url = o.getString("url"),
                title = o.getString("title"),
                thumbnail = o.optStringOrNull("thumbnail"),
                options = optionsFromJson(o.getJSONObject("options")),
                status = status,
                progress = o.optDouble("progress", 0.0).toFloat(),
                error = o.optStringOrNull("error"),
                outputs = outputs,
                createdAt = o.optLong("createdAt", System.currentTimeMillis()),
            )
        }
    }
}

fun DownloadOptions.toJson(): JSONObject = JSONObject().apply {
    when (val m = mode) {
        is MediaMode.Video -> {
            put("mode", "video")
            put("quality", m.quality.name)
            put("prefer60", m.prefer60Fps)
        }
        is MediaMode.Audio -> {
            put("mode", "audio")
            put("audioFormat", m.format.name)
        }
    }
    put("subtitles", subtitles)
    put("subtitleLanguages", subtitleLanguages)
    put("allowPlaylist", allowPlaylist)
    put("headers", JSONObject(headers))
}

fun optionsFromJson(o: JSONObject): DownloadOptions {
    val mode = if (o.optString("mode") == "audio") {
        MediaMode.Audio(AudioFormat.valueOf(o.getString("audioFormat")))
    } else {
        MediaMode.Video(VideoQuality.valueOf(o.getString("quality")), o.optBoolean("prefer60", true))
    }
    val headers = o.optJSONObject("headers")?.let { h -> h.keys().asSequence().associateWith { h.getString(it) } }.orEmpty()
    return DownloadOptions(
        mode = mode,
        subtitles = o.optBoolean("subtitles"),
        subtitleLanguages = o.optString("subtitleLanguages", "ar,en"),
        allowPlaylist = o.optBoolean("allowPlaylist"),
        headers = headers,
    )
}

private fun JSONObject.optStringOrNull(name: String): String? =
    if (isNull(name)) null else optString(name).takeIf { it.isNotEmpty() }
