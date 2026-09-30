package app.nazzel

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import app.nazzel.data.DownloadRepository
import app.nazzel.data.Settings
import app.nazzel.engine.Engine
import app.nazzel.engine.QueueWorker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class NazzelApp : Application() {
    val appScope = CoroutineScope(SupervisorJob())
    lateinit var repository: DownloadRepository
        private set
    lateinit var settings: Settings
        private set

    override fun onCreate() {
        super.onCreate()
        repository = DownloadRepository(this)
        settings = Settings(this)
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL_DOWNLOADS, getString(R.string.notif_channel), NotificationManager.IMPORTANCE_LOW),
        )
        appScope.launch { Engine.init(this@NazzelApp) }
        // Pick up anything left queued from a previous run.
        if (repository.nextQueued() != null) QueueWorker.kick(this)
    }

    companion object {
        const val CHANNEL_DOWNLOADS = "downloads"

        fun repository(context: Context) = (context.applicationContext as NazzelApp).repository
    }
}
