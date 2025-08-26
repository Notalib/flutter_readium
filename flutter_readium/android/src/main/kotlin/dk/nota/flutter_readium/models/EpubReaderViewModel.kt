package dk.nota.flutter_readium.models

import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubPreferences

open class EpubReaderViewModel : ReaderViewModel() {
    var preferences: EpubPreferences? = null

    val navigatorFactory: EpubNavigatorFactory?
        get() {
            val p = publication ?: return null
            return EpubNavigatorFactory(p)
        }
}
