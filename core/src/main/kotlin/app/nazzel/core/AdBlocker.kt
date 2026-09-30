package app.nazzel.core

/** Minimal host-based blocker for the built-in browser: a host is blocked if it or any parent domain is listed. */
class AdBlocker(hosts: Collection<String>) {
    private val blocked = hosts.map { it.trim().lowercase() }.filter { it.isNotEmpty() && !it.startsWith("#") }.toHashSet()

    fun isBlocked(host: String?): Boolean {
        var h = host?.lowercase()?.trimEnd('.') ?: return false
        while (true) {
            if (h in blocked) return true
            val dot = h.indexOf('.')
            if (dot < 0) return false
            h = h.substring(dot + 1)
        }
    }

    companion object {
        /** Parses hosts-file lines ("0.0.0.0 example.com") as well as bare domains. */
        fun parse(lines: Sequence<String>): AdBlocker = AdBlocker(
            lines.map { it.substringBefore('#').trim() }
                .filter { it.isNotEmpty() }
                .map { it.split(Regex("\\s+")).last() }
                .toList(),
        )
    }
}
