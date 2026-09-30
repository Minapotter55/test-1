package app.nazzel.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class YtDlpArgsTest {
    @Test
    fun videoWith60FpsAndSubtitles() {
        val args = YtDlpArgs.build(
            DownloadOptions(MediaMode.Video(VideoQuality.P2160, prefer60Fps = true), subtitles = true),
            "/out", "/tmp/paths.txt",
        )
        assertEquals("res:2160,fps", args[args.indexOf("-S") + 1])
        assertEquals("mp4/mkv", args[args.indexOf("--merge-output-format") + 1])
        assertTrue("--embed-subs" in args)
        assertEquals("ar,en", args[args.indexOf("--sub-langs") + 1])
        assertEquals("/out", args[args.indexOf("-P") + 1])
        assertTrue("--no-playlist" in args)
    }

    @Test
    fun videoWithout60FpsCapsFrameRate() {
        assertEquals("res:1080,fps:30", YtDlpArgs.sortString(VideoQuality.P1080, prefer60Fps = false))
        assertEquals("res,fps", YtDlpArgs.sortString(VideoQuality.BEST, prefer60Fps = true))
    }

    @Test
    fun audioExtraction() {
        val args = YtDlpArgs.build(DownloadOptions(MediaMode.Audio(AudioFormat.OPUS), subtitles = true), "/o", "/p")
        assertEquals("opus", args[args.indexOf("--audio-format") + 1])
        assertTrue("-x" in args)
        assertFalse("--embed-subs" in args)
        val wav = YtDlpArgs.build(DownloadOptions(MediaMode.Audio(AudioFormat.WAV)), "/o", "/p")
        assertFalse("--audio-quality" in wav)
    }

    @Test
    fun headersArePassedThrough() {
        val args = YtDlpArgs.build(DownloadOptions(headers = mapOf("Referer" to "https://a.com/")), "/o", "/p")
        assertEquals("Referer:https://a.com/", args[args.indexOf("--add-header") + 1])
    }
}

class RedactorTest {
    @Test
    fun masksQueryValuesButKeepsNames() {
        assertEquals(
            "GET https://cdn.x.com/v.m3u8?token=***&exp=*** done",
            Redactor.redact("GET https://cdn.x.com/v.m3u8?token=abc123&exp=99 done"),
        )
    }

    @Test
    fun masksHeadersCredentialsAndEmails() {
        val out = Redactor.redact(
            "Cookie: sid=1; a=2\nAuthorization: Bearer abc.def\nuser a.b@mail.com https://u:p@host.com/x password=hunter2",
        )
        assertFalse(out.contains("sid=1"))
        assertFalse(out.contains("abc.def"))
        assertFalse(out.contains("a.b@mail.com"))
        assertFalse(out.contains("u:p@"))
        assertFalse(out.contains("hunter2"))
        assertTrue(out.contains("https://***@host.com/x"))
    }

    @Test
    fun leavesPlainTextAlone() {
        assertEquals("[download]  42.0% of 10MiB", Redactor.redact("[download]  42.0% of 10MiB"))
    }
}

class StreamDetectorTest {
    @Test
    fun classifiesByExtensionAndMime() {
        assertEquals(StreamKind.HLS, StreamDetector.classify("https://a.com/master.m3u8?x=1"))
        assertEquals(StreamKind.DASH, StreamDetector.classify("https://a.com/manifest.mpd"))
        assertEquals(StreamKind.FILE, StreamDetector.classify("https://a.com/v.mp4#t=3"))
        assertEquals(StreamKind.HLS, StreamDetector.classify("https://a.com/play", "application/vnd.apple.mpegurl; charset=utf-8"))
        assertNull(StreamDetector.classify("https://a.com/app.js"))
        assertNull(StreamDetector.classify("blob:https://a.com/1234"))
        assertNull(StreamDetector.classify("https://a.com/m3u8-guide.html"))
    }
}

class AdBlockerAndUrlsTest {
    @Test
    fun blocksSubdomains() {
        val b = AdBlocker.parse(sequenceOf("# comment", "0.0.0.0 doubleclick.net", "ads.example.org"))
        assertTrue(b.isBlocked("stats.g.doubleclick.net"))
        assertTrue(b.isBlocked("ads.example.org"))
        assertFalse(b.isBlocked("example.org"))
        assertFalse(b.isBlocked(null))
    }

    @Test
    fun extractsAndNormalisesUrls() {
        assertEquals("https://youtu.be/abc", Urls.extract("Watch this: https://youtu.be/abc."))
        assertNull(Urls.extract("no link here"))
        assertEquals("https://example.com", Urls.fromAddressBar("example.com"))
        assertTrue(Urls.fromAddressBar("cat videos").startsWith("https://duckduckgo.com/?q=cat+videos"))
    }
}
