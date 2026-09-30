package app.nazzel.core

object Urls {
    private val urlInText = Regex("""https?://[^\s<>"']+""")

    /** Pulls the first http(s) link out of shared text such as "Check this out https://…". */
    fun extract(text: String?): String? = text?.let { urlInText.find(it)?.value?.trimEnd('.', ',', ')', ']') }

    /** Turns address-bar input into a URL, falling back to a search query. */
    fun fromAddressBar(input: String): String {
        val t = input.trim()
        return when {
            t.startsWith("http://") || t.startsWith("https://") -> t
            ' ' !in t && '.' in t -> "https://$t"
            else -> "https://duckduckgo.com/?q=" + java.net.URLEncoder.encode(t, "UTF-8")
        }
    }
}
