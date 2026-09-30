package app.nazzel.engine

import android.annotation.SuppressLint
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.nazzel.NazzelApp
import app.nazzel.R
import app.nazzel.core.Redactor
import app.nazzel.core.YtDlpArgs
import app.nazzel.data.DownloadTask
import app.nazzel.data.LogStore
import app.nazzel.data.TaskStatus
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible
import java.io.File

/**
 * Drains the download queue one task at a time. Pausing a task kills its yt-dlp process; resuming
 * re-queues it and yt-dlp continues from the partial file.
 */
class QueueWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    private val repo = NazzelApp.repository(context)
    private val notifications = context.getSystemService(NotificationManager::class.java)

    override suspend fun doWork(): Result {
        runCatching { setForeground(foregroundInfo(applicationContext.getString(R.string.notif_preparing), null)) }
            .onFailure { LogStore.log("foreground not allowed: ${it.message}") }

        if (!Engine.awaitReady(applicationContext)) {
            val reason = (Engine.state.value as? EngineState.Failed)?.message
            while (true) {
                val task = repo.nextQueued() ?: break
                repo.update(task.id) { it.copy(status = TaskStatus.FAILED, error = reason) }
            }
            return Result.failure()
        }

        while (true) {
            val task = repo.nextQueued() ?: break
            run(task)
        }
        return Result.success()
    }

    private suspend fun run(task: DownloadTask) {
        repo.update(task.id) { it.copy(status = TaskStatus.RUNNING, error = null) }
        LogStore.log("start ${task.url}")

        val outDir = File(applicationContext.getExternalFilesDir(null), "downloads").apply { mkdirs() }
        val pathsFile = File(applicationContext.cacheDir, "paths-${task.id}.txt").apply { delete() }
        val request = YoutubeDLRequest(task.url).addCommands(YtDlpArgs.build(task.options, outDir.absolutePath, pathsFile.absolutePath))

        var lastUiUpdate = 0L
        try {
            runInterruptible(Dispatchers.IO) {
                YoutubeDL.getInstance().execute(request, task.id, false) { progress, eta, line ->
                    val now = System.currentTimeMillis()
                    if (now - lastUiUpdate < 500) return@execute
                    lastUiUpdate = now
                    val postProcessing = progress >= 100f || line.startsWith("[Merger]") ||
                        line.startsWith("[ExtractAudio]") || line.startsWith("[EmbedSubtitle]")
                    repo.update(task.id, persist = false) {
                        if (it.status != TaskStatus.RUNNING && it.status != TaskStatus.PROCESSING) it
                        else it.copy(
                            status = if (postProcessing) TaskStatus.PROCESSING else TaskStatus.RUNNING,
                            progress = progress.coerceIn(0f, 100f),
                            etaSeconds = eta,
                        )
                    }
                    showProgress(task.title, progress.toInt())
                }
            }

            val files = pathsFile.takeIf { it.exists() }?.readLines().orEmpty()
                .map { File(it.trim()) }
                .filter { it.isFile }
            if (files.isEmpty()) error("yt-dlp finished but produced no file")
            val uris = files.map { MediaExporter.export(applicationContext, it).toString() }
            repo.update(task.id) { it.copy(status = TaskStatus.DONE, progress = 100f, outputs = uris) }
            LogStore.log("done ${task.url} -> ${files.joinToString { it.name }}")
        } catch (e: YoutubeDL.CanceledException) {
            // Paused or removed by the user; the repository already reflects that.
            LogStore.log("stopped ${task.url}")
        } catch (e: CancellationException) {
            // WorkManager stopped us (e.g. system constraints); leave the task queued for next time.
            repo.update(task.id) { if (it.status == TaskStatus.PAUSED) it else it.copy(status = TaskStatus.QUEUED) }
            throw e
        } catch (e: Exception) {
            val message = Redactor.redact(e.message ?: e.javaClass.simpleName).lines()
                .lastOrNull { it.contains("ERROR", ignoreCase = true) } ?: Redactor.redact(e.message ?: "error")
            LogStore.log("failed ${task.url}: ${e.message}")
            repo.update(task.id) {
                if (it.status == TaskStatus.PAUSED) it else it.copy(status = TaskStatus.FAILED, error = message.take(500))
            }
        } finally {
            pathsFile.delete()
        }
    }

    // Posting silently fails when the user declined notifications; the download itself carries on.
    @SuppressLint("MissingPermission")
    private fun showProgress(title: String, progress: Int) {
        notifications.notify(NOTIFICATION_ID, notification(title, progress))
    }

    private fun notification(title: String, progress: Int?) =
        NotificationCompat.Builder(applicationContext, NazzelApp.CHANNEL_DOWNLOADS)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setSilent(true)
            .apply { if (progress == null) setProgress(0, 0, true) else setProgress(100, progress, false) }
            .build()

    private fun foregroundInfo(title: String, progress: Int?) =
        ForegroundInfo(NOTIFICATION_ID, notification(title, progress), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)

    override suspend fun getForegroundInfo(): ForegroundInfo =
        foregroundInfo(applicationContext.getString(R.string.notif_preparing), null)

    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val WORK_NAME = "download-queue"

        /** Makes sure a worker will pick up newly queued tasks, even if one is just finishing. */
        fun kick(context: Context) {
            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME,
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                OneTimeWorkRequestBuilder<QueueWorker>().build(),
            )
        }
    }
}
