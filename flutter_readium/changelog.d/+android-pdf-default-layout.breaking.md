**Android PDFs now open in paginated mode by default.**

Previously, they opened in vertical scroll mode. To preserve that behavior, call `setDefaultPDFPreferences(PDFPreferences(layout: PDFLayout.scrollVertical))` before opening the reader.
