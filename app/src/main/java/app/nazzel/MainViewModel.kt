package app.nazzel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.nazzel.core.DetectedStream
import app.nazzel.core.DownloadOptions
import app.nazzel.core.Redactor
import app.nazzel.data.DownloadTask
import app.nazzel.data.LogStore
import app.nazzel.data.TaskStatus
import app.nazzel.engine.Engine
import app.nazzel.engine.MediaInfo
import app.nazzel.engine.QueueWorker
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

sealed interface AnalyzeState {
    data object Idle : AnalyzeState
    data object Loading : AnalyzeState
    data class Loaded(val url: String, val info: MediaInfo) : AnalyzeState
    data class Failed(val url: String, val message: String) : AnalyzeState
}

enum class Tab { DOWNLOAD, QUEUE, BROWSER, SETTINGS }

class MainViewModel(app: Application) : AndroidViewModel(app) {
    private val nazzel = app as NazzelApp
    private val repo = nazzel.repository

    val tasks = repo.tasks
    val engineState = Engine.state

    val tab = MutableStateFlow(Tab.DOWNLOAD)
    val url = MutableStateFlow("")
    val options = MutableStateFlow(nazzel.settings.defaults)

    private val _analyze = MutableStateFlow<AnalyzeState>(AnalyzeState.Idle)
    val analyze = _analyze.asStateFlow()
    private var analyzeJob: Job? = null

    /** Page the browser tab should load next (set when extraction fails and the user opts to sniff). */
    val browserRequest = MutableStateFlow<String?>(null)
    private val _streams = MutableStateFlow<List<DetectedStream>>(emptyList())
    val streams = _streams.asStateFlow()

    fun setUrl(value: String) {
        url.value = value
        if (_analyze.value !is AnalyzeState.Loading) _analyze.value = AnalyzeState.Idle
    }

    fun setOptions(value: DownloadOptions) {
        options.value = value
        nazzel.settings.defaults = value
    }

    fun analyze() {
        val target = url.value.trim().ifEmpty { return }
        analyzeJob?.cancel()
        _analyze.value = AnalyzeState.Loading
        analyzeJob = viewModelScope.launch {
            _analyze.value = try {
                if (!Engine.awaitReady(nazzel)) error((Engine.state.value as? app.nazzel.engine.EngineState.Failed)?.message ?: "engine")
                AnalyzeState.Loaded(target, Engine.fetchInfo(target))
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                LogStore.log("analyze failed: ${e.message}")
                val msg = Redactor.redact(e.message ?: "").lines().lastOrNull { it.contains("ERROR") } ?: ""
                AnalyzeState.Failed(target, msg)
            }
        }
    }

    fun enqueue(url: String, title: String, thumbnail: String? = null, opts: DownloadOptions = options.value) {
        repo.add(DownloadTask(url = url, title = title, thumbnail = thumbnail, options = opts))
        QueueWorker.kick(nazzel)
    }

    fun enqueueAnalyzed() {
        when (val s = _analyze.value) {
            is AnalyzeState.Loaded -> enqueue(s.url, s.info.title, s.info.thumbnail)
            else -> url.value.trim().takeIf { it.isNotEmpty() }?.let { enqueue(it, it) }
        }
        url.value = ""
        _analyze.value = AnalyzeState.Idle
    }

    fun openInBrowser(target: String) {
        browserRequest.value = target
        tab.value = Tab.BROWSER
    }

    fun onStreamDetected(stream: DetectedStream) {
        _streams.update { list -> if (list.any { it.url == stream.url }) list else list + stream }
    }

    fun clearStreams() {
        _streams.value = emptyList()
    }

    fun downloadStream(stream: DetectedStream, pageTitle: String?, userAgent: String) {
        val headers = buildMap {
            stream.pageUrl?.let { put("Referer", it) }
            put("User-Agent", userAgent)
        }
        enqueue(stream.url, pageTitle?.takeIf { it.isNotBlank() } ?: stream.url, opts = options.value.copy(headers = headers))
        tab.value = Tab.QUEUE
    }

    fun pause(id: String) {
        repo.update(id) { it.copy(status = TaskStatus.PAUSED) }
        Engine.cancel(id)
    }

    fun resume(id: String) {
        repo.update(id) { it.copy(status = TaskStatus.QUEUED, error = null) }
        QueueWorker.kick(nazzel)
    }

    fun remove(id: String) {
        Engine.cancel(id)
        repo.remove(id)
    }

    fun clearFinished() = repo.clearFinished()
}
