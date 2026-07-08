package dk.nota.flutterreadium.navigators

import android.util.Size
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MediaMetadata.PICTURE_TYPE_FRONT_COVER
import dk.nota.flutterreadium.ControlPanelInfoType
import org.readium.navigator.media.common.MediaMetadataFactory
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.extensions.toPng
import org.readium.r2.shared.publication.LocalizedString
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.coverFitting
import java.util.concurrent.atomic.AtomicReference

@OptIn(InternalReadiumApi::class)
class DatabaseMediaMetadataFactory(
    private val publication: Publication,
    private val trackCount: Int,
    private val controlPanelInfoType: ControlPanelInfoType,
    /**
     * Optional cache shared across every factory instance a caller creates for the same
     * publication (e.g. one per navigator rebuild), so a rebuild after a network failure
     * doesn't re-fetch the cover over the same broken network. Left null for call sites that
     * don't rebuild (e.g. [dk.nota.flutterreadium.navigators.TTSNavigator]), which then only
     * cache within this instance's own lifetime.
     */
    private val coverCache: AtomicReference<ByteArray?>? = null,
) : MediaMetadataFactory {
    /**
     * The title of the publication.
     */
    private val publicationTitle: String by lazy {
        publication.metadata.title ?: ""
    }

    /**
     * The authors of the publication, joined as a single string.
     */
    private val authors: String by lazy {
        publication.metadata.authors
            .map { it.name }
            .filter { !it.isEmpty() }
            .joinToString(", ")
    }

    private val chapterTitleFallback by lazy {
        LocalizedString
            .fromStrings(
                mapOf(
                    "en" to "Chapter",
                    "da" to "Kapitel",
                    "sv" to "Kapitel",
                    "no" to "Kapittel",
                    "is" to "Kafli",
                ),
            ).getOrFallback(publication.metadata.language?.code)
    }

    /**
     * The cover image as a byte array, cached after first load. Use [loadCoverImage] to load it.
     */
    private var coverImage: ByteArray? = null

    override suspend fun publicationMetadata(): MediaMetadata = builder()?.build() ?: MediaMetadata.EMPTY

    override suspend fun resourceMetadata(index: Int): MediaMetadata = builder(index)?.build() ?: MediaMetadata.EMPTY

    /**
     * Load the cover image as a byte array. Handles resizing.
     */
    private suspend fun loadCoverImage(): ByteArray? {
        if (coverImage != null) return coverImage

        coverCache?.get()?.let {
            coverImage = it
            return it
        }

        coverImage = publication.coverFitting(Size(400, 400))?.toPng()
        coverCache?.set(coverImage)

        return coverImage
    }

    private suspend fun builder(index: Int? = null): MediaMetadata.Builder? {
        var currentChapterTitle =
            index?.let {
                publication.readingOrder.getOrNull(it)?.title
            }

        if (currentChapterTitle == null && index != null) {
            currentChapterTitle = "$chapterTitleFallback ${index + 1}"
        }

        val builder =
            MediaMetadata
                .Builder()
                .setTotalTrackCount(trackCount)

        when (controlPanelInfoType) {
            ControlPanelInfoType.STANDARD, ControlPanelInfoType.STANDARD_WCH -> {
                builder.setArtist(authors)
                if (controlPanelInfoType == ControlPanelInfoType.STANDARD_WCH && !currentChapterTitle.isNullOrEmpty()) {
                    builder.setTitle("$publicationTitle - $currentChapterTitle")
                } else {
                    builder.setTitle(publicationTitle)
                }
            }

            ControlPanelInfoType.CHAPTER_TITLE_AUTHOR, ControlPanelInfoType.CHAPTER_TITLE -> {
                builder.setTitle(currentChapterTitle)
                if (controlPanelInfoType == ControlPanelInfoType.CHAPTER_TITLE) {
                    builder.setArtist(publicationTitle)
                } else {
                    builder.setArtist("$publicationTitle - $authors")
                }
            }

            else -> {
                builder.setArtist(publicationTitle)
                builder.setTitle(authors)
            }
        }

        index?.let { builder.setTrackNumber(it) }
        loadCoverImage()?.let {
            // We can't yet directly use a `content://` or `file://` URI with `setArtworkUri`.
            // See https://github.com/androidx/media/issues/271
            builder.setArtworkData(it, PICTURE_TYPE_FRONT_COVER)
        }
        return builder
    }
}
