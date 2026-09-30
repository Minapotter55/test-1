package app.nazzel

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.nazzel.core.Urls
import app.nazzel.ui.BrowserScreen
import app.nazzel.ui.DownloadScreen
import app.nazzel.ui.NazzelTheme
import app.nazzel.ui.QueueScreen
import app.nazzel.ui.SettingsScreen

class MainActivity : ComponentActivity() {
    private val vm: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleShare(intent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerForActivityResult(ActivityResultContracts.RequestPermission()) {}
                .launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        setContent {
            NazzelTheme {
                val tab by vm.tab.collectAsStateWithLifecycle()
                Scaffold(
                    bottomBar = {
                        NavigationBar {
                            TabItem(tab, Tab.DOWNLOAD, Icons.Filled.Home, R.string.tab_download)
                            TabItem(tab, Tab.QUEUE, Icons.Filled.List, R.string.tab_queue)
                            TabItem(tab, Tab.BROWSER, Icons.Filled.Search, R.string.tab_browser)
                            TabItem(tab, Tab.SETTINGS, Icons.Filled.Settings, R.string.tab_settings)
                        }
                    },
                ) { padding ->
                    val modifier = Modifier.padding(padding)
                    when (tab) {
                        Tab.DOWNLOAD -> DownloadScreen(vm, modifier)
                        Tab.QUEUE -> QueueScreen(vm, modifier)
                        Tab.BROWSER -> BrowserScreen(vm, modifier)
                        Tab.SETTINGS -> SettingsScreen(vm, modifier)
                    }
                }
            }
        }
    }

    @androidx.compose.runtime.Composable
    private fun androidx.compose.foundation.layout.RowScope.TabItem(
        current: Tab,
        target: Tab,
        icon: androidx.compose.ui.graphics.vector.ImageVector,
        label: Int,
    ) {
        NavigationBarItem(
            selected = current == target,
            onClick = { vm.tab.value = target },
            icon = { Icon(icon, contentDescription = null) },
            label = { Text(stringResource(label)) },
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShare(intent)
    }

    /** "Share → Nazzel" from any app drops the link straight into the download box. */
    private fun handleShare(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val link = Urls.extract(intent.getStringExtra(Intent.EXTRA_TEXT)) ?: return
        vm.setUrl(link)
        vm.tab.value = Tab.DOWNLOAD
        vm.analyze()
    }
}
