/*
 * Copyright 2022 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of the project.
 */

package dk.nota.flutter_readium

import android.content.Context
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser

private const val TAG = "ReadiumHelper"

/**
 * Holds the shared Readium objects and services used by the app.
 */
class Readium(context: Context) {

  private val httpClient =
    DefaultHttpClient()

  val assetRetriever =
    AssetRetriever(context.contentResolver, httpClient)

  /**
   * The LCP service decrypts LCP-protected publication and acquire publications from a
   * license file.
   */
//     val lcpService = LcpService(
//         context,
//         assetRetriever
//     )?.let { Try.success(it) }
//         ?: Try.failure(LcpError.Unknown(DebugError("liblcp is missing on the classpath")))

//     private val lcpDialogAuthentication = LcpDialogAuthentication()

  private val contentProtections = listOfNotNull(
    null,
    //lcpService.getOrNull()?.contentProtection(lcpDialogAuthentication)
  )

  /**
   * The PublicationFactory is used to open publications.
   */
  val publicationOpener = PublicationOpener(
    publicationParser = DefaultPublicationParser(
      context,
      assetRetriever = assetRetriever,
      httpClient = httpClient,
      // Only required if you want to support PDF files using the PDFium adapter.
      pdfFactory = null, //PdfiumDocumentFactory(context)
    ),
    contentProtections = contentProtections,
  )

  /*
  fun onLcpDialogAuthenticationParentAttached(view: View) {
      lcpDialogAuthentication.onParentViewAttachedToWindow(view)
  }

  fun onLcpDialogAuthenticationParentDetached() {
      //lcpDialogAuthentication.onParentViewDetachedFromWindow()
  }
  */
}
