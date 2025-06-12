package dk.nota.flutter_readium

import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

sealed class ReaderInitData {
    abstract val publication: Publication
}

sealed class VisualReaderInitData(
    override val publication: Publication,
    val initialLocation: Locator?,
) : ReaderInitData()

class EpubReaderInitData(
    publication: Publication,
    initialLocation: Locator?,
    val initialPreferences: EpubPreferences?,
) : VisualReaderInitData(publication, initialLocation)
{
    val navigatorFactory = EpubNavigatorFactory(publication)
}
