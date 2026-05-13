@file:OptIn(ExperimentalReadiumApi::class, ExperimentalReadiumApi::class)

package dk.nota.flutter_readium

import android.util.Log
import androidx.core.graphics.toColorInt
import dk.nota.flutter_readium.models.FlutterMediaOverlay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.extensions.time
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Href
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.html.cssSelector
import org.readium.r2.shared.publication.services.content.Content
import org.readium.r2.shared.publication.services.content.content
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.shared.util.resource.Resource
import org.readium.r2.shared.util.resource.TransformingResource
import org.readium.r2.shared.util.resource.filename
import java.util.Locale
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import org.readium.r2.navigator.preferences.Color as ReadiumColor

private const val TAG = "ReadiumExtensions"

fun readiumColorFromCSS(cssColor: String): ReadiumColor {
    val color = cssColor.toColorInt()
    return ReadiumColor(color)
}

fun decorationFromMap(decoMap: Map<String, Any>): Decoration? {
    try {
        val id = decoMap["decorationId"] as String
        val locator =
            Locator.fromJSON(jsonDecode(decoMap["locator"] as String) as JSONObject)
                ?: throw Exception("Failed to deserialize locator")

        @Suppress("UNCHECKED_CAST")
        val style =
            decorationStyleFromMap(decoMap["style"] as Map<String, String>)
                ?: throw Exception("Failed to deserialize decoration")
        return Decoration(id, locator, style)
    } catch (ex: Exception) {
        Log.e("ReadiumExtensions", "Error mapping JSONObject to Decoration.Style: $ex")
        return null
    }
}

fun decorationStyleFromMap(decoMap: Map<*, *>?): Decoration.Style? {
    try {
        if (decoMap == null) return null

        val styleStr = decoMap["style"] as String
        val tintColorStr = decoMap["tint"] as String
        val style =
            when (styleStr) {
                "underline" -> Decoration.Style.Underline(readiumColorFromCSS(tintColorStr).int)
                "highlight" -> Decoration.Style.Highlight(readiumColorFromCSS(tintColorStr).int)
                else -> Decoration.Style.Highlight(readiumColorFromCSS(tintColorStr).int)
            }
        return style
    } catch (ex: Exception) {
        Log.e("ReadiumExtensions", "Error mapping JSONObject to Decoration.Style: $ex")
        return null
    }
}

private const val READIUM_FLUTTER_PATH_PREFIX =
    "https://readium/assets/flutter_assets/packages/flutter_readium"

// Helper for injecting extra files into an epub
fun Resource.injectScriptsAndStyles(
    tocIds: List<String>,
    epubPreferences: FlutterEpubPreferences?,
): Resource =
    TransformingResource(this) { bytes ->
        val props = this.properties().getOrNull()
        val filename = props?.filename ?: return@TransformingResource Try.success(bytes)

        // Skip all non-html files
        if (!filename.endsWith("html", ignoreCase = true)) {
            return@TransformingResource Try.success(bytes)
        }

        val content = bytes.toString(Charsets.UTF_8).trim()
        val headEndIndex = content.indexOf("</head>", 0, true)
        if (headEndIndex == -1) {
            Log.w(TAG, "No </head> element found, cannot inject scripts in: $filename")
            return@TransformingResource Try.success(bytes)
        }

        val injectStyle = epubPreferences?.toInjectableStyleSheet()

        if (content.take(headEndIndex).contains(READIUM_FLUTTER_PATH_PREFIX)) {
            injectStyle?.let {
                if (!content.contains(it)) {
                    Log.d(
                        TAG,
                        "Scripts already loaded for $filename, but custom css needs to be updated.",
                    )
                    return@TransformingResource Try.success(
                        content
                            .replace(
                                "</head>",
                                "$it</head>",
                                true,
                            ).toByteArray(),
                    )
                }
            }

            Log.d(TAG, "Skip injecting - already done for: $filename")
            return@TransformingResource Try.success(bytes)
        }

        Log.d(TAG, "Injecting files into: $filename")

        val injectLines =
            listOf(
                """<script type="text/javascript" src="$READIUM_FLUTTER_PATH_PREFIX/assets/helpers/flutterReadiumTools.js"></script>""",
                """<link rel="stylesheet" type="text/css" href="$READIUM_FLUTTER_PATH_PREFIX/assets/helpers/flutterReadiumTools.css"></link>""",
                """<script type="text/javascript">
                const isAndroid = true;
                const isIos = false;
                window.readiumTocIDs = ${jsonEncode(tocIds)};
            </script>
            $injectStyle
            """,
            )
        val newContent =
            StringBuilder(content)
                .insert(headEndIndex, "\n" + injectLines.joinToString("\n") + "\n")
                .toString()

        Try.success(newContent.toByteArray())
    }

