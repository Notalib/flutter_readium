package dk.nota.flutter_readium.models

import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

open class ReaderViewModel {
    var identifier: String? = null

    var pubUrl: String? = null

    var publication: Publication? = null

    var locator: Locator? = null
}

