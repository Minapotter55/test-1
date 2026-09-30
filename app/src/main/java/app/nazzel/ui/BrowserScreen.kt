package app.nazzel.ui

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.nazzel.MainViewModel
import app.nazzel.R
import app.nazzel.core.AdBlocker
import app.nazzel.core.DetectedStream
import app.nazzel.core.StreamDetector
import app.nazzel.core.Urls
import java.io.ByteArrayInputStream

/**
 * Built-in browser used as a fallback when yt-dlp can't extract a page directly. It watches every
 * request the page makes and lists HLS (.m3u8), DASH (.mpd) and plain video files it sees.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun BrowserScreen(vm: MainViewModel, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val streams by vm.streams.collectAsStateWithLifecycle()
    val request by vm.browserRequest.collectAsStateWithLifecycle()
    var address by remember { mutableStateOf("") }
    var pageTitle by remember { mutableStateOf<String?>(null) }
    var canGoBack by remember { mutableStateOf(false) }
    val blocker = remember {
        context.assets.open("adblock_hosts.txt").bufferedReader().useLines { AdBlocker.parse(it.toList().asSequence()) }
    }

    val webView = remember {
        WebView(context).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, req: WebResourceRequest): WebResourceResponse? {
                    val url = req.url.toString()
                    if (blocker.isBlocked(req.url.host)) {
                        return WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(ByteArray(0)))
                    }
                    StreamDetector.classify(url)?.let { kind ->
                        val page = req.requestHeaders["Referer"]
                        view.post { vm.onStreamDetected(DetectedStream(url, kind, page ?: view.url)) }
                    }
                    return null
                }

                override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                    address = url
                }

                override fun onPageFinished(view: WebView, url: String) {
                    pageTitle = view.title
                    canGoBack = view.canGoBack()
                }
            }
        }
    }
    DisposableEffect(Unit) { onDispose { webView.destroy() } }

    LaunchedEffect(request) {
        request?.let {
            vm.clearStreams()
            webView.loadUrl(it)
            vm.browserRequest.value = null
        }
    }

    BackHandler(enabled = canGoBack) { webView.goBack() }

    Column(modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            OutlinedTextField(
                value = address,
                onValueChange = { address = it },
                placeholder = { Text(stringResource(R.string.address_hint)) },
                singleLine = true,
                modifier = Modifier.weight(1f),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = {
                    vm.clearStreams()
                    webView.loadUrl(Urls.fromAddressBar(address))
                }),
            )
            TextButton(onClick = {
                vm.clearStreams()
                webView.loadUrl(Urls.fromAddressBar(address))
            }) { Text(stringResource(R.string.go)) }
        }
        Text(
            stringResource(R.string.adblock_on),
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = 12.dp),
        )

        AndroidView(factory = { webView }, modifier = Modifier.weight(1f).fillMaxWidth())

        HorizontalDivider()
        Text(
            stringResource(R.string.detected_streams, streams.size),
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(start = 12.dp, top = 8.dp),
        )
        if (streams.isEmpty()) {
            Text(stringResource(R.string.no_streams), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(12.dp))
        } else {
            LazyColumn(Modifier.fillMaxWidth().heightIn(max = 200.dp)) {
                items(streams, key = { it.url }) { stream ->
                    ListItem(
                        headlineContent = { Text(stream.url, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        supportingContent = { Text(stream.kind.label) },
                        trailingContent = {
                            TextButton(onClick = {
                                vm.downloadStream(stream, pageTitle, webView.settings.userAgentString)
                            }) { Text(stringResource(R.string.download)) }
                        },
                    )
                }
            }
        }
    }
}
