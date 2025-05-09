package dk.nota.flutter_readium

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Publication
import org.readium.r2.streamer.PublicationOpener.OpenError
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.asset.Asset
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.fromEpubHref
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.shared.util.resource.Resource
import org.readium.r2.shared.util.resource.TransformingContainer
import org.readium.r2.shared.util.resource.TransformingResource
import org.readium.r2.shared.util.resource.filename
import org.readium.r2.shared.util.resource.mediaType

private const val TAG = "PublicationChannel"

internal const val publicationChannelName = "dk.nota.flutter_readium/main"

private var readium: Readium? = null

// TODO: Do we still want to use this?
private var publication: Publication? = null
internal fun publicationFromHandle(): Publication? {
  return publication
}

// Collection of publications init to empty
private var publications = emptyMap<String, Publication>().toMutableMap()

internal fun publicationFromIdentifier(identifier: String): Publication? {
  return publications[identifier];
}


/// Values must match order of OpeningReadiumExceptionType in readium_exceptions.dart.
private fun openingExceptionIndex(exception: OpenError): Int =
  when (exception) {
    is OpenError.Reading -> 0
    is OpenError.FormatNotSupported -> 1
  }

private suspend fun assetToPublication(
  asset: Asset
): Try<Publication, OpenError> {
  return withContext(Dispatchers.IO) {
    val publication: Publication =
      readium!!.publicationOpener.open(asset, allowUserInteraction = true, onCreatePublication = {
        container = TransformingContainer(container) { _: Url, resource: Resource ->
          resource.injectScriptsAndStyles()
        }
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

private suspend fun openPublication(
  pubUrl: AbsoluteUrl,
  result: MethodChannel.Result
) {
  try {
    // TODO: should client provide mediaType to assetRetriever?
    val asset: Asset = readium!!.assetRetriever.retrieve(pubUrl)
      .getOrElse { error: AssetRetriever.RetrieveUrlError ->
        Log.e(TAG, "Error retrieving asset: $error")
        throw Exception()
      }
    val pub = assetToPublication(asset).getOrElse { e ->
      CoroutineScope(Dispatchers.Main).launch {
        result.error(openingExceptionIndex(e).toString(), e.toString(), null)
      }
      return
    }
    Log.d(TAG, "Opened publication = ${pub.metadata.identifier}")
    publications[pub.metadata.identifier ?: pubUrl.toString()] = pub
    // Manifest must now be manually turned into JSON
    val pubJsonManifest = pub.manifest.toJSON().toString().replace("\\/", "/")
    CoroutineScope(Dispatchers.Main).launch {
      result.success(pubJsonManifest)
    }
  } catch (e: Throwable) {
    result.error("OpenPublicationError", e.toString(), e.stackTraceToString())
  }
}

private fun parseMediaType(mediaType: Any?): MediaType? {
  @Suppress("UNCHECKED_CAST")
  val list = mediaType as List<String?>? ?: return null
  return MediaType(list[0]!!)
}

internal class PublicationMethodCallHandler(private val context: Context) :
  MethodChannel.MethodCallHandler {
  @OptIn(InternalReadiumApi::class)
  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    CoroutineScope(Dispatchers.IO).launch {
      if (readium == null) {
        readium = Readium(context)
      }
      when (call.method) {
        "openPublication" -> {
          val args = call.arguments as List<Any?>
          var pubUrlStr = args[0] as String
          if (!pubUrlStr.startsWith("http") && !pubUrlStr.startsWith("file")) {
            pubUrlStr = "file://$pubUrlStr"
          }
          val pubUrl = AbsoluteUrl(pubUrlStr) ?: run {
            Log.e(TAG, "openPublication: Invalid URL")
            result.error("InvalidURLError", "Invalid publication URL", null)
            return@launch
          }
          Log.d(TAG, "openPublication for URL: $pubUrl")

          openPublication(pubUrl, result)
        }

        "closePublication" -> {
          val pubIdentifier = call.arguments as String
          Log.d(TAG, "Close publication with identifier = $pubIdentifier")
          publications[pubIdentifier]?.close()
          publications.remove(pubIdentifier)
          CoroutineScope(Dispatchers.Main).launch {
            result.success(null)
          }
        }

        "get" -> {
          try {
            val args = call.arguments as List<Any?>
            val isLink = args[0] as Boolean
            val linkData = args[1] as String
            val asString = args[2] as Boolean
            val link: Link
            if (isLink) {
              link = Link.fromJSON(JSONObject(linkData))!!
            } else {
              val url = Url.fromEpubHref(linkData) ?: run {
                Log.e(TAG, "get: invalid EPUB href $linkData")
                throw Exception("get: invalid EPUB href $linkData")
              }
              link = Link(url)
            }
            Log.d(TAG, "Use publication = $publication")
            // TODO Debug why the next line crashed with a NullPointerException one time. Probably
            // somehow related to the server being re-indexed. Was an invalid publication somehow
            // created, or was a valid publication disposed and then used?

            val resource = publication!!.get(link) ?: run {
              Log.e(TAG, "get: failed to get resource via link $link")
              throw Exception("failed to get resource via link $link")
            }
            val resourceBytes = resource.read().getOrElse {
              Log.e(TAG, "get: invalid EPUB href $linkData")
              throw Exception("get: invalid EPUB href $linkData")
            }

            CoroutineScope(Dispatchers.Main).launch {
              if (asString) {
                result.success(String(resourceBytes))
              } else {
                result.success(resourceBytes)
              }
            }
          } catch (e: Exception) {
            Log.e(TAG, "Exception: $e")
            Log.e(TAG, "${e.stackTrace}")
            CoroutineScope(Dispatchers.Main).launch {
              result.error(e.javaClass.toString(), e.toString(), e.stackTraceToString())
            }
          }
        }

        else -> result.notImplemented()
      }
    }
  }
}

private fun Resource.injectScriptsAndStyles(): Resource =
  TransformingResource(this) { bytes ->
    val props = this.properties().getOrNull()
    val filename = props?.filename

    if (filename?.endsWith("html", ignoreCase = true) != true) {
      return@TransformingResource Try.success(bytes)
    }

    var content = bytes.toString(Charsets.UTF_8).trim()

    if (content.contains("https://readium/assets/")) {
      Log.d(TAG, "Injecting skipped - already done for: $filename")
      return@TransformingResource Try.success(bytes)
    }

    Log.d(TAG, "Injecting files into: $filename")

    val injectables = listOf(
      // this is injecting and stylesheets seems to be working, but the css variables does not exists,
      // and there are other issues with the looks as well, but I don't know if this is the cause, or I am missing something else.
      """<script type="text/javascript" src="https://readium/assets/comics.js"></script>""",
      """<script type="text/javascript" src="https://readium/assets/epub.js"></script>""",
      """<link rel="stylesheet" type="text/css" href="https://readium/assets/comics.css"></link>""",
      """<link rel="stylesheet" type="text/css" href="https://readium/assets/epub.css"></link>""",
      //"""<style>p { color: navy }</style>"""
    )

    val headEndIndex = content.indexOf("</head>", 0, true)
    if (headEndIndex != -1) {
      val newContent = StringBuilder(content)
        .insert(headEndIndex, "\n" + injectables.joinToString("\n") + "\n")
        .toString()
      content = newContent
    }

    Try.success(content.toByteArray())
  }
