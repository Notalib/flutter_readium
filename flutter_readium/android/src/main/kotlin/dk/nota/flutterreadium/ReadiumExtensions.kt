@file:OptIn(ExperimentalReadiumApi::class, ExperimentalReadiumApi::class)

package dk.nota.flutterreadium

import android.graphics.Color
import android.util.Xml
import androidx.core.graphics.toColorInt
import dk.nota.flutterreadium.models.FlutterMediaOverlay
import dk.nota.flutterreadium.models.FlutterMediaOverlayItem
import dk.nota.flutterreadium.models.GuidedNavigationDocument
import dk.nota.flutterreadium.models.guidedNavigationMediaType
import dk.nota.flutterreadium.models.toMediaOverlays
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
import org.readium.r2.shared.publication.Layout
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.html.cssSelector
import org.readium.r2.shared.publication.services.content.Content
import org.readium.r2.shared.publication.services.content.content
import org.readium.r2.shared.util.Error
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.http.HttpError
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.shared.util.resource.Resource
import org.readium.r2.shared.util.resource.TransformingResource
import org.readium.r2.shared.util.resource.filename
import org.xmlpull.v1.XmlPullParser
import java.io.StringReader
import java.util.Locale
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.DurationUnit
import org.readium.r2.navigator.preferences.Color as ReadiumColor

private const val TAG = "ReadiumExtensions"

/**
 * The [HttpError] found by unwrapping this error's cause chain, if any. Readium/ExoPlayer
 * errors often wrap the real [HttpError] at some depth (e.g. `ReadError.Access(HttpError)`),
 * so a simple `is HttpError` check on the top-level error misses it. Shared by audio-stream
 * error classification and opening-error HTTP status mapping.
 */
internal tailrec fun Error.findHttpError(): HttpError? =
    when (this) {
        is HttpError -> this
        else -> cause?.findHttpError()
    }

fun readiumColorFromCSS(cssColor: String): ReadiumColor {
    val color = cssColor.toColorInt()
    return ReadiumColor(color)
}

fun decorationFromJson(jsonString: String): Decoration? =
    try {
        val json = jsonDecode(jsonString) as JSONObject
        val id = json.getString("id")
        val locator =
            Locator.fromJSON(json.getJSONObject("locator"))
                ?: throw Exception("Failed to deserialize locator")
        val styleJson = json.getJSONObject("style")
        val style =
            decorationStyleFromMap(
                mapOf(
                    "style" to styleJson.getString("style"),
                    "tint" to styleJson.getString("tint"),
                    "isActive" to styleJson.optBoolean("isActive", false),
                ),
            ) ?: throw Exception("Failed to deserialize decoration style")
        Decoration(id, locator, style)
    } catch (ex: Exception) {
        PluginLog.e("ReadiumExtensions", "Error parsing Decoration JSON: $ex")
        null
    }

fun decorationFromMap(decoMap: Map<String, Any>): Decoration? {
    try {
        val id = decoMap["id"] as String

        @Suppress("UNCHECKED_CAST")
        val locatorMap = decoMap["locator"] as Map<String, Any>
        val locator =
            Locator.fromJSON(JSONObject(locatorMap))
                ?: throw Exception("Failed to deserialize locator")

        @Suppress("UNCHECKED_CAST")
        val style =
            decorationStyleFromMap(decoMap["style"] as Map<String, Any>)
                ?: throw Exception("Failed to deserialize decoration")
        return Decoration(id, locator, style)
    } catch (ex: Exception) {
        PluginLog.e("ReadiumExtensions", "Error mapping JSONObject to Decoration.Style: $ex")
        return null
    }
}

fun decorationStyleFromMap(decoMap: Map<*, *>?): Decoration.Style? {
    try {
        if (decoMap == null) return null

        val styleStr = decoMap["style"] as String
        // `tint` is optional — null means no background colour.
        val tintColorStr = decoMap["tint"] as? String
        val isActive = decoMap["isActive"] as? Boolean ?: false
        // Use TRANSPARENT as the no-tint sentinel; templates check alpha == 0.
        val tint = tintColorStr?.let { readiumColorFromCSS(it).int } ?: Color.TRANSPARENT
        val style =
            when (styleStr) {
                "underline" -> Decoration.Style.Underline(tint, isActive)
                "spotlight" -> SpotlightStyle(tint)
                else -> Decoration.Style.Highlight(tint, isActive) // "highlight" + unknown
            }
        return style
    } catch (ex: Exception) {
        PluginLog.e("ReadiumExtensions", "Error mapping JSONObject to Decoration.Style: $ex")
        return null
    }
}

