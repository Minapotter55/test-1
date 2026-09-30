package app.nazzel.data

import app.nazzel.core.Redactor
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** In-memory diagnostic log. Every line is redacted on the way in, so nothing sensitive is ever held. */
object LogStore {
    private const val MAX_LINES = 500
    private val lines = ArrayDeque<String>()
    private val time = SimpleDateFormat("HH:mm:ss", Locale.US)

    @Synchronized
    fun log(message: String) {
        val stamped = "${time.format(Date())} ${Redactor.redact(message)}"
        lines.addLast(stamped)
        while (lines.size > MAX_LINES) lines.removeFirst()
    }

    @Synchronized
    fun dump(): String = lines.joinToString("\n")

    @Synchronized
    fun clear() = lines.clear()
}
