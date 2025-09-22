package dk.nota.flutter_readium

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.util.Log
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryOwner
import dk.nota.flutter_readium.navigators.AudiobookNavigator
import dk.nota.flutter_readium.navigators.EpubNavigator
import dk.nota.flutter_readium.navigators.TTSNavigator
import dk.nota.flutter_readium.navigators.TimebasedNavigator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.navigator.media.tts.android.AndroidTtsEngine
import org.readium.navigator.media.tts.android.AndroidTtsPreferences
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.content.DefaultContentService
import org.readium.r2.shared.publication.services.content.contentServiceFactory
import org.readium.r2.shared.publication.services.content.iterators.HtmlResourceContentIterator
import org.readium.r2.shared.publication.services.search.StringSearchService
import org.readium.r2.shared.publication.services.search.searchServiceFactory
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.DebugError
import org.readium.r2.shared.util.ThrowableError
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Try.Companion.failure
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.asset.Asset
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.shared.util.resource.Resource
import org.readium.r2.shared.util.resource.TransformingContainer
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.PublicationOpener.OpenError
import org.readium.r2.streamer.parser.DefaultPublicationParser
import java.lang.ref.WeakReference

private const val TAG = "ReadiumReader"

private const val stateKey = "dk.nota.flutter_readium.ReadiumReaderState"

private const val currentPublicationUrlKey = "currentPublicationUrl"
private const val ttsEnabledKey = "ttsEnabled"
private const val audioEnabledKey = "audioEnabled"

private const val epubEnabledKey = "epubEnabled"
private const val ttsNavigatorStateKey = "ttsState"
private const val audioNavigatorStateKey = "audioState"
private const val epubNavigatorStateKey = "epubState"

// TODO: Support custom headers and authentication header.

@OptIn(ExperimentalReadiumApi::class)
object ReadiumReader : TimebasedNavigator.TimebasedListener, EpubNavigator.VisualListener {
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var appRef: WeakReference<Application>? = null

    private var readerViewRef: WeakReference<ReadiumReaderWidget>? = null

    private var savedStateRef: WeakReference<SavedStateRegistry>? = null

    // in-memory cached state
    private val state = mutableMapOf<String, Any?>()

    private val httpClient by lazy {
        DefaultHttpClient()
    }

    private var _assetRetriever: AssetRetriever? = null

    private val assetRetriever: AssetRetriever
        get() {
            if (_assetRetriever == null) {
                _assetRetriever = AssetRetriever(context.contentResolver, httpClient)
            }

            return _assetRetriever!!
        }

    private var _publicationOpener: PublicationOpener? = null

    private var ttsNavigator: TTSNavigator? = null

    private var audiobookNavigator: AudiobookNavigator? = null

    private var epubNavigator: EpubNavigator? = null

    /**
     * The PublicationFactory is used to open publications.
     */
    private val publicationOpener: PublicationOpener
        get() {
            if (_publicationOpener == null) {
                _publicationOpener = PublicationOpener(
                    publicationParser = DefaultPublicationParser(
                        context,
                        assetRetriever = assetRetriever,
                        httpClient = httpClient,
                        // Only required if you want to support PDF files using the PDFium adapter.
                        pdfFactory = null, //PdfiumDocumentFactory(context)
                    ),
                )
            }

            return _publicationOpener!!
        }

    // Initialize from plugin or anywhere you have an Application or Context.
    fun attach(activity: Activity) {
        unwrapToApplication(activity)
            ?.let { appRef = WeakReference(it) }

        // store weak ref only
        (activity as? SavedStateRegistryOwner)?.savedStateRegistry?.let {
            savedStateRef = WeakReference(it)
            it.registerSavedStateProvider(stateKey) {
                storeState()
            }

            restoreState(it.consumeRestoredStateForKey(stateKey))
        }
    }

    private fun storeState(): Bundle {
        if (currentPublicationUrl == null) {
            // No current publication, no state.
            return Bundle()
        }

        return Bundle().apply {
            putString(currentPublicationUrlKey, currentPublicationUrl)
            putBoolean(epubEnabledKey, epubNavigator != null)
            putBundle(epubNavigatorStateKey, epubNavigator?.storeState())
            putBoolean(ttsEnabledKey, ttsNavigator != null)
            putBundle(ttsNavigatorStateKey, ttsNavigator?.storeState())
            putBoolean(audioEnabledKey, audiobookNavigator != null)
            putBundle(audioNavigatorStateKey, audiobookNavigator?.storeState())
        }
    }

