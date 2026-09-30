package app.nazzel.core

/**
 * Masks sensitive values before text is written to logs, shown in diagnostics, or copied to the clipboard.
 * Signed media URLs routinely carry tokens in the query string, so query values are hidden wholesale
 * and only parameter names are kept for debugging.
 */
object Redactor {
    private const val MASK = "***"

    private val urlQuery = Regex("""(https?://[^\s?#"'<>]+)\?([^\s#"'<>]*)""")
    private val headerLine = Regex(
        """(?i)\b(authorization|cookie|set-cookie|x-api-key|proxy-authorization)(\s*[:=]\s*)([^\r\n]+)""",
    )
    private val keyValue = Regex(
        """(?i)\b(token|access_token|refresh_token|api_key|apikey|key|sig|signature|secret|password|passwd|session|sessionid|auth)(=)([^\s&"']+)""",
    )
    private val bearer = Regex("""(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+""")
    private val email = Regex("""[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}""")
    private val userInfo = Regex("""(https?://)[^/\s:@]+:[^/\s@]+@""")

    fun redact(text: String): String {
        var out = text
        out = userInfo.replace(out) { "${it.groupValues[1]}$MASK@" }
        out = urlQuery.replace(out) { m ->
            val params = m.groupValues[2].split('&').filter { it.isNotEmpty() }.joinToString("&") { p ->
                val name = p.substringBefore('=')
                "$name=$MASK"
            }
            "${m.groupValues[1]}?$params"
        }
        out = headerLine.replace(out) { "${it.groupValues[1]}${it.groupValues[2]}$MASK" }
        out = bearer.replace(out, "Bearer $MASK")
        out = keyValue.replace(out) { m ->
            if (m.groupValues[3] == MASK) m.value else "${m.groupValues[1]}=$MASK"
        }
        out = email.replace(out, "$MASK@$MASK")
        return out
    }
}
