package dk.nota.flutterreadium.models

import dk.nota.flutterreadium.FlutterEpubPreferences
import dk.nota.flutterreadium.ReaderFontFamily
import org.readium.r2.navigator.epub.EpubNavigatorFactory

open class EpubReaderViewModel : ReaderViewModel() {
    var preferences: FlutterEpubPreferences? = null

    var navigatorFactory: EpubNavigatorFactory? = null

    var fontFamilyDeclarations: List<ReaderFontFamily> = emptyList()
}
