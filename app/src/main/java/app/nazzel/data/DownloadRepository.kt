package app.nazzel.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import org.json.JSONArray
import java.io.File

/** The download queue. Kept in memory as a flow and mirrored to a small JSON file so it survives restarts. */
class DownloadRepository(context: Context) {
    private val file = File(context.filesDir, "queue.json")
    private val _tasks = MutableStateFlow(load())
    val tasks: StateFlow<List<DownloadTask>> = _tasks.asStateFlow()

    fun get(id: String): DownloadTask? = _tasks.value.firstOrNull { it.id == id }

    fun nextQueued(): DownloadTask? = _tasks.value.firstOrNull { it.status == TaskStatus.QUEUED }

    fun add(task: DownloadTask) = mutate { it + task }

    fun remove(id: String) = mutate { list -> list.filterNot { it.id == id } }

    fun clearFinished() = mutate { list -> list.filterNot { it.isFinished } }

    fun update(id: String, persist: Boolean = true, transform: (DownloadTask) -> DownloadTask) {
        _tasks.update { list -> list.map { if (it.id == id) transform(it) else it } }
        if (persist) save()
    }

    private fun mutate(transform: (List<DownloadTask>) -> List<DownloadTask>) {
        _tasks.update(transform)
        save()
    }

    @Synchronized
    private fun save() {
        val json = JSONArray(_tasks.value.map { it.toJson() }).toString()
        val tmp = File(file.parentFile, file.name + ".tmp")
        tmp.writeText(json)
        tmp.renameTo(file)
    }

    private fun load(): List<DownloadTask> = runCatching {
        if (!file.exists()) return emptyList()
        val array = JSONArray(file.readText())
        List(array.length()) { DownloadTask.fromJson(array.getJSONObject(it)) }
    }.getOrElse { emptyList() }
}