    private fun restoreState(bundle: Bundle?) {
        if (bundle == null) {
            Log.d(TAG, ":restoreState nothing to restore")
            return
        }

        Log.d(TAG, ":restoreState $bundle")
        val pubUrl = bundle.getString(currentPublicationUrlKey)
        if (pubUrl == null) {
            Log.d(TAG, ":storeState - currentPublicationUrl - not restored")
            return
        }

        Log.d(TAG, ":restoreState - currentPublicationUrl - $pubUrl")
        mainScope.launch {
            val pub = openPublication(pubUrl).getOrElse {
                Log.d(TAG, ":restoreState - failed to restore publication")
                // TODO: Handle this somehow
                return@launch
            }

            if (bundle.getBoolean(epubEnabledKey)) {
                Log.d(TAG, ":storeState - restore epub navigator")
                bundle.getBundle(epubNavigatorStateKey)?.let {
                    epubNavigator = EpubNavigator.restoreState(pub, this@ReadiumReader, it)
                        .apply {
                            initNavigator()
                            Log.d(TAG, ":storeState - epubNavigator restored")
                        }
                }
            }

            if (bundle.getBoolean(ttsEnabledKey)) {
                // Restore TTS navigator
                Log.d(TAG, ":storeState - restore tts navigator")
                bundle.getBundle(ttsNavigatorStateKey)?.let {
                    ttsNavigator = TTSNavigator.restoreState(pub, this@ReadiumReader, it)
                        .apply {
                            initNavigator()
                            Log.d(TAG, ":storeState - ttsNavigator restored")
                        }
                }
            }

            if (bundle.getBoolean(audioEnabledKey)) {
                // Restore Audio navigator
                Log.d(TAG, ":storeState - restore audio navigator")
                bundle.getBundle(audioNavigatorStateKey)?.let {
                    audiobookNavigator =
                        AudiobookNavigator.restoreState(pub, this@ReadiumReader, it)
                            .apply {
                                initNavigator()
                                Log.d(TAG, ":storeState - audioNavigator restored")
                            }
                }
            }

            Log.d(TAG, "consumeRestoredStateForKey - 2 - $currentPublication")
        }
    }

    fun detach() {
        closePublication()

        appRef?.clear()
        appRef = null

        savedStateRef?.clear()
        savedStateRef = null

        _assetRetriever = null
        _publicationOpener = null

        readerViewRef?.clear()
        readerViewRef = null

        mainScope.coroutineContext.cancelChildren()
    }

    // Safe getter — returns applicationContext or throws if not available.
    val application: Application
        get() = appRef?.get()
            ?: throw IllegalStateException("Application not initialized. Call ReadiumReader.attach(...) first.")

    var currentReaderWidget: ReadiumReaderWidget?
        get() = readerViewRef?.get()
        set(value) {
            readerViewRef = value?.let { WeakReference(it) }
        }

    private val context: Context
        get() = application.applicationContext

    private var _currentPublication: Publication? = null
    val currentPublication: Publication?
        get() = _currentPublication
    var currentPublicationUrl
        get() = state[currentPublicationUrlKey] as String?
        set(value) {
            state[currentPublicationUrlKey] = value
        }

