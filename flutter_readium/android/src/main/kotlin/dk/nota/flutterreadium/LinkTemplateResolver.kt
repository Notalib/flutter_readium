package dk.nota.flutterreadium

import org.readium.r2.shared.publication.Href
import org.readium.r2.shared.publication.Link
import java.util.concurrent.ConcurrentHashMap

internal sealed interface LinkTemplateResolution {
    data class Resolved(
        val link: Link,
    ) : LinkTemplateResolution

    data class Unresolved(
        val reason: Reason,
        val missingVariables: List<String> = emptyList(),
    ) : LinkTemplateResolution {
        enum class Reason {
            MISSING_VARIABLE,
            INVALID_TEMPLATE,
            INVALID_HREF,
        }
    }
}

internal object LinkTemplateResolver {
    private val reportedFailures = ConcurrentHashMap.newKeySet<String>()

    fun resolve(
        link: Link,
        parameters: Map<String, String> = emptyMap(),
    ): LinkTemplateResolution {
        if (!link.href.isTemplated) {
            return LinkTemplateResolution.Resolved(link)
        }

        if (!isValidTemplate(link.href.toString())) {
            return LinkTemplateResolution.Unresolved(
                LinkTemplateResolution.Unresolved.Reason.INVALID_TEMPLATE,
            )
        }

        val missing =
            link.href.parameters
                .orEmpty()
                .filter { it !in parameters }
                .distinct()
                .sorted()
        if (missing.isNotEmpty()) {
            return LinkTemplateResolution.Unresolved(
                LinkTemplateResolution.Unresolved.Reason.MISSING_VARIABLE,
                missing,
            )
        }

        val expanded = link.url(parameters = parameters)
        val resolvedHref = Href(expanded)
        return if (resolvedHref == null || resolvedHref.isTemplated) {
            LinkTemplateResolution.Unresolved(
                LinkTemplateResolution.Unresolved.Reason.INVALID_HREF,
            )
        } else {
            LinkTemplateResolution.Resolved(link.copy(href = resolvedHref))
        }
    }

    fun shouldReport(
        link: Link,
        resolution: LinkTemplateResolution.Unresolved,
    ): Boolean = reportedFailures.add("${link.href}|${resolution.reason}|${resolution.missingVariables}")

    fun parameters(
        resourceLink: Link?,
        sidecarLink: Link? = null,
    ): Map<String, String> {
        if (resourceLink == null) return emptyMap()

        val href = resourceLink.href.toString()
        val parameters =
            mutableMapOf(
                "ref" to href,
                "resource" to href,
            )
        val fragment = href.substringAfter('#', "")
        if (fragment.isNotEmpty()) {
            parameters["id"] = fragment
        }
        if (sidecarLink != null) {
            parameters["mediaOverlay"] = sidecarLink.href.toString()
            parameters["media-overlay"] = sidecarLink.href.toString()
        }
        return parameters
    }

    private fun isValidTemplate(href: String): Boolean {
        val expression = Regex("""\{([^{}]*)\}""")
        var cursor = 0
        while (cursor < href.length) {
            val open = href.indexOf('{', cursor)
            val close = href.indexOf('}', cursor)
            if (open == -1) return close == -1
            if (close == -1 || close < open) return false

            val body = href.substring(open + 1, close)
            val variables = if (body.startsWith('?')) body.substring(1) else body
            if (variables.isEmpty() || (!body.startsWith("?") && body.startsWith("#"))) {
                return false
            }
            if (
                variables.split(',').any {
                    !it.matches(Regex("""[A-Za-z][A-Za-z0-9._-]*"""))
                }
            ) {
                return false
            }

            cursor = close + 1
        }
        return expression.findAll(href).count() > 0 || href.none { it == '}' }
    }
}