val syncNarrationsMediaType = MediaType("application/vnd.syncnarr+json")

/**
 * Check if the publication has any media overlays.
 */
fun Publication.hasMediaOverlays() =
    this.readingOrder.any { r ->
        r.alternates.any { a ->
            a.mediaType == syncNarrationsMediaType
        } || r.properties["media-overlay"] != null
    }

/**
 * Get the media overlays for the publication, if any.
 * Note: If an item in the reading order does not have a media overlay, it will be represented by null
 */
suspend fun Publication.getMediaOverlays(): List<FlutterMediaOverlay?>? {
    if (!hasMediaOverlays()) return null

    // Flatten TOC for title lookup
    val toc = tableOfContents.flattenChildren().map { Pair(it.href.toString(), it) }

    // Remember last matched TOC item for titles
    var lastTocMatch: Pair<String, Link>? = null

    val overlayLinks =
        this.readingOrder.mapNotNull { r ->
            r.alternates
                .find { a -> a.mediaType == syncNarrationsMediaType }
                ?.copy(title = r.title)
        }

    // Fetch+parse every overlay JSON in parallel on IO. Cap is configurable so we don't open
    // dozens of sockets to the origin at once.
    val parsed: List<FlutterMediaOverlay?> =
        coroutineScope {
            val fetchConcurrency =
                BuildConfig.MEDIA_OVERLAY_FETCH_CONCURRENCY.takeIf { it > 0 } ?: run {
                    Log.w(
                        TAG,
                        "::getMediaOverlays() - invalid MEDIA_OVERLAY_FETCH_CONCURRENCY=" +
                            "${BuildConfig.MEDIA_OVERLAY_FETCH_CONCURRENCY}; falling back to 1",
                    )
                    1
                }
            val gate = Semaphore(permits = fetchConcurrency)
            overlayLinks
                .mapIndexed { index, link ->
                    async(Dispatchers.IO) {
                        gate.withPermit {
                            val resource = get(link)
                            if (resource == null) {
                                Log.i(TAG, "::getMediaOverlays() - no resource for ${link.href}")
                                return@withPermit null
                            }

                            val jsonString = resource.read().getOrNull()?.let { String(it) }
                            if (jsonString == null) {
                                Log.i(
                                    TAG,
                                    "::getMediaOverlays() - unable to load resource ${link.href}",
                                )
                                return@withPermit null
                            }

                            val duration =
                                link.duration?.takeIf { it > 0.0 } ?: return@withPermit null

                            return@withPermit FlutterMediaOverlay.fromJson(
                                JSONObject(jsonString),
                                index + 1,
                                null,
                                link.title ?: "",
                                duration,
                            )
                        }
                    }
                }.awaitAll()
        }

    // TOC-matching pass stays sequential — it walks shared mutable state
    // (`lastTocMatch`) in reading order. It's pure CPU and not the bottleneck.
    return parsed.map { mo ->
        if (mo == null) return@map null

        val items =
            mo.items.map { item ->
                // Find best matching title from TOC
                val match =
                    toc.find { tocItem ->
                        tocItem.first == item.text
                    }

                if (match?.second != null) {
                    lastTocMatch = match
                    item.copy(
                        title = match.second.title ?: "",
                        tocHref = match.second.href.resolve(),
                    )
                } else if (lastTocMatch?.second != null && lastTocMatch.first.substringBefore("#") == item.textFile) {
                    item.copy(
                        title = lastTocMatch.second.title ?: "",
                        tocHref = lastTocMatch.second.href.resolve(),
                    )
                } else {
                    item
                }
            }

        return@map FlutterMediaOverlay(items)
    }
}