private const val READIUM_FLUTTER_PATH_PREFIX =
    "https://readium_assets/flutter_assets/packages/flutter_readium"

// Helper for injecting extra files into an epub.
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
            PluginLog.w(TAG, "No </head> element found, cannot inject scripts in: $filename")
            return@TransformingResource Try.success(bytes)
        }

        val injectStyle = epubPreferences?.toInjectableStyleSheet()

        if (content.take(headEndIndex).contains(READIUM_FLUTTER_PATH_PREFIX)) {
            injectStyle?.let {
                if (!content.contains(it)) {
                    PluginLog.d(
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

            PluginLog.d(TAG, "Skip injecting - already done for: $filename")
            return@TransformingResource Try.success(bytes)
        }

        PluginLog.d(TAG, "Injecting files into: $filename")

        val injectLines =
            listOf(
                """<script type="text/javascript" src="$READIUM_FLUTTER_PATH_PREFIX/assets/helpers/flutterReadiumTools.js"></script>""",
                """<link rel="stylesheet" type="text/css" href="$READIUM_FLUTTER_PATH_PREFIX/assets/helpers/flutterReadiumTools.css"></link>""",
                """<script type="text/javascript">
                const isAndroid = true;
                const isIos = false;
                window.readiumTocIDs = ${jsonEncode(tocIds)};
                window.updateNarrationSync = function(v) {
                    if (window.narrationSync) {
                        window.narrationSync.onNarrationSyncChanged(v === true);
                    }
                };
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
 * Check if the publication has any guided navigation data for audio-text synchronization.
 */
fun Publication.hasGuidedNavigationMediaOverlays() =
    links.any { it.mediaType == guidedNavigationMediaType } ||
        readingOrder.any { r -> r.alternates.any { it.mediaType == guidedNavigationMediaType } }

/**
 * Check if the publication has any audio-text synchronization data,
 * either as syncnarr media overlays or as guided navigation.
 */
fun Publication.hasSyncNarration() = hasMediaOverlays() || hasGuidedNavigationMediaOverlays()

private val mediaOverlayFetchConcurrency =
    BuildConfig.MEDIA_OVERLAY_FETCH_CONCURRENCY.takeIf { it > 0 } ?: run {
        PluginLog.w(
            TAG,
            "::getGuidedNavigationMediaOverlays - invalid MEDIA_OVERLAY_FETCH_CONCURRENCY=" +
                "${BuildConfig.MEDIA_OVERLAY_FETCH_CONCURRENCY}; falling back to 1",
        )
        1
    }

/**
 * Enriches a list of [FlutterMediaOverlay] with title and [FlutterMediaOverlayItem.tocHref] from
 * the publication's table of contents. Uses a sliding-window approach: items that don't match a
 * ToC entry directly inherit the last matched entry when they share the same text file.
 * Null overlay slots are passed through unchanged.
 */
private fun Publication.enrichOverlaysWithToc(overlays: List<FlutterMediaOverlay?>): List<FlutterMediaOverlay?> {
    val toc = tableOfContents.flattenChildren().map { it.href.toString() to it }
    var lastTocMatch: Pair<String, Link>? = null

    fun FlutterMediaOverlayItem.enrich(): FlutterMediaOverlayItem {
        val match = toc.find { it.first == text }
        return when {
            match != null -> {
                lastTocMatch = match
                copy(title = match.second.title ?: "", tocHref = match.second.href.resolve())
            }

            lastTocMatch != null && lastTocMatch!!.first.substringBefore("#") == textFile -> {
                copy(
                    title = lastTocMatch!!.second.title ?: "",
                    tocHref = lastTocMatch!!.second.href.resolve(),
                )
            }

            else -> {
                this
            }
        }
    }

    return overlays.map { overlay -> overlay?.let { ov -> FlutterMediaOverlay(ov.items.map { it.enrich() }) } }
}

/**
 * Get the media overlays for the publication, if any.
 * Note: If an item in the reading order does not have a media overlay, it will be represented by null
 */
suspend fun Publication.getMediaOverlays(): List<FlutterMediaOverlay?>? {
    if (!hasMediaOverlays()) return null

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
            val gate = Semaphore(permits = mediaOverlayFetchConcurrency)
            overlayLinks
                .mapIndexed { index, link ->
                    async(Dispatchers.IO) {
                        gate.withPermit {
                            val resource = get(link)
                            if (resource == null) {
                                PluginLog.w(TAG, "::getMediaOverlays() - no resource for ${link.href}")
                                return@withPermit null
                            }

                            val jsonString = resource.read().getOrNull()?.let { String(it) }
                            if (jsonString == null) {
                                PluginLog.w(
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

    return enrichOverlaysWithToc(parsed)
}

/**
 * Get the guided navigation media overlays for the publication, if any.
 *
 * Tries a single guided navigation document from [Publication.links] first (preferred, fewer
 * requests), then falls back to per-item alternates in [Publication.readingOrder].
 *
 * Returns null if the publication contains no guided navigation.
 */
suspend fun Publication.getGuidedNavigationMediaOverlays(): List<FlutterMediaOverlay>? {
    if (!hasGuidedNavigationMediaOverlays()) return null

    // Strategy 1: single guided navigation document in publication links (preferred).
    val singleDocLink = links.find { it.mediaType == guidedNavigationMediaType }
    if (singleDocLink != null) {
        val jsonString =
            get(singleDocLink)?.read()?.getOrNull()?.let { String(it) } ?: run {
                PluginLog.w(
                    TAG,
                    "::getGuidedNavigationMediaOverlays - unable to load ${singleDocLink.href}",
                )
                return null
            }
        val document =
            GuidedNavigationDocument.fromJSON(jsonString) ?: run {
                PluginLog.w(
                    TAG,
                    "::getGuidedNavigationMediaOverlays - failed to parse document from ${singleDocLink.href}",
                )
                return null
            }

        val rawOverlays =
            document.toMediaOverlays().mapNotNull { overlay ->
                val textFile = overlay.items.firstOrNull()?.textFile ?: return@mapNotNull null
                val roEntry =
                    readingOrder.withIndex().firstOrNull { (_, link) ->
                        Url.invoke(textFile)?.let { link.href.resolve().isEquivalent(it) } == true
                    }
                val position = (roEntry?.index ?: -1) + 1
                val duration = roEntry?.value?.duration ?: 0.0
                FlutterMediaOverlay(
                    overlay.items.map { item ->
                        item.copy(position = position, readingOrderItemDuration = duration)
                    },
                )
            }
        return enrichOverlaysWithToc(rawOverlays).filterNotNull()
    }

    // Strategy 2: per-item alternates in reading order.
    val hasGuidedNav =
        readingOrder.any { r -> r.alternates.any { it.mediaType == guidedNavigationMediaType } }
    if (!hasGuidedNav) return null

    val parsed: List<List<FlutterMediaOverlay>?> =
        coroutineScope {
            val gate = Semaphore(permits = mediaOverlayFetchConcurrency)
            readingOrder
                .mapIndexed { index, roLink ->
                    async(Dispatchers.IO) {
                        val guidedLink =
                            roLink.alternates.find { it.mediaType == guidedNavigationMediaType }
                                ?: return@async null
                        gate.withPermit {
                            val jsonString =
                                get(guidedLink)?.read()?.getOrNull()?.let { String(it) }
                                    ?: run {
                                        PluginLog.w(
                                            TAG,
                                            "::getGuidedNavigationMediaOverlays - unable to load ${guidedLink.href}",
                                        )
                                        return@withPermit null
                                    }
                            val document =
                                GuidedNavigationDocument.fromJSON(jsonString)
                                    ?: return@withPermit null
                            document.toMediaOverlays(
                                position = index + 1,
                                readiumOrderItemDuration = roLink.duration ?: 0.0,
                            )
                        }
                    }
                }.awaitAll()
        }

    return enrichOverlaysWithToc(parsed.flatMap { it ?: emptyList() }).filterNotNull()
}

/**
 * Create a new Publication containing only the audio files from the media overlays.
 * This is used for the Sync Audiobook navigator.
 * Returns the new Publication and the list of media overlays, if any.
 * If there are no media overlays, returns the original publication and null.
 * Guided navigation is preferred over syncnarr media overlays when both are present.
 */
@OptIn(InternalReadiumApi::class)
suspend fun Publication.makeSyncAudiobook(): Pair<Publication, List<FlutterMediaOverlay?>?> {
    if (!hasSyncNarration()) {
        return Pair(this, null)
    }

    val mediaOverlays: List<FlutterMediaOverlay?>? =
        if (hasGuidedNavigationMediaOverlays()) {
            getGuidedNavigationMediaOverlays()
        } else {
            getMediaOverlays()
        }
    if (mediaOverlays == null) return Pair(this, null)

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
 * Get the text id from a Locator's fragments or cssSelector, if any.
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
fun Locator.copyWithTimeFragment(time: Duration): Locator = copyWithTimeFragment(time.toSeconds)

/**
 * Make a new copy with a new time fragment
 */
fun Locator.copyWithTimeFragment(time: Number): Locator =
    copyWithLocations(
        fragments = makeTimeFragments(time),
    )

/**
 * Helper for making a valid t=<time> fragment for kotlin-toolkit.
 * to cast to int.
 */
fun makeTimeFragments(time: Number): List<String> = listOf("t=$time")

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
    letIfBothNotNull(duration?.toSeconds, progression)?.let { (d, p) -> d * p }?.seconds
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
        PluginLog.w(TAG, "::findAllCssSelectors - this only works for an EPUB Profile")
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
            PluginLog.w(TAG, "::findAllCssSelectors - no content service found")
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

private val tocHrefLocationKey = "tocHref"

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

// Resolves preferences against the publication's layout. The first-element top margin
// is a reflowable-text affordance, so it's dropped for every non-reflowable publication
// (fixed/scrolled layouts and image publications, which report no layout) where it would
// otherwise shift the full-page content down.
fun FlutterEpubPreferences.effectiveForLayout(layout: Layout?): FlutterEpubPreferences =
    if (layout?.isReflowable == true) this else copy(firstElementTopMargin = null)

val Layout.isFixed: Boolean
    get() = this == Layout.FIXED

val Layout.isReflowable: Boolean
    get() = this == Layout.REFLOWABLE

val Layout.isScrolled: Boolean
    get() = this == Layout.SCROLLED

/**
 * Get the duration in seconds, that includes decimals. Unlike [Duration.inWholeSeconds]
 */
val Duration.toSeconds: Double
    get() = toDouble(DurationUnit.SECONDS)

/**
 * Metadata read from a CBZ/DiViNa `ComicInfo.xml`. Only the fields this plugin surfaces.
 */
data class ComicInfoMetadata(
    val title: String?,
    val authors: List<String>,
)

/**
 * Reads `ComicInfo.xml` (the ComicRack metadata standard) from an image-based publication.
 *
 * WORKAROUND for a kotlin-toolkit gap: swift-toolkit's `ImageParser` parses `ComicInfo.xml`
 * into the publication [org.readium.r2.shared.publication.Metadata] (title, authors, …), but
 * kotlin-toolkit (≤ 3.3.0 / main) does not — its `ImageParser` emits only
 * `Metadata(conformsTo = [DIVINA])`, so CBZ titles come back blank on Android. This reads the
 * standard fields we display so Android matches iOS.
 *
 * TODO(upstream): remove once kotlin-toolkit's ImageParser parses ComicInfo.xml.
 *   Tracking issue: https://github.com/readium/kotlin-toolkit/issues/<TBD>
 */
suspend fun Publication.readComicInfoMetadata(): ComicInfoMetadata? {
    val link = Link(href = Url("ComicInfo.xml") ?: return null)
    val xml =
        get(link)?.read()?.getOrNull()?.let { String(it) } ?: return null
    return parseComicInfo(xml)
}

private fun parseComicInfo(xml: String): ComicInfoMetadata? =
    try {
        val parser = Xml.newPullParser()
        parser.setInput(StringReader(xml))
        var title: String? = null
        val authors = mutableListOf<String>()
        var currentTag: String? = null
        var event = parser.eventType
        while (event != XmlPullParser.END_DOCUMENT) {
            when (event) {
                XmlPullParser.START_TAG -> {
                    currentTag = parser.name
                }

                XmlPullParser.END_TAG -> {
                    currentTag = null
                }

                XmlPullParser.TEXT -> {
                    val text = parser.text?.trim().orEmpty()
                    if (text.isNotEmpty()) {
                        when (currentTag) {
                            // ComicInfo <Writer> is a comma-separated author list, matching
                            // swift-toolkit's `writers.map { Contributor(name: $0) }`.
                            "Title" -> {
                                title = text
                            }

                            "Writer" -> {
                                authors +=
                                    text.split(",").map { it.trim() }.filter { it.isNotEmpty() }
                            }
                        }
                    }
                }
            }
            event = parser.next()
        }
        ComicInfoMetadata(title, authors)
    } catch (e: Exception) {
        PluginLog.w(TAG, "::parseComicInfo - failed to parse ComicInfo.xml: ${e.message}")
        null
    }
