package app.nazzel.core

/** Target video resolution. [maxHeight] of null means "best available". */
enum class VideoQuality(val label: String, val maxHeight: Int?) {
    BEST("Best", null),
    P2160("4K (2160p)", 2160),
    P1440("1440p", 1440),
    P1080("1080p", 1080),
    P720("720p", 720),
    P480("480p", 480),
    P360("360p", 360),
}

enum class AudioFormat(val label: String, val ytDlpName: String) {
    MP3("MP3", "mp3"),
    OPUS("Opus", "opus"),
    WAV("WAV", "wav"),
}

sealed interface MediaMode {
    data class Video(val quality: VideoQuality, val prefer60Fps: Boolean) : MediaMode
    data class Audio(val format: AudioFormat) : MediaMode
}

data class DownloadOptions(
    val mode: MediaMode = MediaMode.Video(VideoQuality.P1080, prefer60Fps = true),
    val subtitles: Boolean = false,
    val subtitleLanguages: String = "ar,en",
    val allowPlaylist: Boolean = false,
    /** Extra HTTP headers, e.g. Referer / User-Agent captured by the browser sniffer. */
    val headers: Map<String, String> = emptyMap(),
)

/**
 * Translates [DownloadOptions] into yt-dlp command-line arguments.
 * Kept free of Android dependencies so it can be unit tested on the JVM.
 */
object YtDlpArgs {

    const val OUTPUT_TEMPLATE = "%(title).150B [%(id)s].%(ext)s"

    fun build(options: DownloadOptions, outputDir: String, pathsFile: String): List<String> {
        val args = mutableListOf<String>()
        args += listOf("-P", outputDir, "-o", OUTPUT_TEMPLATE)
        args += listOf("--newline", "--no-mtime", "--continue")
        args += if (options.allowPlaylist) "--yes-playlist" else "--no-playlist"
        // Final file locations are written here so the app can find the result after post-processing.
        args += listOf("--print-to-file", "after_move:filepath", pathsFile)

        when (val mode = options.mode) {
            is MediaMode.Video -> {
                args += listOf("-f", "bv*+ba/b")
                args += listOf("-S", sortString(mode.quality, mode.prefer60Fps))
                // mp4 when codecs allow it, otherwise mkv (e.g. VP9/AV1 + Opus at 4K).
                args += listOf("--merge-output-format", "mp4/mkv")
                if (options.subtitles) {
                    args += listOf(
                        "--write-subs", "--write-auto-subs",
                        "--sub-langs", options.subtitleLanguages.ifBlank { "all" },
                        "--embed-subs",
                    )
                }
            }
            is MediaMode.Audio -> {
                args += listOf("-f", "ba/b", "-x", "--audio-format", mode.format.ytDlpName)
                if (mode.format != AudioFormat.WAV) args += listOf("--audio-quality", "0")
            }
        }
        args += "--embed-metadata"
        for ((name, value) in options.headers) {
            if (name.isNotBlank() && value.isNotBlank()) args += listOf("--add-header", "$name:$value")
        }
        return args
    }

    /** yt-dlp format sort: largest resolution up to the cap, then fps (capped at 30 unless 60 is preferred). */
    fun sortString(quality: VideoQuality, prefer60Fps: Boolean): String {
        val res = quality.maxHeight?.let { "res:$it" } ?: "res"
        val fps = if (prefer60Fps) "fps" else "fps:30"
        return "$res,$fps"
    }
}
