package dk.nota.flutterreadium

import android.util.Xml
import org.readium.r2.shared.publication.Locator
import org.xmlpull.v1.XmlPullParser
import java.io.ByteArrayInputStream

private const val TAG = "XhtmlIdTree"

/**
 * Element ids of an XHTML document in document order, with each element's subtree.
 *
 * ToC entries can target a container (e.g. a newspaper `<section>` or `<aside>`) that has no
 * Sync Narration cue and that the ContentService never yields; only its descendants do. This
 * maps such a target to the first descendant that does. See ADR 0001.
 */
class XhtmlIdTree(
    xhtml: ByteArray,
) {
    val ids = mutableListOf<String>()

    /** The descendants of `ids[i]` are `ids.subList(i + 1, subtreeEnd[i])`. */
    private val subtreeEnd = mutableListOf<Int>()

    init {
        // Index into ids for each open element, or null when it has no id.
        val open = ArrayDeque<Int?>()
        // Ids after an XML parse error are missing; elements still open then own every id read.
        try {
            val parser = Xml.newPullParser()
            parser.setInput(ByteArrayInputStream(xhtml), null)
            var event = parser.eventType
            while (event != XmlPullParser.END_DOCUMENT) {
                when (event) {
                    XmlPullParser.START_TAG -> {
                        val id = parser.getAttributeValue(null, "id")
                        if (id == null) {
                            open.addLast(null)
                        } else {
                            open.addLast(ids.size)
                            ids.add(id)
                            subtreeEnd.add(ids.size)
                        }
                    }

                    XmlPullParser.END_TAG -> {
                        open.removeLastOrNull()?.let { subtreeEnd[it] = ids.size }
                    }
                }
                event = parser.next()
            }
        } catch (e: Exception) {
            PluginLog.d(TAG, "::init - XML parse stopped: $e")
        }
        open.filterNotNull().forEach { subtreeEnd[it] = ids.size }
    }

    /** The first id inside element [id], excluding [id] itself, that is in [candidates]. */
    fun firstDescendant(
        id: String,
        candidates: Set<String>,
    ): String? {
        val start = ids.indexOf(id).takeIf { it >= 0 } ?: return null
        return ids.subList(start + 1, subtreeEnd[start]).firstOrNull { it in candidates }
    }

    /** A known cue-less element seeks forward; a missing id keeps the caller's fallback policy. */
    fun anchor(
        locator: Locator,
        textId: String,
        cueIds: Set<String>,
    ): Locator? {
        if (locator.locations.fragments.any { it.startsWith("t=") }) return locator
        val start = ids.indexOf(textId).takeIf { it >= 0 } ?: return locator
        val first = ids.subList(start, ids.size).firstOrNull { it in cueIds } ?: return null
        return locator.copy(
            locations =
                locator.locations.copy(
                    fragments = listOf(first),
                    otherLocations = locator.locations.otherLocations + ("cssSelector" to "#$first"),
                ),
        )
    }
}
