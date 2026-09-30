package app.nazzel.engine

import android.content.Context
import app.nazzel.core.Redactor
import app.nazzel.data.LogStore
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

sealed interface EngineState {
    data object Preparing : EngineState
    data object Ready : EngineState
    data class Failed(val message: String) : EngineState
}

data class MediaInfo(
    val title: String,
    val thumbnail: String?,
    val durationSeconds: Int,
    val uploader: String?,
    /** Distinct video heights on offer, highest first. */
    val heights: List<Int>,
)

/** Wraps the bundled yt-dlp (Python) and FFmpeg binaries shipped by youtubedl-android. */
object Engine {
    private val _state = MutableStateFlow<EngineState>(EngineState.Preparing)
    val state: StateFlow<EngineState> = _state.asStateFlow()
    private val initLock = Mutex()

    /** Unpacks the binaries on first run (takes a few seconds), then is a no-op. */
    suspend fun init(context: Context) = initLock.withLock {
        if (_state.value == EngineState.Ready) return@withLock
        _state.value = EngineState.Preparing
        _state.value = withContext(Dispatchers.IO) {
            runCatching {
                YoutubeDL.getInstance().init(context.applicationContext)
                FFmpeg.getInstance().init(context.applicationContext)
                LogStore.log("engine ready, yt-dlp ${YoutubeDL.getInstance().versionName(context) ?: "bundled"}")
                EngineState.Ready
            }.getOrElse {
                LogStore.log("engine init failed: ${it.message}")
                EngineState.Failed(Redactor.redact(it.message ?: it.javaClass.simpleName))
            }
        }
    }

    suspend fun awaitReady(context: Context): Boolean {
        init(context)
        return state.first { it != EngineState.Preparing } == EngineState.Ready
    }

    suspend fun fetchInfo(url: String, headers: Map<String, String> = emptyMap()): MediaInfo =
        runInterruptible(Dispatchers.IO) {
            val request = YoutubeDLRequest(url).addOption("--no-playlist")
            headers.forEach { (k, v) -> request.addOption("--add-header", "$k:$v") }
            LogStore.log("analyze $url")
            val info = YoutubeDL.getInstance().getInfo(request)
            MediaInfo(
                title = info.title ?: info.fulltitle ?: url,
                thumbnail = info.thumbnail,
                durationSeconds = info.duration,
                uploader = info.uploader,
                heights = info.formats.orEmpty()
                    .filter { it.vcodec != "none" && it.height > 0 }
                    .map { it.height }
                    .distinct()
                    .sortedDescending(),
            )
        }

    fun version(context: Context): String =
        YoutubeDL.getInstance().versionName(context) ?: YoutubeDL.getInstance().version(context) ?: "bundled"

    /** Returns true if a newer yt-dlp was installed, false if already current. */
    suspend fun updateYtDlp(context: Context): Boolean = withContext(Dispatchers.IO) {
        val status = YoutubeDL.getInstance().updateYoutubeDL(context.applicationContext, YoutubeDL.UpdateChannel.STABLE)
        LogStore.log("yt-dlp update: $status")
        status == YoutubeDL.UpdateStatus.DONE
    }

    fun cancel(processId: String) {
        YoutubeDL.getInstance().destroyProcessById(processId)
    }
}
