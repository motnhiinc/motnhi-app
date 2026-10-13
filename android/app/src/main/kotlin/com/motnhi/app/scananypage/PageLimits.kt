package com.motnhi.app.scananypage

internal object PageLimits {
    fun failureCode(texts: List<String>): String? {
        val nonempty = texts.filter { it.isNotBlank() }
        if (nonempty.isEmpty()) return "no_text"
        if (nonempty.size > 40 || nonempty.sumOf { it.codePointCount(0, it.length) } > 4000) return "page_too_long"
        return null
    }
}
