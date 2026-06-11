package dk.nota.flutterreadium.models

import dk.nota.flutterreadium.FlutterEpubPreferences
import org.readium.r2.navigator.epub.EpubNavigatorFactory

open class EpubReaderViewModel : ReaderViewModel() {
    var preferences: FlutterEpubPreferences? = null

    var navigatorFactory: EpubNavigatorFactory? = null
}
