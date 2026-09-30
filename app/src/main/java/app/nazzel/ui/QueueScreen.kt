package app.nazzel.ui

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.nazzel.MainViewModel
import app.nazzel.R
import app.nazzel.data.DownloadTask
import app.nazzel.data.TaskStatus

@Composable
fun QueueScreen(vm: MainViewModel, modifier: Modifier = Modifier) {
    val tasks by vm.tasks.collectAsStateWithLifecycle()

    if (tasks.isEmpty()) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text(stringResource(R.string.queue_empty)) }
        return
    }

    LazyColumn(
        modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (tasks.any { it.isFinished }) {
            item {
                TextButton(onClick = vm::clearFinished) { Text(stringResource(R.string.clear_finished)) }
            }
        }
        items(tasks.asReversed(), key = { it.id }) { task -> TaskCard(task, vm) }
    }
}

@Composable
private fun TaskCard(task: DownloadTask, vm: MainViewModel) {
    val context = LocalContext.current
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(task.title, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall)

            val statusText = when (task.status) {
                TaskStatus.QUEUED -> stringResource(R.string.status_queued)
                TaskStatus.RUNNING -> stringResource(R.string.status_running, task.progress.toInt()) +
                    (if (task.etaSeconds > 0) " · " + stringResource(R.string.eta, formatDuration(task.etaSeconds)) else "")
                TaskStatus.PROCESSING -> stringResource(R.string.status_processing)
                TaskStatus.PAUSED -> stringResource(R.string.status_paused)
                TaskStatus.DONE -> stringResource(R.string.status_done)
                TaskStatus.FAILED -> stringResource(R.string.status_failed)
            }
            Text(
                statusText,
                style = MaterialTheme.typography.bodySmall,
                color = if (task.status == TaskStatus.FAILED) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            when (task.status) {
                TaskStatus.RUNNING, TaskStatus.PAUSED ->
                    LinearProgressIndicator(progress = { task.progress / 100f }, modifier = Modifier.fillMaxWidth())
                TaskStatus.PROCESSING, TaskStatus.QUEUED -> LinearProgressIndicator(Modifier.fillMaxWidth())
                else -> Unit
            }
            task.error?.let { Text(it, style = MaterialTheme.typography.bodySmall, maxLines = 3, overflow = TextOverflow.Ellipsis) }

            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                when (task.status) {
                    TaskStatus.QUEUED, TaskStatus.RUNNING, TaskStatus.PROCESSING ->
                        TextButton(onClick = { vm.pause(task.id) }) { Text(stringResource(R.string.pause)) }
                    TaskStatus.PAUSED -> TextButton(onClick = { vm.resume(task.id) }) { Text(stringResource(R.string.resume)) }
                    TaskStatus.FAILED -> TextButton(onClick = { vm.resume(task.id) }) { Text(stringResource(R.string.retry)) }
                    TaskStatus.DONE -> task.outputs.firstOrNull()?.let { uri ->
                        TextButton(onClick = {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            try {
                                context.startActivity(intent)
                            } catch (e: ActivityNotFoundException) {
                                // No app installed that can play this file type.
                            }
                        }) { Text(stringResource(R.string.open)) }
                    }
                }
                TextButton(onClick = { vm.remove(task.id) }) { Text(stringResource(R.string.remove)) }
            }
        }
    }
}
