package app.nazzel.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.nazzel.AnalyzeState
import app.nazzel.MainViewModel
import app.nazzel.R
import app.nazzel.core.AudioFormat
import app.nazzel.core.DownloadOptions
import app.nazzel.core.MediaMode
import app.nazzel.core.Urls
import app.nazzel.core.VideoQuality
import app.nazzel.engine.EngineState
import coil.compose.AsyncImage

@Composable
fun DownloadScreen(vm: MainViewModel, modifier: Modifier = Modifier) {
    val url by vm.url.collectAsStateWithLifecycle()
    val analyze by vm.analyze.collectAsStateWithLifecycle()
    val options by vm.options.collectAsStateWithLifecycle()
    val engine by vm.engineState.collectAsStateWithLifecycle()
    val clipboard = LocalClipboardManager.current

    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        when (val e = engine) {
            EngineState.Preparing -> Text(stringResource(R.string.engine_preparing), style = MaterialTheme.typography.bodySmall)
            is EngineState.Failed -> Text(
                stringResource(R.string.engine_failed, e.message),
                color = MaterialTheme.colorScheme.error,
            )
            EngineState.Ready -> Unit
        }

        OutlinedTextField(
            value = url,
            onValueChange = vm::setUrl,
            label = { Text(stringResource(R.string.url_hint)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            trailingIcon = {
                TextButton(onClick = {
                    Urls.extract(clipboard.getText()?.text)?.let(vm::setUrl)
                }) { Text(stringResource(R.string.paste)) }
            },
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = vm::analyze, enabled = url.isNotBlank() && analyze !is AnalyzeState.Loading) {
                Text(stringResource(R.string.analyze))
            }
            OutlinedButton(onClick = vm::enqueueAnalyzed, enabled = url.isNotBlank()) {
                Text(stringResource(if (analyze is AnalyzeState.Loaded) R.string.download else R.string.download_direct))
            }
        }

        when (val s = analyze) {
            AnalyzeState.Idle -> Unit
            AnalyzeState.Loading -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                Text(stringResource(R.string.analyzing))
            }
            is AnalyzeState.Loaded -> Card(Modifier.fillMaxWidth()) {
                Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    s.info.thumbnail?.let {
                        AsyncImage(model = it, contentDescription = null, modifier = Modifier.size(width = 120.dp, height = 68.dp))
                    }
                    Column {
                        Text(s.info.title, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall)
                        Text(
                            listOfNotNull(s.info.uploader, formatDuration(s.info.durationSeconds.toLong()).takeIf { s.info.durationSeconds > 0 })
                                .joinToString(" · "),
                            style = MaterialTheme.typography.bodySmall,
                        )
                        if (s.info.heights.isNotEmpty()) {
                            Text(
                                stringResource(R.string.available_heights, s.info.heights.take(6).joinToString { "${it}p" }),
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }
                }
            }
            is AnalyzeState.Failed -> Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(stringResource(R.string.analyze_failed), color = MaterialTheme.colorScheme.error)
                    if (s.message.isNotBlank()) Text(s.message, style = MaterialTheme.typography.bodySmall, maxLines = 4)
                    Text(stringResource(R.string.open_in_browser_hint), style = MaterialTheme.typography.bodySmall)
                    Button(onClick = { vm.openInBrowser(s.url) }) { Text(stringResource(R.string.open_in_browser)) }
                }
            }
        }

        OptionsEditor(options, vm::setOptions)
    }
}

@Composable
fun OptionsEditor(options: DownloadOptions, onChange: (DownloadOptions) -> Unit) {
    val mode = options.mode
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = mode is MediaMode.Video,
                onClick = { if (mode !is MediaMode.Video) onChange(options.copy(mode = MediaMode.Video(VideoQuality.P1080, true))) },
                label = { Text(stringResource(R.string.mode_video)) },
            )
            FilterChip(
                selected = mode is MediaMode.Audio,
                onClick = { if (mode !is MediaMode.Audio) onChange(options.copy(mode = MediaMode.Audio(AudioFormat.MP3))) },
                label = { Text(stringResource(R.string.mode_audio)) },
            )
        }

        when (mode) {
            is MediaMode.Video -> {
                Text(stringResource(R.string.quality), style = MaterialTheme.typography.labelLarge)
                ChipRow(VideoQuality.entries, mode.quality, { it.label }) {
                    onChange(options.copy(mode = mode.copy(quality = it)))
                }
                SwitchRow(stringResource(R.string.prefer_60fps), mode.prefer60Fps) {
                    onChange(options.copy(mode = mode.copy(prefer60Fps = it)))
                }
                SwitchRow(stringResource(R.string.subtitles), options.subtitles) { onChange(options.copy(subtitles = it)) }
                if (options.subtitles) {
                    OutlinedTextField(
                        value = options.subtitleLanguages,
                        onValueChange = { onChange(options.copy(subtitleLanguages = it)) },
                        label = { Text(stringResource(R.string.subtitle_langs)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            is MediaMode.Audio -> {
                Text(stringResource(R.string.audio_format), style = MaterialTheme.typography.labelLarge)
                ChipRow(AudioFormat.entries, mode.format, { it.label }) { onChange(options.copy(mode = MediaMode.Audio(it))) }
            }
        }
        SwitchRow(stringResource(R.string.allow_playlist), options.allowPlaylist) { onChange(options.copy(allowPlaylist = it)) }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun <T> ChipRow(items: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit) {
    // Wraps onto several lines so all qualities stay visible on narrow screens.
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items.forEach { item ->
            FilterChip(selected = item == selected, onClick = { onSelect(item) }, label = { Text(label(item)) })
        }
    }
}

@Composable
fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

fun formatDuration(seconds: Long): String {
    if (seconds < 0) return "--:--"
    val h = seconds / 3600
    val m = (seconds % 3600) / 60
    val s = seconds % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}
