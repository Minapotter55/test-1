package app.nazzel.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.nazzel.MainViewModel
import app.nazzel.R
import app.nazzel.core.Redactor
import app.nazzel.data.LogStore
import app.nazzel.engine.Engine
import app.nazzel.engine.EngineState
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(vm: MainViewModel, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    val options by vm.options.collectAsStateWithLifecycle()
    val engine by vm.engineState.collectAsStateWithLifecycle()
    var version by remember(engine) { mutableStateOf(if (engine == EngineState.Ready) Engine.version(context) else "…") }
    var updating by remember { mutableStateOf(false) }

    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Section(stringResource(R.string.settings_defaults))
        OptionsEditor(options, vm::setOptions)
        Text(stringResource(R.string.saved_to), style = MaterialTheme.typography.bodySmall)

        HorizontalDivider()
        Section(stringResource(R.string.settings_engine))
        Text(stringResource(R.string.ytdlp_version, version))
        Button(
            enabled = engine == EngineState.Ready && !updating,
            onClick = {
                updating = true
                scope.launch {
                    val msg = try {
                        if (Engine.updateYtDlp(context)) context.getString(R.string.update_done)
                        else context.getString(R.string.update_latest)
                    } catch (e: Exception) {
                        context.getString(R.string.update_failed, Redactor.redact(e.message ?: ""))
                    }
                    version = Engine.version(context)
                    updating = false
                    Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
                }
            },
        ) { Text(stringResource(if (updating) R.string.updating else R.string.update_ytdlp)) }

        HorizontalDivider()
        Section(stringResource(R.string.settings_privacy))
        Text(stringResource(R.string.privacy_note), style = MaterialTheme.typography.bodyMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = {
                val report = buildString {
                    appendLine("Nazzel diagnostics")
                    appendLine("yt-dlp: $version")
                    appendLine("Android: ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})")
                    appendLine("ABI: ${android.os.Build.SUPPORTED_ABIS.firstOrNull()}")
                    appendLine()
                    append(LogStore.dump())
                }
                // LogStore is already redacted; run it once more over the whole report as a safety net.
                clipboard.setText(AnnotatedString(Redactor.redact(report)))
                Toast.makeText(context, R.string.copied, Toast.LENGTH_SHORT).show()
            }) { Text(stringResource(R.string.copy_diagnostics)) }
            OutlinedButton(onClick = { LogStore.clear() }) { Text(stringResource(R.string.clear_logs)) }
        }
    }
}

@Composable
private fun Section(title: String) {
    Text(title, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
}
