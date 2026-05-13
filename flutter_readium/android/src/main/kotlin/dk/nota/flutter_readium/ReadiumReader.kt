package dk.nota.flutter_readium

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import androidx.fragment.app.FragmentManager
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryOwner
import dk.nota.flutter_readium.events.ReadiumError
import dk.nota.flutter_readium.events.ReadiumErrorEventChannel
import dk.nota.flutter_readium.events.ReadiumReaderStatus
import dk.nota.flutter_readium.events.ReadiumReaderStatusEventChannel
import dk.nota.flutter_readium.events.TextLocatorEventChannel
import dk.nota.flutter_readium.events.TimedBasedStateEventChannel
import dk.nota.flutter_readium.models.ReadiumTimebasedState
import dk.nota.flutter_readium.navigators.AudiobookNavigator
import dk.nota.flutter_readium.navigators.EpubNavigator
import dk.nota.flutter_readium.navigators.SyncAudiobookNavigator
import dk.nota.flutter_readium.navigators.TTSNavigator
import dk.nota.flutter_readium.navigators.TimebasedNavigator
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.readium.navigator.media.tts.android.AndroidTtsEngine
import org.readium.navigator.media.tts.android.AndroidTtsPreferences
import org.readium.navigator.media.tts.android.AndroidTtsSettings
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.extensions.normalizeLocator
import org.readium.r2.shared.DelicateReadiumApi
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.LocatorCollection
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.html.cssSelector
import org.readium.r2.shared.publication.services.search.SearchService
import org.readium.r2.shared.publication.services.search.search
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.DebugError
import org.readium.r2.shared.util.Language
import org.readium.r2.shared.util.ThrowableError
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Try.Companion.failure
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.asset.Asset
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.data.Container
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.http.HttpRequest
import org.readium.r2.shared.util.http.HttpTry
import org.readium.r2.shared.util.resource.Resource
import org.readium.r2.shared.util.resource.TransformingContainer
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.PublicationOpener.OpenError
import org.readium.r2.streamer.parser.DefaultPublicationParser
import java.lang.ref.WeakReference
import kotlin.time.Duration

private const val TAG = "ReadiumReader"

private const val stateKey = "dk.nota.flutter_readium.ReadiumReaderState"

private const val currentPublicationUrlKey = "currentPublicationUrl"
private const val ttsEnabledKey = "ttsEnabled"
private const val audioEnabledKey = "audioEnabled"
private const val syncAudioEnabledKey = "syncAudioEnabled"

private const val epubEnabledKey = "epubEnabled"
private const val ttsNavigatorStateKey = "ttsState"
private const val audioNavigatorStateKey = "audioState"
private const val syncAudioNavigatorStateKey = "syncAudioState"
private const val epubNavigatorStateKey = "epubState"
private const val decorationStyleKey = "decorationStyle"

// TODO: Support custom headers and authentication header for content files.

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class, DelicateReadiumApi::class)
object ReadiumReader : TimebasedNavigator.TimebasedListener, EpubNavigator.VisualListener {
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val jobs = mutableListOf<Job>()

    private var appRef: WeakReference<Application>? = null

    private var timedBasedStateEventChannel: TimedBasedStateEventChannel? = null

    private var textLocatorEventChannel: TextLocatorEventChannel? = null

    private var readiumReaderStatusEventChannel: ReadiumReaderStatusEventChannel? = null

    private var errorChannel: ReadiumErrorEventChannel? = null

    private var readerViewRef: WeakReference<ReadiumReaderWidget>? = null

    private var savedStateRef: WeakReference<SavedStateRegistry>? = null

    // in-memory cached state
    private val state = mutableMapOf<String, Any?>()

    private val currentReadiumTimebasedState =
        MutableStateFlow(ReadiumTimebasedState.none())

    private val currentTextLocator = MutableStateFlow<Locator?>(null)

    private var defaultHttpHeaders = mutableMapOf<String, String>()

    var decorationStyle: FlutterDecorationPreferences
        get() =
            state[decorationStyleKey] as? FlutterDecorationPreferences
                ?: FlutterDecorationPreferences()
        set(value) {
            state[decorationStyleKey] = value
        }

