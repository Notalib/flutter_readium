package dk.nota.flutter_readium.models

import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

open class ReaderViewModel {
    var identifier: String? = null

    var pubUrl: String? = null

    var publication: Publication? = null

    var locator: Locator? = null
}

open class EpubReaderViewModel : ReaderViewModel()
{
    var preferences: EpubPreferences? = null

    val navigatorFactory: EpubNavigatorFactory?
        get() {
            val p = publication ?: return null
            return EpubNavigatorFactory(p)
        }
}
