package app.nazzel.core

enum class StreamKind(val label: String) { HLS("HLS"), DASH("DASH"), FILE("Video file") }

data class DetectedStream(val url: String, val kind: StreamKind, val pageUrl: String?)

/** Recognises media manifests and direct video files among the requests a web page makes. */
object StreamDetector {
    private val hls = Regex("""(?i)\.m3u8(?:$|[?#])""")
    private val dash = Regex("""(?i)\.mpd(?:$|[?#])""")
    private val file = Regex("""(?i)\.(?:mp4|webm|mkv|mov)(?:$|[?#])""")

    private val hlsMime = setOf("application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl")
    private val dashMime = setOf("application/dash+xml")

    fun classify(url: String, mimeType: String? = null): StreamKind? {
        if (!url.startsWith("http://") && !url.startsWith("https://")) return null
        val mime = mimeType?.substringBefore(';')?.trim()?.lowercase()
        val path = url.substringBefore('#')
        return when {
            hls.containsMatchIn(path) || mime in hlsMime -> StreamKind.HLS
            dash.containsMatchIn(path) || mime in dashMime -> StreamKind.DASH
            file.containsMatchIn(path) || mime?.startsWith("video/") == true -> StreamKind.FILE
            else -> null
        }
    }
}