/**
 * Create a new Publication containing only the audio files from the media overlays.
 * This is used for the Sync Audiobook navigator.
 * Returns the new Publication and the list of media overlays, if any.
 * If there are no media overlays, returns the original publication and null.
 */
@OptIn(InternalReadiumApi::class)
suspend fun Publication.makeSyncAudiobook(): Pair<Publication, List<FlutterMediaOverlay?>?> {
    if (!hasMediaOverlays()) {
        return Pair(this, null)
    }

    val mediaOverlays = getMediaOverlays() ?: return Pair(this, null)

    val manifest =
        Manifest(
            context = context,
            metadata = metadata.copy(conformsTo = setOf(Publication.Profile.AUDIOBOOK)),
            resources = resources,
            links = links,
            readingOrder =
                mediaOverlays
                    .mapNotNull { overlay ->
                        val item = overlay?.items?.first() ?: return@mapNotNull null

                        Href
                            .invoke(item.audioFile)
                            ?.let { href ->
                                Link(
                                    href,
                                    mediaType = item.audioMediaType,
                                    duration = overlay.duration,
                                    title = item.title,
                                )
                            }
                    }.filter { it.duration != null && it.duration!! > 0.0 },
        )

    val pseudoPublication = Publication.Builder(manifest, container).build()
    return Pair(pseudoPublication, mediaOverlays)
}

/**
 * Get the text id from a Locator's fragments or css selector, if any.
 */
fun Locator.getTextId(): String? {
    val cssFragment =
        locations.cssSelector ?: locations.fragments.find {
            it.isNotEmpty() && !it.contains("=")
        } ?: return null
    return cssFragment.removePrefix("#")
}

/**
 * Make a new copy with a new time fragment
 */
fun Locator.copyWithTimeFragment(time: Duration): Locator {
    // IMPORTANT: Readium expects time fragment to be an integer.
    return copyWithTimeFragment(time.inWholeSeconds)
}

/**
 * Make a new copy with a new time fragment
 */
fun Locator.copyWithTimeFragment(time: Number): Locator =
    copyWithLocations(
        fragments = makeTimeFragments(time),
    )

/**
 * Helper for making a valid t=<time> fragment for kotlin-toolkit.
 * TODO: Once https://github.com/readium/kotlin-toolkit/issues/782 is fixed, we will no longer need
 * to cast to int.
 */
fun makeTimeFragments(time: Number): List<String> = listOf("t=${time.toInt()}")

/**
 * Get progression from [Locator.Locations.progression]
 */
val Locator.progression: Double?
    get() = locations.progression

/**
 * Computes the time position from the resource duration.
 * This takes progression value over time fragment, if both are present
 */
@OptIn(InternalReadiumApi::class)
fun Locator.Locations.timeWithDuration(duration: Duration?): Duration? =
    letIfBothNotNull(duration?.inWholeSeconds?.seconds, progression)?.let { (d, p) -> d * p }
        ?: time

/**
 * Computes the time position from the resource duration.
 * This takes progression value over time fragment, if both are present
 */
fun Locator.Locations.timeWithDuration(duration: Int?): Duration? = timeWithDuration(duration?.seconds)

/**
 * Computes the time position from the resource duration.
 * This takes progression value over time fragment, if both are present
 */
fun Locator.Locations.timeWithDuration(duration: Double?): Duration? = timeWithDuration(duration?.seconds)

/**
 * Find a link in the reading order from its href.
 */
fun Publication.findReadingOrderLink(href: Url): Link? = readingOrder.firstOrNull { href.isEquivalent(it.href.resolve()) }

/**
 * Get the duration for an item in the reading order.
 */
