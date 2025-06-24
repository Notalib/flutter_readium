/*
 * Copyright 2022 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of the project.
 */

package dk.nota.flutter_readium

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.content.DefaultContentService
import org.readium.r2.shared.publication.services.content.contentServiceFactory
import org.readium.r2.shared.publication.services.content.iterators.HtmlResourceContentIterator
import org.readium.r2.shared.publication.services.search.StringSearchService
import org.readium.r2.shared.publication.services.search.searchServiceFactory
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.ThrowableError
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.asset.Asset
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.resource.Resource
import org.readium.r2.shared.util.resource.TransformingContainer
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.PublicationOpener.OpenError
import org.readium.r2.streamer.parser.DefaultPublicationParser

private const val TAG = "ReadiumHelper"

// Collection of publications init to empty
private var publications = mutableMapOf<String, Publication>()
private var publicationUrls = mutableMapOf<String, String>()

/**
 * Holds the shared Readium objects and services used by the app.
 */
@OptIn(ExperimentalReadiumApi::class)
class Readium(private val context: Context) {
  private val httpClient =
    DefaultHttpClient()

  private val assetRetriever by lazy {
    AssetRetriever(context.contentResolver, httpClient)
  }

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

  private val contentProtections by lazy {
    listOfNotNull(
      null,
      //lcpService.getOrNull()?.contentProtection(lcpDialogAuthentication)
    )
  }

  /**
   * The PublicationFactory is used to open publications.
   */
  private val publicationOpener by lazy {
    PublicationOpener(
      publicationParser = DefaultPublicationParser(
        context,
        assetRetriever = assetRetriever,
        httpClient = httpClient,
        // Only required if you want to support PDF files using the PDFium adapter.
        pdfFactory = null, //PdfiumDocumentFactory(context)
      ),
      contentProtections = contentProtections,
    )
  }

  /*
  fun onLcpDialogAuthenticationParentAttached(view: View) {
      lcpDialogAuthentication.onParentViewAttachedToWindow(view)
  }

  fun onLcpDialogAuthenticationParentDetached() {
      //lcpDialogAuthentication.onParentViewDetachedFromWindow()
  }
  */

  fun publicationFromIdentifier(identifier: String): Publication? {
    return publications[identifier]
  }

  fun publicationUrlFromIdentifier(identifier: String): String?{
    return publicationUrls[identifier]
  }

  private suspend fun assetToPublication(
    asset: Asset
  ): Try<Publication, OpenError> {
    return withContext(Dispatchers.IO) {
      val publication: Publication =
        publicationOpener.open(asset, allowUserInteraction = true, onCreatePublication = {
          container = TransformingContainer(container) { _: Url, resource: Resource ->
            resource.injectScriptsAndStyles()
          }
          // TODO: Temporary fix for missing service factories for WebPubs with HTML content.
          servicesBuilder.contentServiceFactory = DefaultContentService.createFactory(
            resourceContentIteratorFactories = listOf(
              HtmlResourceContentIterator.Factory()
            )
          )
          servicesBuilder.searchServiceFactory = StringSearchService.createDefaultFactory()
        })
          .getOrElse { err: OpenError ->
            Log.e(TAG, "Error opening publication: $err")
            asset.close()
            return@withContext Try.failure(err)
          }
      Log.d(TAG, "Open publication success: $publication")
      return@withContext Try.success(publication)
    }
  }

  suspend fun openPublication(
    pubUrl: AbsoluteUrl
  ): Try<Publication, PublicationError> {
    try {
      // TODO: should client provide mediaType to assetRetriever?
      val asset: Asset = assetRetriever.retrieve(pubUrl)
        .getOrElse { error: AssetRetriever.RetrieveUrlError ->
          Log.e(TAG, "Error retrieving asset: $error from url:$pubUrl")
          return Try.failure(PublicationError.invoke(error))
        }
      val pub = assetToPublication(asset).getOrElse { error: OpenError ->
        Log.e(TAG, "Error loading asset to Publication object: $error from url:$pubUrl")
        return Try.failure(PublicationError.invoke(error))
      }
      Log.d(TAG, "Opened publication = ${pub.metadata.identifier} from url:$pubUrl")
      publications[pub.metadata.identifier ?: pubUrl.toString()] = pub
      publicationUrls[pub.metadata.identifier ?: pubUrl.toString()] = pubUrl.toString()
      return Try.success(pub)
    } catch (e: Throwable) {
      return Try.failure(PublicationError.Unexpected(ThrowableError(e)))
    }
  }

  fun closePublication(pubIdentifier: String)
  {
    publications[pubIdentifier]?.close()
    publications.remove(pubIdentifier)
  }
}
