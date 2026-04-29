package dk.nota.flutter_readium.models

import dk.nota.flutter_readium.FlutterEpubPreferences
import org.readium.r2.navigator.epub.EpubNavigatorFactory

open class EpubReaderViewModel : ReaderViewModel() {
    var preferences: FlutterEpubPreferences? = null

    var navigatorFactory: EpubNavigatorFactory? = null
}