    private val httpClient by lazy {
        DefaultHttpClient(
            callback =
                object : DefaultHttpClient.Callback {
                    override suspend fun onStartRequest(request: HttpRequest): HttpTry<HttpRequest> {
                        val requestWithHeaders =
                            request.copy {
                                defaultHttpHeaders.toMap().forEach { (key, value) ->
                                    setHeader(key, value)
                                }
                            }
                        return Try.success(requestWithHeaders)
                    }
                },
        )
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
    private var syncAudiobookNavigator: SyncAudiobookNavigator? = null

    private val timebasedNavigator: TimebasedNavigator<*>?
        get() = audiobookNavigator ?: syncAudiobookNavigator ?: ttsNavigator

    private var epubNavigator: EpubNavigator? = null

    private var _audioPreferences: FlutterAudioPreferences = FlutterAudioPreferences()

    /** Current audio preferences (defaults if audio hasn't been enabled yet). */
    val audioPreferences: FlutterAudioPreferences
        get() = _audioPreferences

    /**
     * The PublicationFactory is used to open publications.
     */
    private val publicationOpener: PublicationOpener
        get() {
            if (_publicationOpener == null) {
                _publicationOpener =
                    PublicationOpener(
                        publicationParser =
                            DefaultPublicationParser(
                                context,
                                assetRetriever = assetRetriever,
                                httpClient = httpClient,
                                // Only required if you want to support PDF files using the PDFium adapter.
                                pdfFactory = null, // PdfiumDocumentFactory(context)
                            ),
                    )
            }

            return _publicationOpener!!
        }

    // Initialize from plugin or anywhere you have an Application or Context.
    fun attach(
        activity: Activity,
        messenger: BinaryMessenger,
    ) {
        unwrapToApplication(activity)?.let { appRef = WeakReference(it) }

        timedBasedStateEventChannel?.dispose()
        timedBasedStateEventChannel = TimedBasedStateEventChannel(messenger)

        textLocatorEventChannel?.dispose()
        textLocatorEventChannel = TextLocatorEventChannel(messenger)

        readiumReaderStatusEventChannel?.dispose()
        readiumReaderStatusEventChannel = ReadiumReaderStatusEventChannel(messenger)

        errorChannel?.dispose()
        errorChannel = ReadiumErrorEventChannel(messenger)

        // store weak ref only
        (activity as? SavedStateRegistryOwner)?.savedStateRegistry?.let {
            savedStateRef = WeakReference(it)
            it.registerSavedStateProvider(stateKey) {
                storeState()
            }

            restoreState(it.consumeRestoredStateForKey(stateKey))
        }

        currentReadiumTimebasedState
            .onEach {
                Log.d(
                    TAG,
                    "currentTimebasedReaderState: ${
                        jsonEncode(
                            it.toJSON(),
                        )
                    }",
                )

                timedBasedStateEventChannel?.sendEvent(it)
            }.launchIn(mainScope)
            .let { jobs.add(it) }
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
            putBoolean(syncAudioEnabledKey, syncAudiobookNavigator != null)
            putBundle(syncAudioNavigatorStateKey, syncAudiobookNavigator?.storeState())
            putParcelable(decorationStyleKey, decorationStyle)
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
            val pub =
                openPublication(pubUrl).getOrElse {
                    Log.d(TAG, ":restoreState - failed to restore publication")
                    // TODO: Handle this somehow
                    return@launch
                }

            decorationStyle =
                bundle.getParcelable(decorationStyleKey) as? FlutterDecorationPreferences
                    ?: FlutterDecorationPreferences()

            if (bundle.getBoolean(epubEnabledKey)) {
                Log.d(TAG, ":storeState - restore epub navigator")
                bundle.getBundle(epubNavigatorStateKey)?.let { state ->
                    epubNavigator =
                        EpubNavigator.restoreState(pub, this@ReadiumReader, state).apply {
                            initNavigator()
                            Log.d(TAG, ":storeState - epubNavigator restored")
                            setDecorationStyle(decorationStyle)
                        }
                }
            }

            if (bundle.getBoolean(ttsEnabledKey)) {
                // Restore TTS navigator
                Log.d(TAG, ":storeState - restore tts navigator")
                bundle.getBundle(ttsNavigatorStateKey)?.let { state ->
                    ttsNavigator =
                        TTSNavigator.restoreState(pub, this@ReadiumReader, state).apply {
                            initNavigator()
                            Log.d(TAG, ":storeState - ttsNavigator restored")
                        }
                }
            }

            if (bundle.getBoolean(audioEnabledKey)) {
                // Restore Audio navigator
                Log.d(TAG, ":storeState - restore audio navigator")
                bundle.getBundle(audioNavigatorStateKey)?.let { state ->
                    audiobookNavigator =
                        AudiobookNavigator.restoreState(pub, this@ReadiumReader, state).apply {
                            initNavigator()
                            Log.d(TAG, ":storeState - audioNavigator restored")
                        }
                }
            } else if (bundle.getBoolean(syncAudioEnabledKey)) {
                // Restore Sync Audio navigator
                Log.d(TAG, ":storeState - restore sync audio navigator")
                val (ap, mediaOverlays) = pub.makeSyncAudiobook()
                if (mediaOverlays != null) {
                    bundle.getBundle(syncAudioNavigatorStateKey)?.let { state ->
                        syncAudiobookNavigator =
                            SyncAudiobookNavigator
                                .restoreState(
                                    ap,
                                    mediaOverlays,
                                    this@ReadiumReader,
                                    state,
                                ).apply {
                                    initNavigator()
                                    Log.d(TAG, ":storeState - syncAudioNavigator restored")
                                }
                    }
                } else {
                    Log.e(TAG, ":storeState - no media overlays for sync audio navigator")
                }
            }

            Log.d(TAG, "consumeRestoredStateForKey - 2 - $currentPublication")
        }
    }

    fun detach() {
        mainScope.launch {
            closePublication()
        }

        appRef?.clear()
        appRef = null

        savedStateRef?.clear()
        savedStateRef = null

        _assetRetriever = null
        _publicationOpener = null

        readerViewRef?.clear()
        readerViewRef = null

        timedBasedStateEventChannel?.dispose()
        timedBasedStateEventChannel = null

        textLocatorEventChannel?.dispose()
        textLocatorEventChannel = null

        readiumReaderStatusEventChannel?.dispose()
        readiumReaderStatusEventChannel = null

        errorChannel?.dispose()
        errorChannel = null

        jobs.forEach { it.cancel() }
        jobs.clear()
        mainScope.coroutineContext.cancelChildren()
    }

    // Safe getter — returns applicationContext or throws if not available.
    val application: Application
        get() =
            appRef?.get()
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

    /***
     * For EPUB profile, maps document [Url] to a list of all the cssSelectors in the document.
     *
     * This is used to find the current toc item.
     */
    private var currentPublicationCssSelectorMap: MutableMap<Url, List<String>>? = null

    /**
     * Sets the headers used in the HTTP requests for fetching publication resources, including
     * resources in already created `Publication` objects.
     *
     * @param headers a map of HTTP header key value pairs.
     */
    fun setDefaultHttpHeaders(headers: Map<String, String>) {
        defaultHttpHeaders.clear()
        defaultHttpHeaders.putAll(headers)
    }

    private suspend fun assetToPublication(
        asset: Asset,
        transformingContainerFactory: ((Container<Resource>) -> Container<Resource>)? = null,
    ): Try<Publication, OpenError> {
        val publication: Publication =
            publicationOpener
                .open(asset, allowUserInteraction = true, onCreatePublication = {
                    container = transformingContainerFactory?.let { it(container) } ?: container
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
    suspend fun loadPublication(pubUrl: String?): Try<Publication, PublicationError> {
        if (pubUrl == null) {
            return failure(
                PublicationError.Unexpected(
                    DebugError("missing argument"),
                ),
            )
        }

        return AbsoluteUrl.invoke(pubUrl)?.let { pubUrl -> loadPublication(pubUrl) } ?: failure(
            PublicationError.Unexpected(
                DebugError("Invalid Url"),
            ),
        )
    }

    /**
     * Load a publication from an AbsoluteUrl
     *
     * Note: Remember to close the publication to avoid leaks.
     */
    suspend fun loadPublication(
        pubUrl: AbsoluteUrl,
        transformingContainerFactory: ((Container<Resource>) -> Container<Resource>)? = null,
    ): Try<Publication, PublicationError> {
        if (currentPublicationUrl == pubUrl.toString()) {
            // Current publication is the same as the one we are trying to load, return it.
            currentPublication?.let {
                return Try.success(it)
            }
        }

        return withContext(Dispatchers.IO) {
            try {
                // TODO: should client provide mediaType to assetRetriever?
                val asset: Asset =
                    assetRetriever
                        .retrieve(pubUrl)
                        .getOrElse { error: AssetRetriever.RetrieveUrlError ->
                            Log.e(TAG, "Error retrieving asset: $error from url:$pubUrl")
                            return@withContext failure(PublicationError.invoke(error))
                        }
                val pub =
                    assetToPublication(
                        asset,
                        transformingContainerFactory,
                    ).getOrElse { error: OpenError ->
                        Log.e(
                            TAG,
                            "Error loading asset to Publication object: $error from url:$pubUrl",
                        )
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
    suspend fun openPublication(pubUrl: String?): Try<Publication, PublicationError> {
        if (pubUrl == null) {
            return failure(
                PublicationError.Unexpected(
                    DebugError("missing argument"),
                ),
            )
        }

        return AbsoluteUrl.invoke(pubUrl)?.let { pubUrl -> openPublication(pubUrl) } ?: failure(
            PublicationError.Unexpected(
                DebugError("Invalid Url"),
            ),
        )
    }

    /**
     * Open a publication and set it as the current publication.
     */
    suspend fun openPublication(pubUrl: AbsoluteUrl): Try<Publication, PublicationError> {
        if (currentPublicationUrl == pubUrl.toString()) {
            // Current publication is the same as the one we are trying to open, return it.
            // If you need to reload the publication, you need to close it first.
            currentPublication?.let {
                return Try.success(it)
            }
        }

        // Close previously opened publication to avoid leaks.
        closePublication()

        val transformingContainerFactory =
            fun(container: Container<Resource>): Container<Resource> {
                return TransformingContainer(container) { url: Url, resource: Resource ->
                    val publication = currentPublication ?: return@TransformingContainer resource
                    val navigator = epubNavigator ?: return@TransformingContainer resource

                    val tocIds =
                        publication.tableOfContents
                            .flattenChildren()
                            .mapNotNull { it.href.resolve().fragment }
                    val epubPreferences = navigator.preferences
                    if (url.extension?.value?.endsWith("html", ignoreCase = true) == true) {
                        resource.injectScriptsAndStyles(tocIds, epubPreferences)
                    } else {
                        resource
                    }
                }
            }

        val pub =
            loadPublication(
                pubUrl,
                transformingContainerFactory,
            ).getOrElse { e -> return failure(e) }

        _currentPublication = pub
        currentPublicationUrl = pubUrl.toString()

        return Try.success(pub)
    }

    /**
     * Load a publication from a URL
     * Note: Remember to close the publication to avoid leaks.
     */
    suspend fun loadPublicationFromUrl(urlStr: String): Try<Publication, PublicationError> {
        val pubUrl =
            resolvePubUrl(urlStr).getOrElse {
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
        val pubUrl =
            resolvePubUrl(urlStr).getOrElse {
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
        val pubUrl =
            AbsoluteUrl(pubUrlStr) ?: return failure(
                PublicationError.InvalidPublicationUrl(pubUrlStr),
            )

        return Try.success(pubUrl)
    }

    fun closePublication() {
        _currentPublication?.close()
        _currentPublication = null
        currentPublicationCssSelectorMap = null

        ttsNavigator?.dispose()
        ttsNavigator = null
        audiobookNavigator?.dispose()
        audiobookNavigator = null
        syncAudiobookNavigator?.dispose()
        syncAudiobookNavigator = null

        _audioPreferences = FlutterAudioPreferences()

        currentReadiumTimebasedState.value = ReadiumTimebasedState()
        currentTextLocator.value = null

        state.clear()
    }

    override fun onTimebasedPlaybackStateChanged(timebasedState: TimebasedNavigator.TimebasedState) {
        Log.d(TAG, ":onTimebasedPlaybackStateChanged $timebasedState")
        currentReadiumTimebasedState.value = currentReadiumTimebasedState.value.copyWith(state = timebasedState)
    }

    override fun onTimebasedBufferChanged(buffer: Duration?) {
        Log.d(TAG, ":onTimebasedBufferChanged $buffer")

        currentReadiumTimebasedState.value = currentReadiumTimebasedState.value.copyWith(currentBuffered = buffer?.inWholeMilliseconds)
    }

    override fun onTimebasedPlaybackFailure(error: PublicationError) {
        Log.d(TAG, ":onTimebasedPlaybackFailure $error")

        errorChannel?.sendEvent(ReadiumError.invoke(error))
    }

    @OptIn(InternalReadiumApi::class)
    override fun onTimebasedCurrentLocatorChanges(
        locator: Locator,
        currentReadingOrderLink: Link?,
    ) {
        val duration = currentReadingOrderLink?.duration
        val timeOffset = locator.locations.timeWithDuration(duration)

        Log.d(TAG, ":onTimebasedCurrentLocatorChanges $locator, timeOffset=$timeOffset")

        currentReadiumTimebasedState.value =
            currentReadiumTimebasedState.value.copyWith(
                currentOffset = timeOffset?.inWholeMilliseconds?.toDouble(),
                currentDuration = duration?.let { it * 1000 },
                currentLocator = locator,
            )
    }

    override fun onTimebasedLocationChanged(locator: Locator) {
        Log.d(TAG, ":onTimebasedLocationChanged $locator")

        mainScope.launch {
            epubSyncToLocator(locator, true)
        }
    }

    /**
     * Find the current table of content item from a locator.
     */
    suspend fun epubEnrichLocatorWithTocHref(locator: Locator): Locator {
        val publication =
            currentPublication ?: run {
                Log.e(TAG, ":epubFindCurrentToc - no currentPublication")
                return locator
            }

        if (!publication.conformsTo(Publication.Profile.EPUB)) {
            Log.e(TAG, ":epubFindCurrentToc - not an EPUB profile")
            return locator
        }

        // This locator already has a tocHref, add title and return it.
        locator.locations.tocHref?.let { tocHref ->
            return locator.copy(title = publication.getTitleFromTocHref(tocHref))
        }

        val cssSelector =
            locator.locations.cssSelector ?: run {
                Log.e(TAG, ":epubFindCurrentToc - missing cssSelector in locator")
                return locator
            }

        val resultLocator = locator.copy()

        val cleanHref = resultLocator.href.cleanHref()
        val tocLinks =
            publication.tableOfContents.flattenChildren().filter {
                it.href
                    .resolve()
                    .cleanHref()
                    .path == cleanHref.path
            }

        val documentCssSelectors = epubGetAllDocumentCssSelectors(resultLocator.href)
        val idx =
            documentCssSelectors.indexOf(cssSelector).takeIf { it > -1 } ?: run {
                // cssSelector wasn't found in the list of document cssSelectors, best effort is to assume first
                Log.d(
                    TAG,
                    ":epubFindCurrentToc cssSelector:$cssSelector not found in contentIds, assume idx = 0",
                )
                0
            }

        val toc =
            tocLinks.associateBy { documentCssSelectors.indexOf("#${it.href.resolve().fragment}") }

        val tocItem =
            toc.entries.lastOrNull { it.key <= idx }?.value ?: toc.entries.firstOrNull()?.value
                ?: run {
                    Log.d(TAG, ":epubFindCurrentToc - no tocItem found")
                    return resultLocator
                }

        return resultLocator
            .copy(
                title = tocItem.title,
            ).copyWithTocHref(tocItem)
    }

    @OptIn(InternalReadiumApi::class)
    suspend fun epubEnable(
        initialLocator: Locator?,
        initialPreferences: FlutterEpubPreferences,
        fragmentManager: FragmentManager,
        viewGroup: ViewGroup,
        readerWidget: ReadiumReaderWidget,
    ) {
        val pub = currentPublication ?: throw Exception("Publication not opened cannot enable epub")

        currentReaderWidget = readerWidget

        val isEpub = pub.conformsTo(Publication.Profile.EPUB)
        if (!isEpub) {
            throw Exception("Publication is not an EPUB, cannot enable epub navigator")
        }

        withScope(mainScope) {
            epubNavigator?.let {
                attachEpubNavigator(fragmentManager, viewGroup)
                return@withScope
            } // Already enabled - assume from restored state.

            EpubNavigator(pub, initialLocator, this@ReadiumReader, initialPreferences).apply {
                initNavigator()
                epubNavigator = this
                attachEpubNavigator(fragmentManager, viewGroup)
                setDecorationStyle(decorationStyle)
                return@withScope
            }
        }
    }

    suspend fun attachEpubNavigator(
        fragmentManager: FragmentManager?,
        viewGroup: ViewGroup?,
    ) {
        if (fragmentManager == null || viewGroup == null) {
            Log.d(TAG, "::attachEpubNavigator: Missing fragmentManager or viewGroup")
            return
        }

        val navigator =
            epubNavigator ?: run {
                Log.d(TAG, "::attachEpubNavigator: Tried to attach a non-existing epub navigator?")
                return
            }

        withScope(mainScope) {
            // Queue decorations to be applied when the epubNavigator is attached.
            decorationsUpdated()

            navigator.attachNavigator(fragmentManager, viewGroup)
        }
    }

    fun epubClose() {
        currentReaderWidget = null
        epubNavigator?.dispose()
        epubNavigator = null
    }

    suspend fun ttsEnable(ttsPrefs: FlutterTtsPreferences) {
        currentPublication?.let {
            ttsNavigator =
                TTSNavigator(it, this@ReadiumReader, currentTextLocator.value, ttsPrefs).apply {
                    initNavigator()
                }
        } ?: throw Exception("Publication not opened cannot enable tts")
    }

    suspend fun ttsSetPreferences(ttsPrefs: FlutterTtsPreferences) {
        ttsNavigator?.updatePreferences(ttsPrefs)
            ?: throw Exception("TTS is not enabled, can't set preferences")
    }

    suspend fun setDecorationStyle(style: FlutterDecorationPreferences) {
        decorationStyle = style

        decorationsUpdated()
    }

    suspend fun decorationsUpdated() {
        ttsNavigator?.decorationsUpdated()
        syncAudiobookNavigator?.decorationsUpdated()
    }

    /**
     * Cached list of android tts voices.
     */
    private var availableTtsVoices: Set<AndroidTtsEngine.Voice>? = null

    /**
     * Get available tts voices
     */
    suspend fun ttsGetAvailableVoices(): Set<AndroidTtsEngine.Voice> {
        // Already loaded, return existing list.
        availableTtsVoices?.takeIf { it.isNotEmpty() }?.let { return it }

        // Get the available voices from the TTS navigator.
        // If the TTS navigator hasn't been initialized, create a dummy AndroidTtsEngine.
        availableTtsVoices = ttsNavigator?.voices ?: AndroidTtsEngine
            .invoke(
                context,
                {
                    AndroidTtsSettings(
                        Language("C"),
                        false,
                        0.0,
                        0.0,
                        mapOf(),
                    )
                },
                { language, availableVoices -> null },
                AndroidTtsPreferences(),
            )?.voices

        return availableTtsVoices ?: setOf()
    }

    fun ttsGetPreferences(): FlutterTtsPreferences? = ttsNavigator?.preferences

    suspend fun ttsSetPreferredVoice(
        voiceId: String?,
        language: String?,
    ) {
        if (voiceId == null) {
            Log.d(TAG, ":ttsSetPreferredVoice - missing voiceId")
            return
        }

        if (language == null) {
            Log.d(TAG, ":ttsSetPreferredVoice - missing language")
            return
        }

        ttsNavigator?.setPreferredVoice(voiceId, language)
    }

    suspend fun play(locator: Locator?) {
        val fromLocator =
            locator ?: currentReadiumTimebasedState.value.currentLocator ?: currentTextLocator.value
                ?: epubFirstVisibleElementLocator()

        Log.d(TAG, ":play($locator) - fromLocator:$fromLocator")

        timebasedNavigator?.play(fromLocator)
    }

    suspend fun pause() {
        timebasedNavigator?.pause()
    }

    suspend fun resume() {
        timebasedNavigator?.resume()
    }

    suspend fun stop() {
        audiobookNavigator?.apply {
            pause()
            dispose()

            audiobookNavigator = null
        }

        syncAudiobookNavigator?.apply {
            pause()
            dispose()

            syncAudiobookNavigator = null
        }

        ttsNavigator?.apply {
            pause()
            dispose()

            ttsNavigator = null
        }

        currentReadiumTimebasedState.value = ReadiumTimebasedState.none()
    }

    /**
     * Skip backwards.
     */
    suspend fun previous() {
        timebasedNavigator?.goBackward()
    }

    /**
     * Skip forwards.
     */
    suspend fun next() {
        timebasedNavigator?.goForward()
    }

    /**
     * Go to a specific locator.
     */
    suspend fun goToLocator(locator: Locator) {
        val publication =
            currentPublication ?: run {
                Log.e(TAG, "::goToLocator called without a current publication")
                return
            }
        val toLocator = publication.normalizeLocator(locator)
        timebasedNavigator?.let { navigator ->
            Log.d(TAG, "::goToLocator - timebased $toLocator")
            navigator.goToLocator(
                toLocator.copy(
                    text = Locator.Text(),
                ),
            )

            return
        }

        epubGoToLocator(toLocator, true)
    }

    /**
     * Go to a progression value between 0.0 and 1.0
     */
    suspend fun goToProgression(progression: Double) {
        timebasedNavigator?.let { timebasedNavigator ->
            Log.d(TAG, "::goToProgression - timebased $progression")
            timebasedNavigator.seekToProgression(progression)

            return
        }

        epubGoToProgression(progression)
    }

    suspend fun searchInPublication(query: String): Try<List<LocatorCollection>, Error> {
        val pub =
            currentPublication ?: return failure(
                Error("no publication"),
            )
        val resultIterator =
            pub.search(query, SearchService.Options()) ?: return failure(
                Error("SearchService unavailable"),
            )
        val results = mutableListOf<LocatorCollection>()
        while (true) {
            val result = resultIterator.next()
            if (result.isFailure) break
            val collection = result.getOrNull() ?: break
            results.add(collection)
        }
        return Try.success(results.toList())
    }

    /**
     * Seek to a specific [offset] in seconds from the current position. Can be negative or positive.
     */
    suspend fun audioSeek(offset: Double) {
        val navigator =
            timebasedNavigator ?: run {
                Log.e(TAG, "::audioSeek - called with an active timebase navigator")
                return
            }

        navigator.seekTo(offset)
    }

    @OptIn(InternalReadiumApi::class)
    suspend fun audioEnable(
        locator: Locator?,
        preferences: FlutterAudioPreferences,
    ) {
        _audioPreferences = preferences

        val publication =
            currentPublication ?: run {
                throw Exception("Publication not opened")
            }

        val initialLocator = locator?.let { publication.normalizeLocator(it) }

        // Handle karaoke books - by creating a pseudo audio publication from the media overlays.
        val (ap, overlays) = publication.makeSyncAudiobook()

        audiobookNavigator?.dispose()
        syncAudiobookNavigator?.dispose()
        audiobookNavigator = null
        syncAudiobookNavigator = null

        if (overlays == null) {
            Log.d(TAG, "::audioEnable - plain audiobook")

            audiobookNavigator =
                AudiobookNavigator(
                    ap,
                    this@ReadiumReader,
                    initialLocator,
                    preferences,
                ).apply {
                    initNavigator()
                }
        } else {
            Log.d(TAG, "::audioEnable - media-overlay book")
            val ail = initialLocator ?: epubNavigator?.currentLocator?.value
            syncAudiobookNavigator =
                SyncAudiobookNavigator(
                    ap,
                    overlays,
                    this@ReadiumReader,
                    ail,
                    preferences,
                ).apply {
                    initNavigator()
                }
        }
    }

    suspend fun audioUpdatePreferences(preferences: FlutterAudioPreferences) {
        _audioPreferences = preferences

        val navigator =
            audiobookNavigator ?: syncAudiobookNavigator ?: run {
                Log.e(TAG, "::audioUpdatePreferences called without an active audiobook navigator")
                throw Exception("Audio not enabled, cannot update preferences")
            }

        navigator.updatePreferences(preferences)
    }

    suspend fun applyDecorations(
        decorations: List<Decoration>,
        group: String,
    ) {
        val navigator = epubNavigator ?: return

        navigator.applyDecorations(decorations, group)
    }

    override fun onPageLoaded() {
        currentReaderWidget?.onPageLoaded()
    }

    override fun onPageChanged(
        pageIndex: Int,
        totalPages: Int,
        locator: Locator,
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

    suspend fun epubFirstVisibleElementLocator(): Locator? {
        val navigator =
            epubNavigator ?: run {
                Log.d(TAG, ":epubFirstVisibleElementLocator called without a epubNavigator")
                return null
            }

        return navigator.firstVisibleElementLocator()
    }

    suspend fun epubEvaluateJavascript(script: String): String? {
        val navigator =
            epubNavigator ?: run {
                Log.d(TAG, ":epubEvaluateJavascript called without a epubNavigator")
                return null
            }

        return navigator.evaluateJavascript(script)
    }

    /**
     * Update EPUB navigator preferences.
     */
    suspend fun epubUpdatePreferences(preferences: FlutterEpubPreferences) {
        val navigator =
            epubNavigator ?: run {
                Log.d(TAG, ":epubUpdatePreferences called without a epubNavigator")
                return
            }

        navigator.updatePreferences(preferences)
    }

    /**
     * Navigate backward in the EPUB navigator.
     */
    suspend fun epubGoBackward(animated: Boolean) {
        val navigator =
            epubNavigator ?: run {
                Log.d(TAG, ":epubGoBackward called without a epubNavigator")
                return
            }

        navigator.goBackward(animated)
    }

    /**
     * Navigate forward in the EPUB navigator.
     */
    suspend fun epubGoForward(animated: Boolean) {
        val navigator =
            epubNavigator ?: run {
                Log.d(TAG, ":epubGoForward called without a epubNavigator")
                return
            }

        navigator.goForward(animated)
    }

    /**
     * Go to a specific locator in the EPUB navigator, this scrolls to the locator position if needed.
     */
    suspend fun epubGoToLocator(
        locator: Locator,
        animated: Boolean,
    ) {
        val publication =
            currentPublication ?: run {
                Log.e(TAG, "::epubGoToLocator called wihtout an open publication")
                return
            }

        val toLocator = publication.normalizeLocator(locator)

        val navigator =
            epubNavigator ?: run {
                Log.d(TAG, ":epubGoToLocator called without a epubNavigator")
                return
            }

        navigator.goToLocator(toLocator, animated)
    }

    suspend fun epubGoToProgression(progression: Double) {
        val navigator =
            epubNavigator ?: run {
                Log.d(TAG, ":epubGoToProgression called without a epubNavigator")
                return
            }

        navigator.scrollToProgression(progression)
    }

    /**
     * Sync epub to [SyncAudiobookNavigator] or [TTSNavigator]
     */
    suspend fun epubSyncToLocator(
        locator: Locator,
        animated: Boolean,
        segmentDuration: Double? = null,
    ) {
        val navigator = epubNavigator ?: return
        withScope(mainScope) {
            if (navigator.preferences?.disableSynchronization == true) {
                return@withScope
            }

            navigator.goToLocator(locator, animated, segmentDuration)
        }
    }

    /**
     * Get all cssSelectors for an EPUB file.
     * Note: These only includes text elements, so body, page breaks etc are not included.
     */
    suspend fun epubGetAllDocumentCssSelectors(href: Url): List<String> {
        val cssSelectorMap = currentPublicationCssSelectorMap ?: mutableMapOf()
        currentPublicationCssSelectorMap = cssSelectorMap

        val cleanHref = href.cleanHref()
        return cssSelectorMap.getOrPut(cleanHref) {
            currentPublication?.findAllCssSelectors(
                cleanHref,
            ) ?: listOf()
        }
    }

    /**
     * Emit reader status update to the flutter layer.
     */
    fun emitReaderStatusUpdate(statusUpdate: ReadiumReaderStatus) {
        readiumReaderStatusEventChannel?.sendEvent(statusUpdate)
    }

    /**
     * Emit an error event to the flutter layer.
     */
    fun emitError(error: ReadiumError) {
        errorChannel?.sendEvent(error)
    }

    /**
     * Emit text locator to the flutter layer
     */
    fun emitTextLocatorUpdate(locator: Locator) {
        textLocatorEventChannel?.sendEvent(locator)

        currentTextLocator.value = locator
    }
}
