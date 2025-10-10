package dk.nota.flutter_readium.navigators

import android.content.Context
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MediaMetadata.PICTURE_TYPE_FRONT_COVER
import dk.nota.flutter_readium.ControlPanelInfoType
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import org.readium.navigator.media.common.MediaMetadataFactory
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Publication


class DatabaseMediaMetadataFactory(
    private val context: Context,
    private val publication: Publication,
    private val trackCount: Int,
    private val controlPanelInfoType: ControlPanelInfoType
) : MediaMetadataFactory {
    private class Metadata(
        val title: String,
        val authors: String,
        val cover: Link?
    )


    private val metadata: Metadata = Metadata(
        title = publication.metadata.title ?: "",
        authors = publication.metadata.authors.joinToString(", ") { it.name }.ifEmpty { "" },
        cover = publication.links.firstOrNull() { l -> l.rels.contains("cover") }
    )

    // Remember byte arrays will go cross processes and should be kept small so use .scaleToFit(400, 400).toPng()
    // TODO: Load cover image asynchronously and cache it
    private var coverImage: ByteArray? = null

    override suspend fun publicationMetadata(): MediaMetadata =
        builder()?.build() ?: MediaMetadata.EMPTY

    override suspend fun resourceMetadata(index: Int): MediaMetadata =
        builder(index)?.build() ?: MediaMetadata.EMPTY

    private suspend fun builder(index: Int? = null): MediaMetadata.Builder? {
        val publicationTitle = metadata.title
        val authors = metadata.authors
        val currentChapterTitle = index?.let {
            publication.readingOrder.getOrNull(it)?.title ?: ""
        } ?: ""

        val builder = MediaMetadata.Builder()
            .setTotalTrackCount(trackCount)

        when (controlPanelInfoType) {
            ControlPanelInfoType.STANDARD, ControlPanelInfoType.STANDARD_WCH -> {
                builder.setArtist(authors)
                if (controlPanelInfoType == ControlPanelInfoType.STANDARD_WCH && currentChapterTitle.isNotEmpty()) {
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
                builder.setArtist(currentChapterTitle)
                builder.setTitle(publicationTitle)
            }
        }

        index?.let { builder.setTrackNumber(it) }
        coverImage?.let {
            // We can't yet directly use a `content://` or `file://` URI with `setArtworkUri`.
            // See https://github.com/androidx/media/issues/271
            builder.setArtworkData(it, PICTURE_TYPE_FRONT_COVER)
        }
        return builder
    }
}