fun Publication.getReadingOrderItemDuration(href: Url): Duration? = findReadingOrderLink(href)?.duration?.takeIf { it >= 0.0 }?.seconds

/**
 * Helper for getting all cssSelectors for a HTML document.
 */
suspend fun Publication.findAllCssSelectors(href: Url): List<String>? {
    if (!conformsTo(Publication.Profile.EPUB)) {
        Log.d(TAG, ":findAllCssSelectors - this only works for an EPUB Profile")
        return null
    }

    val cleanHref = href.cleanHref()

    val contentItems =
        content(
            Locator(
                href = cleanHref,
                mediaType = MediaType.XHTML,
            ),
        ) ?: run {
            Log.d(TAG, ":findAllCssSelectors - no content service found")
            return null
        }

    val ids = arrayListOf<String>()
    for (element in contentItems) {
        if (element !is Content.TextElement) {
            continue
        }

        if (element.locator.href
                .cleanHref()
                .path != cleanHref.path
        ) {
            // We iterated to the next document, stopping
            break
        }

        // We are only interested in #id type of cssSelectors.
        val cssSelector =
            element.locator.locations.cssSelector
                ?.takeIf { it.startsWith("#") } ?: continue

        ids.add(cssSelector)
    }

    return ids
}

/**
 * Get the Table of Content title from a href.
 */
fun Publication.getTitleFromTocHref(tocHref: String?): String? {
    if (tocHref == null || tocHref.isEmpty()) return null

    for (tocLink in tableOfContents.flattenChildren()) {
        if (tocLink.href
                .resolve()
                .toString()
                .equals(tocHref, ignoreCase = true)
        ) {
            return tocLink.title
        }
    }

    return null
}

/**
 * Remove query and fragment from the Url
 */
fun Url.cleanHref() = removeFragment().removeQuery()

val Href.fragmentParameters: Map<String, String>
    get() =
        resolve()
            .fragment
            // Splits parameters
            ?.split("&")
            ?.filter { !it.startsWith("=") }
            ?.map { it.split("=") }
            // Only keep named parameters
            ?.filter { it.size == 2 }
            ?.associate { it[0].trim().lowercase(Locale.ROOT) to it[1].trim() }
            ?: mapOf()

/**
 * Media fragment, used for example in audiobooks.
 *
 * https://www.w3.org/TR/media-frags/
 */
val Href.time: Duration?
    get() =
        fragmentParameters["t"]?.toIntOrNull()?.seconds

/**
 * Returns a list of `Link` after flattening the `children`.
 */
fun List<Link>.flattenChildren(): List<Link> {
    fun Link.flattenChildren(): List<Link> = listOf(this) + children.flattenChildren()

    return flatMap { it.flattenChildren() }
}

private const val tocHrefLocationKey = "tocHref"

/**
 * A CSS Selector.
 */
val Locator.Locations.tocHref: String?
    get() = this[tocHrefLocationKey] as? String

/**
 * Add a tocHref to Locator.locations.otherLocations.
 */
fun Locator.copyWithTocHref(tocLink: Link): Locator = this.copyWithTocHref(tocLink.href.resolve())

/**
 * Add a tocHref to Locator.locations.otherLocations.
 */
fun Locator.copyWithTocHref(tocUrl: Url?): Locator {
    if (tocUrl == null) return copy()

    return this.copyWithAdditionalLocations(mapOf(tocHrefLocationKey to tocUrl.toString()))
}

/**
 * Make a copy of the locator by adding more values to Locator.Locations.otherLocations.
 */
fun Locator.copyWithAdditionalLocations(additionalValues: Map<String, Any>) =
    copyWithLocations(
        otherLocations = locations.otherLocations + additionalValues,
    )

/**
 * Add currentPage and totalPages to [Locator.locations]
 */
fun Locator.addPageNumber(
    pageIndex: Int,
    totalPages: Int,
) = copyWithAdditionalLocations(
    mapOf(
        "currentPage" to pageIndex,
        "totalPages" to totalPages,
    ),
)
