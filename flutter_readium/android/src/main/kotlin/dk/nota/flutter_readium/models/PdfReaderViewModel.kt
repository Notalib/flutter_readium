package dk.nota.flutter_readium.models

import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.adapter.pdfium.navigator.PdfiumSettings
import org.readium.r2.navigator.pdf.PdfNavigatorFactory
import org.readium.r2.shared.ExperimentalReadiumApi

@OptIn(ExperimentalReadiumApi::class)
open class PdfReaderViewModel : ReaderViewModel() {
    var preferences: PdfiumPreferences? = null

    var navigatorFactory: PdfNavigatorFactory<PdfiumSettings, PdfiumPreferences, *>? = null
}