    private suspend fun assetToPublication(
        asset: Asset
    ): Try<Publication, OpenError> {
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
                    return failure(err)
                }
        Log.d(TAG, "Open publication success: $publication")
        return Try.success(publication)
    }

    /**
     * Load a publication from a String url.
     * Note: Remember to close the publication to avoid leaks.
     */
    suspend fun loadPublication(
        pubUrl: String?
    ): Try<Publication, PublicationError> {
        if (pubUrl == null) {
            return failure(
                PublicationError.Unexpected(
                    DebugError("missing argument")
                )
            )
        }

        return AbsoluteUrl.invoke(pubUrl)?.let { loadPublication(it) } ?: failure(
            PublicationError.Unexpected(
                DebugError("Invalid Url")
            )
        )
    }

    /**
     * Load a publication from an AbsoluteUrl
     *
     * Note: Remember to close the publication to avoid leaks.
     */
    suspend fun loadPublication(
        pubUrl: AbsoluteUrl
    ): Try<Publication, PublicationError> {
        return withContext(Dispatchers.IO) {
            try {
                // TODO: should client provide mediaType to assetRetriever?
                val asset: Asset = assetRetriever.retrieve(pubUrl)
                    .getOrElse { error: AssetRetriever.RetrieveUrlError ->
                        Log.e(TAG, "Error retrieving asset: $error from url:$pubUrl")
                        return@withContext failure(PublicationError.invoke(error))
                    }
                val pub = assetToPublication(asset).getOrElse { error: OpenError ->
                    Log.e(TAG, "Error loading asset to Publication object: $error from url:$pubUrl")
                    return@withContext failure(PublicationError.invoke(error))
                }
                Log.d(TAG, "Opened publication = ${pub.metadata.identifier} from url:$pubUrl")
                return@withContext Try.success(pub)
            } catch (e: Throwable) {
                return@withContext failure(PublicationError.Unexpected(ThrowableError(e)))
            }
        }
    }

    /**
     * Open a publication and set it as the current publication.
     */
    suspend fun openPublication(
        pubUrl: String?
    ): Try<Publication, PublicationError> {
        if (pubUrl == null) {
            return failure(
                PublicationError.Unexpected(
                    DebugError("missing argument")
                )
            )
        }

        return AbsoluteUrl.invoke(pubUrl)?.let { openPublication(it) } ?: failure(
            PublicationError.Unexpected(
                DebugError("Invalid Url")
            )
        )
    }

    /**
     * Open a publication and set it as the current publication.
     */
    suspend fun openPublication(
        pubUrl: AbsoluteUrl
    ): Try<Publication, PublicationError> {
        val pub = loadPublication(pubUrl).getOrElse { e -> return failure(e) }

        // Close previously opened publication to avoid links.
        _currentPublication?.close()
        _currentPublication = pub
        currentPublicationUrl = pubUrl.toString()

        return Try.success(pub)
    }

    /**
     * Load a publication from a URL
     * Note: Remember to close the publication to avoid leaks.
     */
    suspend fun loadPublicationFromUrl(urlStr: String): Try<Publication, PublicationError> {
        val pubUrl = resolvePubUrl(urlStr).getOrElse {
            return failure(PublicationError.InvalidPublicationUrl(urlStr))
        }

        Log.d(TAG, "loadPublicationFromUrl: $pubUrl")

        return loadPublication(pubUrl)
    }

    /**
     * Open a publication from a URL.
     *
     * Note: This sets the publication as the current publication.
     */
    suspend fun openPublicationFromUrl(urlStr: String): Try<Publication, PublicationError> {
        val pubUrl = resolvePubUrl(urlStr).getOrElse {
            return failure(PublicationError.InvalidPublicationUrl(urlStr))
        }

        Log.d(TAG, "openPublicationFromUrl: $pubUrl")

        return openPublication(pubUrl)
    }

    /**
     * Helper function for resolving a URL and make sure a file path is turned into a URL.
     */
    private fun resolvePubUrl(urlStr: String): Try<AbsoluteUrl, PublicationError> {
        var pubUrlStr = urlStr
        // If URL is neither http nor file, assume it is a local file reference.
        if (!pubUrlStr.startsWith("http") && !pubUrlStr.startsWith("file")) {
            pubUrlStr = "file://$pubUrlStr"
        }
        // Create AbsoluteUrl, return PublicationError.InvalidPublicationUrl if null
        val pubUrl = AbsoluteUrl(pubUrlStr)
        if (pubUrl == null) {
            return failure(PublicationError.InvalidPublicationUrl(pubUrlStr))
        }

        return Try.success(pubUrl)
    }

    fun closePublication() {
        _currentPublication?.close()
        _currentPublication = null

        ttsNavigator?.dispose()
        ttsNavigator = null
        audiobookNavigator?.dispose()
        audiobookNavigator = null

        state.clear()
    }

    override fun onTimebasedPlaybackStateChanged(playbackState: TimebasedNavigator.PlaybackState) {
        Log.d(TAG, ":onTimebasedPlaybackStateChanged $playbackState")
    }

    override fun onTimebasedCurrentLocatorChanges(locator: Locator) {
        Log.d(TAG, ":onTimebasedCurrentLocatorChanges $locator")
    }

    suspend fun epubEnable(initialLocator: Locator?, epubPrefs: EpubPreferences): EpubNavigator {
        val pub = currentPublication
            ?: throw Exception("Publication not opened cannot enable epub")

        // TODO: Check if pub is an epub. -- pub.conformsTo(Publication.Profile.EPUB)
        epubNavigator?.let { return it } // Already enabled - assume from restored state.

        EpubNavigator(pub, initialLocator, this, epubPrefs).apply {
            initNavigator()
            epubNavigator = this
            return this
        }
    }

    fun epubClose() {
        epubNavigator?.dispose()
        epubNavigator = null
    }

    suspend fun ttsEnable(ttsPrefs: AndroidTtsPreferences) {
        currentPublication?.let {
            // TODO: Get initial locator
            TTSNavigator(it, this, null, ttsPrefs).apply { initNavigator() }
        } ?: throw Exception("Publication not opened cannot enable tts")
    }

    fun ttsSetPreferences(ttsPrefs: AndroidTtsPreferences) {
        ttsNavigator?.updatePreferences(ttsPrefs)
            ?: throw Exception("TTS is not enabled, can't set preferences")
    }

    fun ttsSetDecorationStyle(uttStyle: Decoration.Style?, rangeStyle: Decoration.Style?) {
        ttsNavigator?.let {
            it.setUtteranceStyle(uttStyle)
            it.setCurrentRangeStyle(rangeStyle)
        } ?: throw Exception("TTS is not enabled, can't set decoration style")
    }

    fun ttsGetAvailableVoices(): Set<AndroidTtsEngine.Voice>? {
        return ttsNavigator?.voices
    }

    fun ttsSetPreferredVoice(voiceId: String?, language: String?) {
        if (voiceId != null) {
            ttsNavigator?.setPreferredVoice(voiceId, language)
        }
    }

    suspend fun play(fromLocator: Locator?) {
        // If using TTS and no fromLocator given, start from current visible locator.
        if (fromLocator == null && ttsNavigator != null) {
            currentReaderWidget?.getFirstVisibleLocator()
        }

        audiobookNavigator?.play(fromLocator)
        ttsNavigator?.play(fromLocator)
    }

    fun pause() {
        audiobookNavigator?.pause()
        ttsNavigator?.pause()
    }

    fun resume() {
        audiobookNavigator?.resume()
        ttsNavigator?.resume()
    }

    fun stop() {
        audiobookNavigator?.pause()
        audiobookNavigator?.dispose()
        ttsNavigator?.dispose()

        // Remove any current TTS decorations
        epubNavigator?.applyDecorations(emptyList(), "tts")
    }

    fun next() {
        // TODO: seek by audioPreferences.seekInterval
        //audioNavigator?.seekBy(audioPreferences.seekInterval)
        ttsNavigator?.nextUtterance()
    }

    fun previous() {
        // TODO: seek by audioPreferences.seekInterval
        //audioNavigator?.seekBy(-1 * audioPreferences.seekInterval)
        ttsNavigator?.previousUtterance()
    }

    suspend fun audioEnable(initialLocator: Locator?, exoPreferences: ExoPlayerPreferences) {
        currentPublication?.let {
            // TODO: Handle karaoke books, this only works for plain audiobooks.
            audiobookNavigator = AudiobookNavigator(
                it,
                this,
                initialLocator,
                exoPreferences
            )

            audiobookNavigator?.initNavigator()
            audiobookNavigator?.play()
        } ?: throw Exception("Publication not opened")
    }

    fun audioUpdatePreferences(exoPreferences: ExoPlayerPreferences) {
        audiobookNavigator?.updatePreferences(exoPreferences)
            ?: throw Exception("Audio not enabled, cannot update preferences")
    }

    fun applyDecorations(
        decorations: List<Decoration>,
        group: String
    ) {
        epubNavigator?.applyDecorations(decorations, group)
    }

    override fun onPageLoaded() {
        currentReaderWidget?.onPageLoaded()
    }

    override fun onPageChanged(
        pageIndex: Int,
        totalPages: Int,
        locator: Locator
    ) {
        currentReaderWidget?.onPageChanged(pageIndex, totalPages, locator)
    }

    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        currentReaderWidget?.onExternalLinkActivated(url)
    }

    override fun onVisualCurrentLocationChanged(locator: Locator) {
        currentReaderWidget?.onVisualCurrentLocationChanged(locator)
    }

    override fun onVisualReaderIsReady() {
        currentReaderWidget?.onVisualReaderIsReady()
    }
}

/// Values must match order of OpeningReadiumExceptionType in readium_exceptions.dart.
internal fun openingExceptionIndex(exception: OpenError): Int =
    when (exception) {
        is OpenError.Reading -> 0
        is OpenError.FormatNotSupported -> 1
    }

private fun parseMediaType(mediaType: Any?): MediaType? {
    @Suppress("UNCHECKED_CAST")
    val list = mediaType as List<String?>? ?: return null
    return MediaType(list[0]!!)
}